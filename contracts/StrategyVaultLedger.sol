// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {
    Account,
    StrategyFund,
    UpdateStrategyFundAssetsParams,
    StrategyExecutionParams,
    BasicInfo,
    PendingState,
    StrategyExecution,
    Operation,
    OperationType,
    OperationRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    UpdateUserClaim,
    AllocateFundRes,
    SettleType,
    StrategyFundState,
    SettleParams
} from "./lib/types/LedgerStruct.sol";

import {VaultType, OperationData} from "./lib/types/VaultStruct.sol";
import {PayloadType} from "./lib/types/CrossChainStruct.sol";
import {StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {IStrategyVaultLedger} from "./interfaces/IStrategyVaultLedger.sol";
import {console} from "forge-std/console.sol";
//todo 1. sig verify 2. constant 3. admin access 4. repeat nonce

contract StrategyVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable, IStrategyVaultLedger {
    using Math for uint256;

    uint256 public priceDecimal;
    uint256 public shareDecimal;
    uint256 public assetsDecimal;

    uint256 public pendingMainShares;
    uint256 public pendingLpDepositAssets;
    uint256 public pendingLpWithdrawShares;

    uint256 public mainShares;
    uint256 public mainAssetsAfterFee;

    uint256 public latestPeriodId;

    address public crossChainManagerAddress;
    address public operatorAddress;
    /// @dev address of upload data to contract
    address public engineAddress;

    /// @dev fee rate of each strategy fund
    mapping(uint256 => uint256) public feeRateOfFund;
    /// @dev allowed strategy provider
    mapping(bytes32 => bool) public isAllowedStrategyProvider;
    /// @dev strategy fund information by strategy provider id
    mapping(bytes32 => StrategyFund) public strategyFundById;
    /// @dev account information by account id
    mapping(bytes32 => Account) public accountById;
    /// @dev Determines whether the operation corresponding to the nonce is executed by the contract
    mapping(uint256 => bool) public isOpHandeled;

    /// @notice Require only operator can call
    modifier onlyOperator() {
        if (msg.sender != operatorAddress) {
            revert InvalidCaller();
        }
        _;
    }
    /// @notice Require only crossChainManager can call

    modifier onlyVaultCrossChainManager() {
        if (msg.sender != crossChainManagerAddress) {
            revert InvalidCaller();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        __Ownable_init(owner);

        __UUPSUpgradeable_init();

        priceDecimal = 6;
        shareDecimal = 6;
        assetsDecimal = 6;
    }

    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

    //--------------------------------------FROM VAULT-----------------------------------------
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData memory operationData)
        external
        onlyVaultCrossChainManager
    {
        bytes32 accountId = operationData.accountId;
        bytes32 spId = operationData.strategyProviderId;

        Account storage account = accountById[accountId];
        StrategyFund storage strategyFund = strategyFundById[spId];

        if (payloadType == PayloadType.LP_DEPOSIT) {
            account.unAllocatedAssets += operationData.amount;
            account.assets += operationData.amount;
        } else if (payloadType == PayloadType.LP_WITHDRAW) {
            if (operationData.amount + account.frozenShares > account.shares) {
                revert NotEnoughWithdrawShare();
            }
            account.frozenShares += operationData.amount;
        } else if (payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.SP_WITHDRAW) {
            //check sp id is allowed
            if (!isAllowedStrategyProvider[spId]) {
                revert NotAllowedStrategyProvider();
            }
            if (payloadType == PayloadType.SP_DEPOSIT) {
                strategyFund.unAllocatedAssets += operationData.amount;
            } else {
                if (operationData.amount + strategyFund.frozenShares > strategyFund.totalShares) {
                    revert NotEnoughWithdrawShare();
                }
                strategyFund.frozenShares += operationData.amount;
            }
        } else {
            revert InvalidPayloadType();
        }

        emit OperationHandled(payloadType, chainId, operationData);
    }

    //--------------------------------------FROM BE--------------------------------------------
    function updateStrategyFundAssets(
        uint256 periodId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes memory signature
    ) external onlyOperator {
        _check(periodId);
        bytes32 messageHash = keccak256(abi.encode(periodId, strategyFundAssets));
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature);
        if (signer != engineAddress) {
            revert InvalidSigner();
        }
        uint256 assetsAfterFee;
        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            //gas optimization
            StrategyFund storage strategyFund = strategyFundById[strategyFundAssets[i].strategyProviderId];
            PendingState storage pendingState = strategyFund.pendingState;

            //reset performance fee
            strategyFund.pendingState.pendingPerformanceFee = 0;

            uint256 fundAssets = strategyFundAssets[i].totalAssets;
            uint256 fundShares = strategyFund.totalShares;

            //Performance Fee
            uint256 performanceFee;
            uint256 feeShares;
            uint256 assetPerShare = fundAssets * 10 ** priceDecimal / fundShares;
            // console.log("assetPerShare", assetPerShare);
            // console.log("strategyFund.hwm", strategyFund.hwm);
            if (assetPerShare > strategyFund.hwm) {
                performanceFee =
                    (assetPerShare - strategyFund.hwm) * fundShares * feeRateOfFund[i] / 100 / 10 ** priceDecimal;
                console.log("performanceFee", performanceFee);
                feeShares =
                    _convertToShares(performanceFee, fundAssets - performanceFee, fundShares, Math.Rounding.Floor);
                console.log("feeShares", feeShares);
                strategyFund.pendingState.pendingPerformanceFee = performanceFee;
            }

            //Update pending stateå
            strategyFund.pendingState.pendingTotalAssets = fundAssets;
            strategyFund.fundAssetsAfterFee = fundAssets - performanceFee;
            pendingState.pendingStrategyProviderShares += feeShares;
            pendingState.pendingTotalShares = fundShares + feeShares;
            assetsAfterFee += strategyFund.mainShares * (fundAssets - performanceFee) / strategyFund.totalShares;
        }

        mainAssetsAfterFee = assetsAfterFee;
        //console.log("mainAssetsAfterFee", mainAssetsAfterFee);

        //emit event
        PendingState[] memory pendingStates = new PendingState[](strategyFundAssets.length);
        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            pendingStates[i] = strategyFundById[strategyFundAssets[i].strategyProviderId].pendingState;
        }
        emit StrategyFundAssetsUpdate(periodId, mainAssetsAfterFee, pendingStates);
    }

    function updateLPAndStrategyFund(
        uint256 periodId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes memory signature
    ) external onlyOperator {
        _check(periodId);
        OperationRes[] memory operationRes = new OperationRes[](updateUserLedgerParams.length);
        uint256 amount;
        for (uint256 i = 0; i < updateUserLedgerParams.length; i++) {
            Operation memory operation = updateUserLedgerParams[i].operation;
            OperationType operationType = updateUserLedgerParams[i].operationType;
            if (operationType == OperationType.LP_DEPOSIT) {
                //handle LP deposit
                amount = _handleLpDeposit(operation.id, operation.amount);
            } else if (operationType == OperationType.LP_WITHDRAW) {
                //handle LP withdraw
                amount = _handleLpWithdraw(operation.id, operation.amount);
            } else if (operationType == OperationType.SP_DEPOSIT) {
                //handle SP deposit
                amount = _handleSPDeposit(operation.id, operation.amount);
            } else if (operationType == OperationType.SP_WITHDRAW) {
                //handle SP withdraw
                amount = _handleSpWithdraw(operation.id, operation.amount);
            } else {
                revert InvalidOpType();
            }
            operationRes[i] = OperationRes({id: operation.id, nonce: operation.nonce, amount: amount});
            isOpHandeled[operation.nonce] = true;
        }

        //emit event
        emit LPAndStrategyFundUpdated(periodId, pendingMainShares, operationRes);
    }

    function allocatToFunds(bytes32[] calldata strategyProviderIds) external onlyOperator {
        StrategyFund storage strategyFund;
        uint256 totalMainAssetsInFund;

        if (strategyProviderIds.length == 1) {
            strategyFund = strategyFundById[strategyProviderIds[0]];

            //deposit
            uint256 distributeDepositShares = _convertToShares(
                pendingLpDepositAssets, strategyFund.fundAssetsAfterFee, strategyFund.totalShares, Math.Rounding.Floor
            );
            strategyFund.pendingState.pendingTotalAssets += pendingLpDepositAssets;
            strategyFund.pendingState.pendingTotalShares += distributeDepositShares;
            strategyFund.pendingState.pendingMainShares += distributeDepositShares;

            //withdraws
            uint256 withdrawAssets =
                _convertToAssets(pendingLpWithdrawShares, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);
            strategyFund.pendingState.pendingTotalAssets -= withdrawAssets;
            strategyFund.pendingState.pendingMainShares -= pendingLpWithdrawShares;
            strategyFund.pendingState.pendingTotalShares -= pendingLpWithdrawShares;
        } else {
            for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                strategyFund = strategyFundById[strategyProviderIds[i]];
                totalMainAssetsInFund += _convertToAssets(
                    strategyFund.mainShares,
                    strategyFund.fundAssetsAfterFee,
                    strategyFund.totalShares,
                    Math.Rounding.Floor
                );
            }
            console.log("pendingLpDepositAssets", pendingLpDepositAssets);
            console.log("pendingLpWithdrawShares", pendingLpWithdrawShares);
            //allocate deposit
            if (pendingLpDepositAssets > 0) {
                for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                    strategyFund = strategyFundById[strategyProviderIds[i]];

                    uint256 mainAssetsInFund = _convertToAssets(
                        strategyFund.mainShares,
                        strategyFund.fundAssetsAfterFee,
                        strategyFund.totalShares,
                        Math.Rounding.Floor
                    );
                    uint256 distributeAssets =
                        pendingLpDepositAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Floor);

                    uint256 distributeShares = _convertToShares(
                        distributeAssets, strategyFund.fundAssetsAfterFee, strategyFund.totalShares, Math.Rounding.Floor
                    );
                    strategyFund.pendingState.pendingTotalAssets += distributeAssets;
                    strategyFund.pendingState.pendingTotalShares += distributeShares;
                    strategyFund.pendingState.pendingMainShares += distributeShares;
                }
            }
            //allocate withdraw
            if (pendingLpWithdrawShares > 0) {
                uint256 withdrawAssets =
                    _convertToAssets(pendingLpWithdrawShares, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);

                for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                    strategyFund = strategyFundById[strategyProviderIds[i]];

                    uint256 mainAssetsInFund = _convertToAssets(
                        strategyFund.mainShares,
                        strategyFund.fundAssetsAfterFee,
                        strategyFund.totalShares,
                        Math.Rounding.Floor
                    );
                    uint256 distributeAssets =
                        withdrawAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Ceil);
                    uint256 distributeShares = _convertToShares(
                        distributeAssets, strategyFund.fundAssetsAfterFee, strategyFund.totalShares, Math.Rounding.Floor
                    );
                    strategyFund.pendingState.pendingTotalAssets -= distributeAssets;
                    strategyFund.pendingState.pendingMainShares -= distributeShares;
                    strategyFund.pendingState.pendingTotalShares -= distributeShares;
                }
            }
        }

        //emit event
        AllocateFundRes[] memory allocateFundRes = new AllocateFundRes[](strategyProviderIds.length);
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            strategyFund = strategyFundById[strategyProviderIds[i]];
            allocateFundRes[i] = AllocateFundRes({
                totalAssets: strategyFund.pendingState.pendingTotalAssets,
                totalShares: strategyFund.pendingState.pendingTotalShares,
                mainShares: strategyFund.pendingState.pendingMainShares
            });
        }
        emit FundAllocated(strategyProviderIds, allocateFundRes);
    }

    function settleMainAndStrategyFunds(uint256 periodId, bytes32[] calldata strategyProviderIds)
        external
        onlyOperator
    {
        _check(periodId);

        //settle MAIN
        mainShares = pendingMainShares;
        StrategyFundState[] memory strategyFundStates = new StrategyFundState[](strategyProviderIds.length);

        //settle strategy fund
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            StrategyFund storage strategyFund = strategyFundById[strategyProviderIds[i]];

            //hwm must be updated firstly
            strategyFund.hwm = _calculateHWM(strategyProviderIds[i]);

            strategyFund.totalShares = strategyFund.pendingState.pendingTotalShares;
            strategyFund.totalAssets = strategyFund.pendingState.pendingTotalAssets;
            strategyFund.mainShares = strategyFund.pendingState.pendingMainShares;
            strategyFund.strategyProviderShares = strategyFund.pendingState.pendingStrategyProviderShares;

            //emit event
            strategyFundStates[i] = StrategyFundState({
                strategyProviderId: strategyProviderIds[i],
                totalShares: strategyFund.totalShares,
                totalAssets: strategyFund.totalAssets,
                mainShares: strategyFund.mainShares,
                strategyProviderShares: strategyFund.strategyProviderShares,
                hwm: strategyFund.hwm
            });
        }

        emit MainAndStrategyFundsSettled(periodId, mainShares, strategyFundStates);
    }

    function settleAccounts(uint256 periodId, bytes32[] calldata accountIds) external onlyOperator {
        _check(periodId);
        AccountState[] memory accountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            Account storage account = accountById[accountIds[i]];
            account.shares = account.pendingShares;

            //for event
            accountStates[i] = AccountState({accountId: accountIds[i], shares: account.shares});
        }

        emit AccountSettled(periodId, accountStates);
    }

    function updatePeriodId() external onlyOperator {
        pendingLpDepositAssets = 0;
        pendingLpWithdrawShares = 0;
        latestPeriodId++;

        emit PeriodIdUpdated(latestPeriodId);
    }

    function executeStrategy(
        uint256 periodId,
        StrategyExecutionParams memory strategyExecutionParams,
        bytes calldata signature
    ) external onlyOperator {
        uint256 totalTransferredAssets;

        for (uint256 i = 0; i < strategyExecutionParams.assetsDistributions.length; i++) {
            totalTransferredAssets += strategyExecutionParams.assetsDistributions[i].assets;
        }
        if (totalTransferredAssets != strategyExecutionParams.totalAssets) {
            revert InvalidTotalAssets();
        }

        for (uint256 i = 0; i < strategyExecutionParams.assetsDistributions.length; i++) {
            //contruct StrategyExecution
            StrategyExecution memory strategyExecution = StrategyExecution({
                basicInfo: BasicInfo({
                    vaultType: VaultType.USER,
                    periodId: periodId,
                    vaultId: strategyExecutionParams.basicInfo.vaultId,
                    tokenHash: strategyExecutionParams.basicInfo.tokenHash,
                    brokerHash: strategyExecutionParams.basicInfo.brokerHash
                }),
                chainId: strategyExecutionParams.assetsDistributions[i].chainId,
                amount: strategyExecutionParams.assetsDistributions[i].assets
            });
        }

        emit StrategyExecuted(periodId, totalTransferredAssets);
    }

    function updateUnclaimed(uint256 periodId, UpdateUserClaim[] memory updateUserClaims, bytes memory signature)
        external
        onlyOperator
    {
        // StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
        //     payloadType: uint8(payloadType),
        //     chainId: block.chainid,
        //     payload: abi.encode(periodId,updateUserClaims)
        // });
        //cross-chain message
        //IVaultCrossChainManager(crossChainManager).vaultSendToLedger{value: msg.value}(message);
    }
    //--------------------------------------CONFIG--------------------------------------------

    function setFeeRate(bytes32[] calldata strategyProviderIds) external {}

    function setCrossChainManagerAddress(address _crossChainManagerAddress) external onlyOwner {
        crossChainManagerAddress = _crossChainManagerAddress;

        emit CrossChainManagerAddressSet(_crossChainManagerAddress);
    }

    /// @notice Set the address of Strategy Provider
    /// @param spId Strategy Provider Id
    function setAllowedStrategyProvider(bytes32 spId, bool knob) external onlyOwner {
        isAllowedStrategyProvider[spId] = knob;

        emit AllowedStrategyProviderSet(spId, knob);
    }

    /// @notice Set the address of operatorManager contract
    /// @param _operatorAddress new operatorManagerAddress
    function setOperatorManager(address _operatorAddress) public onlyOwner {
        operatorAddress = _operatorAddress;

        emit OperatorManagerSet(_operatorAddress);
    }

    function setEngine(address _engineAddress) public onlyOwner {
        engineAddress = _engineAddress;
    }
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function checkMainAndStrategyFund(uint256 periodId, bytes32[] calldata strategyProviderIds)
        external
        view
        returns (StrategyFundState[] memory)
    {
        _check(periodId);
        StrategyFundState[] memory strategyFundStates = new StrategyFundState[](strategyProviderIds.length);

        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            StrategyFund storage strategyFund = strategyFundById[strategyProviderIds[i]];

            uint256 hwm = _calculateHWM(strategyProviderIds[i]);
            strategyFundStates[i] = StrategyFundState({
                strategyProviderId: strategyProviderIds[i],
                totalShares: strategyFund.totalShares,
                totalAssets: strategyFund.totalAssets,
                mainShares: strategyFund.mainShares,
                strategyProviderShares: strategyFund.strategyProviderShares,
                hwm: hwm
            });
        }
        return strategyFundStates;
    }

    function checkAccounts(uint256 periodId, bytes32[] calldata accountIds)
        external
        view
        returns (AccountState[] memory)
    {
        _check(periodId);
        AccountState[] memory accountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            Account storage account = accountById[accountIds[i]];
            accountStates[i] = AccountState({accountId: accountIds[i], shares: account.shares});
        }
        return accountStates;
    }

    function convertToShares(uint256 amount, uint256 _totalAssets, uint256 _toatlShares)
        external
        view
        returns (uint256)
    {
        return _convertToShares(amount, _totalAssets, _toatlShares, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _toatlShares)
        external
        view
        returns (uint256)
    {
        return _convertToAssets(shares, _totalAssets, _toatlShares, Math.Rounding.Floor);
    }

    function getStrategyFund(bytes32 spId) public view returns (StrategyFund memory) {
        return strategyFundById[spId];
    }
    /*=========================================================================================
    *                                       INTERNAL
    *=========================================================================================*/

    function _check(uint256 periodId) internal view {
        if (periodId != latestPeriodId) {
            revert InvalidPeriodId();
        }
    }

    function _handleLpDeposit(bytes32 accountId, uint256 amount) internal returns (uint256) {
        Account storage account = accountById[accountId];

        if (amount > account.unAllocatedAssets) {
            revert NotEnoughLPDeposit();
        }

        uint256 depositShares = _convertToShares(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);
        //effect
        account.pendingShares += depositShares;
        account.unAllocatedAssets -= amount;

        pendingMainShares += depositShares;
        pendingLpDepositAssets += amount;

        console.log("depositShares", depositShares);
        console.log("after depoist mainshares", pendingMainShares);
        return depositShares;
    }

    function _handleLpWithdraw(bytes32 accountId, uint256 amount) internal returns (uint256) {
        Account storage account = accountById[accountId];

        if (amount > account.frozenShares) {
            revert NotEnoughWithdrawShare();
        }

        //effect
        uint256 withdrawAssets = _convertToAssets(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);

        account.pendingShares -= amount;
        account.frozenShares -= amount;
        pendingMainShares -= amount;
        pendingLpWithdrawShares += amount;

        console.log("after withdrw mainshares", pendingMainShares);
        return withdrawAssets;
    }

    function _handleSPDeposit(bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFund storage strategyFund = strategyFundById[strategyProviderId];
        PendingState storage pendingState = strategyFund.pendingState;
        if (amount > strategyFund.unAllocatedAssets) {
            revert NotEnoughSPDeposit();
        }
        //console.log("SP deposit amount", amount);
        console.log("strategyFund.fundAssetsAfterFee", strategyFund.fundAssetsAfterFee);
        uint256 depositShares =
            _convertToShares(amount, strategyFund.fundAssetsAfterFee, strategyFund.totalShares, Math.Rounding.Floor);

        pendingState.pendingTotalShares += depositShares;
        pendingState.pendingStrategyProviderShares += depositShares;
        pendingState.pendingTotalAssets += amount;
        strategyFund.unAllocatedAssets -= amount;
        console.log("deposit SP Shares", depositShares);
        return depositShares;
    }

    function _handleSpWithdraw(bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFund storage strategyFund = strategyFundById[strategyProviderId];
        PendingState storage pendingState = strategyFund.pendingState;

        if (amount > strategyFund.frozenShares) {
            revert NotEnoughWithdrawShare();
        }
        uint256 spWithdrawAmount =
            _convertToAssets(amount, strategyFund.fundAssetsAfterFee, strategyFund.totalShares, Math.Rounding.Floor);

        //effect
        pendingState.pendingTotalShares -= amount;
        pendingState.pendingStrategyProviderShares -= amount;
        pendingState.pendingTotalAssets -= spWithdrawAmount;
        strategyFund.frozenShares -= amount;
        return spWithdrawAmount;
    }

    function _calculateHWM(bytes32 strategyProviderId) internal view returns (uint256) {
        StrategyFund memory strategyFund;
        strategyFund = strategyFundById[strategyProviderId];

        uint256 hwm = strategyFund.hwm;
        uint256 totalShares = strategyFund.totalShares;
        if (strategyFund.pendingState.pendingPerformanceFee > 0) {
            hwm = strategyFund.fundAssetsAfterFee * 10 ** priceDecimal / totalShares;
        } else {
            uint256 pendingTotalShares = strategyFund.pendingState.pendingTotalShares;
            //New issued shares greater than 0
            if (pendingTotalShares > totalShares) {
                uint256 newTotalIssuedShares = pendingTotalShares - totalShares;
                //calculate new hwm
                hwm = (
                    (
                        strategyFund.hwm * totalShares / 10 ** priceDecimal
                            + newTotalIssuedShares * strategyFund.fundAssetsAfterFee / totalShares
                    )
                ) * 10 ** priceDecimal / pendingTotalShares;
            }
        }
        return hwm;
    }

    /**
     * @dev Internal conversion function (from assets amount to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 amount, uint256 _totalAssets, uint256 _toatlShares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return (_toatlShares == 0)
            ? amount.mulDiv(10 ** shareDecimal, 10 ** assetsDecimal, rounding)
            : amount.mulDiv(_toatlShares, _totalAssets, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _toatlShares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 assets)
    {
        return (_toatlShares == 0)
            ? shares.mulDiv(10 ** assetsDecimal, 10 ** shareDecimal, rounding)
            : shares.mulDiv(_totalAssets, _toatlShares, rounding);
    }
}
