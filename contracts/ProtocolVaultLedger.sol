// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    Account,
    StrategyFund,
    UpdateStrategyFundAssetsParams,
    UpdateStrategyFundAssetsRes,
    PendingState,
    Operation,
    OperationType,
    OperationRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    UpdateUserClaim,
    AllocateFundRes,
    StrategyFundState
} from "./lib/types/LedgerStruct.sol";
import {Signature} from "./lib/utils/Signature.sol";
import {VaultType, OperationData} from "./lib/types/VaultStruct.sol";
import {PayloadType} from "./lib/types/CrossChainStruct.sol";
import {StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVaultLedger} from "./interfaces/IProtocolVaultLedger.sol";
import {console} from "forge-std/console.sol";

contract ProtocolVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable, IProtocolVaultLedger {
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

    address public crossChainManager;
    address public operator;
    /// @dev address of upload data to contract
    address public engine;

    /// @dev fee rate of each strategy fund
    mapping(uint256 => uint256) public feeRateOfFund;
    /// @dev allowed strategy provider
    mapping(bytes32 => bool) public isAllowedStrategyProvider;
    /// @dev strategy fund information by strategy provider id
    mapping(bytes32 => StrategyFund) public strategyFundById;
    /// @dev account information by account id
    mapping(bytes32 => Account) public accountById;
    /// @dev Determines whether the operation corresponding to the requestId is executed by the contract
    mapping(bytes32 => bool) public isOpHandeled;
    mapping(bytes32 => bool) public isClaimedHandled;

    /// @notice Require only operator can call
    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert InvalidCaller();
        }
        _;
    }
    /// @notice Require only crossChainManager can call

    modifier onlyVaultCrossChainManager() {
        if (msg.sender != crossChainManager) {
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

        //gas optimization
        Account storage account = accountById[accountId];
        StrategyFund storage strategyFund = strategyFundById[spId];

        uint256 amount = operationData.amount;

        if (payloadType == PayloadType.LP_DEPOSIT) {
            account.unAllocatedAssets += amount;
            account.assets += amount;
        } else if (payloadType == PayloadType.LP_WITHDRAW) {
            if (amount + account.frozenShares > account.shares) {
                emit NotEnoughWithdrawShare();
                return;
            }
            account.frozenShares += amount;
        } else if (payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.SP_WITHDRAW) {
            //check sp id is allowed
            if (!isAllowedStrategyProvider[spId]) {
                //revert NotAllowedStrategyProvider();
                emit NotAllowedStrategyProvider(spId);
                return;
            }

            if (payloadType == PayloadType.SP_DEPOSIT) {
                strategyFund.unAllocatedAssets += amount;
            } else {
                if (amount + strategyFund.frozenShares > strategyFund.totalShares) {
                    emit NotEnoughWithdrawShare();
                    return;
                }
                strategyFund.frozenShares += amount;
            }
        } else {
            emit InvalidPayloadType();
            return;
        }

        emit OperationHandled(payloadType, chainId, operationData);
    }

    //--------------------------------------FROM BE--------------------------------------------
    function updateStrategyFundAssets(
        uint256 periodId,
        bytes32 vaultId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes memory signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyUpdateFundAssets(periodId, vaultId, strategyFundAssets, signature, engine);
        uint256 assetsAfterFee;
        //for event
        UpdateStrategyFundAssetsRes[] memory updateStrategyFundAssetsRes =
            new UpdateStrategyFundAssetsRes[](strategyFundAssets.length);

        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            //gas optimization
            StrategyFund storage strategyFund = strategyFundById[strategyFundAssets[i].strategyProviderId];
            PendingState storage pendingState = strategyFund.pendingState;

            //reset performance fee
            strategyFund.performanceFee = 0;

            uint256 fundAssets = strategyFundAssets[i].totalAssets;
            uint256 fundShares = strategyFund.totalShares;

            //Performance Fee
            uint256 performanceFee;
            uint256 feeShares;
            uint256 assetPerShare = fundAssets * 10 ** priceDecimal / fundShares;

            if (assetPerShare > strategyFund.hwm) {
                performanceFee =
                    (assetPerShare - strategyFund.hwm) * fundShares * feeRateOfFund[i] / 100 / 10 ** priceDecimal;

                feeShares =
                    _convertToShares(performanceFee, fundAssets - performanceFee, fundShares, Math.Rounding.Floor);

                strategyFund.performanceFee = performanceFee;
            }

            //Update pending state
            strategyFund.pendingState.pendingTotalAssets = fundAssets;
            strategyFund.fundAssetsAfterFee = fundAssets - performanceFee;
            pendingState.pendingStrategyProviderShares += feeShares;
            pendingState.pendingTotalShares = fundShares + feeShares;
            assetsAfterFee += strategyFund.mainShares * (fundAssets - performanceFee) / strategyFund.totalShares;

            //Add to event
            updateStrategyFundAssetsRes[i] = UpdateStrategyFundAssetsRes({
                strategyProviderId: strategyFundAssets[i].strategyProviderId,
                fundAssetsAfterFee: fundAssets - performanceFee,
                strategyProviderShares: pendingState.pendingStrategyProviderShares,
                totalShares: fundShares + feeShares
            });
        }

        mainAssetsAfterFee = assetsAfterFee;

        emit StrategyFundAssetsUpdate(periodId, vaultId, mainAssetsAfterFee, updateStrategyFundAssetsRes);
    }

    function updateLPAndStrategyFund(
        uint256 periodId,
        bytes32 vaultId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes memory signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyUpdateLPAndStrategyFund(periodId, vaultId, updateUserLedgerParams, signature, engine);

        OperationRes[] memory operationRes = new OperationRes[](updateUserLedgerParams.length);
        uint256 amount;
        for (uint256 i = 0; i < updateUserLedgerParams.length; i++) {
            bytes32 requsstId = updateUserLedgerParams[i].operation.requestId;

            if (!isOpHandeled[requsstId]) {
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

                operationRes[i] = OperationRes({id: operation.id, requestId: operation.requestId, amount: amount});
                isOpHandeled[operation.requestId] = true;
            }
        }

        //emit event
        emit LPAndStrategyFundUpdated(periodId, vaultId, operationRes);
    }

    function allocatToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyAllocatToFunds(periodId, vaultId, strategyProviderIds, signature, engine);

        StrategyFund storage strategyFund;
        uint256 totalMainAssetsInFund;

        //for event
        AllocateFundRes[] memory allocateFundRes = new AllocateFundRes[](strategyProviderIds.length);

        if (strategyProviderIds.length == 1) {
            strategyFund = strategyFundById[strategyProviderIds[0]];

            //deposit
            uint256 distributeDepositShares = _convertToShares(
                pendingLpDepositAssets, strategyFund.fundAssetsAfterFee, strategyFund.totalShares, Math.Rounding.Floor
            );
            strategyFund.pendingState.pendingTotalAssets += pendingLpDepositAssets;
            strategyFund.pendingState.pendingTotalShares += distributeDepositShares;
            strategyFund.pendingState.pendingMainShares += distributeDepositShares;

            //withdraw
            uint256 withdrawAssets =
                _convertToAssets(pendingLpWithdrawShares, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);
            strategyFund.pendingState.pendingTotalAssets -= withdrawAssets;
            strategyFund.pendingState.pendingMainShares -= pendingLpWithdrawShares;
            strategyFund.pendingState.pendingTotalShares -= pendingLpWithdrawShares;

            //event
            allocateFundRes[0] = AllocateFundRes({
                strategyProviderId: strategyProviderIds[0],
                totalDepositAssets: pendingLpDepositAssets,
                totalDepositShares: distributeDepositShares,
                totalWithdrawAssets: withdrawAssets,
                totalWithdrawShares: pendingLpWithdrawShares
            });
        } else {
            for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                strategyFund = strategyFundById[strategyProviderIds[i]];
                allocateFundRes[i].strategyProviderId = strategyProviderIds[i];
                totalMainAssetsInFund += _convertToAssets(
                    strategyFund.mainShares,
                    strategyFund.fundAssetsAfterFee,
                    strategyFund.totalShares,
                    Math.Rounding.Floor
                );
            }

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
                    uint256 distributeDepositAssets =
                        pendingLpDepositAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Floor);

                    uint256 distributeDepositShares = _convertToShares(
                        distributeDepositAssets,
                        strategyFund.fundAssetsAfterFee,
                        strategyFund.totalShares,
                        Math.Rounding.Floor
                    );
                    strategyFund.pendingState.pendingTotalAssets += distributeDepositAssets;
                    strategyFund.pendingState.pendingTotalShares += distributeDepositShares;
                    strategyFund.pendingState.pendingMainShares += distributeDepositShares;

                    //event
                    allocateFundRes[i].totalDepositAssets = distributeDepositAssets;
                    allocateFundRes[i].totalDepositShares = distributeDepositShares;
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
                    uint256 distributeWithdrawAssets =
                        withdrawAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Ceil);
                    uint256 distributeWithdrawShares = _convertToShares(
                        distributeWithdrawAssets,
                        strategyFund.fundAssetsAfterFee,
                        strategyFund.totalShares,
                        Math.Rounding.Floor
                    );
                    strategyFund.pendingState.pendingTotalAssets -= distributeWithdrawAssets;
                    strategyFund.pendingState.pendingMainShares -= distributeWithdrawShares;
                    strategyFund.pendingState.pendingTotalShares -= distributeWithdrawShares;
                    //event
                    allocateFundRes[i].totalWithdrawAssets = distributeWithdrawAssets;
                    allocateFundRes[i].totalWithdrawShares = distributeWithdrawShares;
                }
            }
        }

        emit FundAllocated(periodId, vaultId, strategyProviderIds, allocateFundRes);
    }

    function settleMainAndStrategyFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifySettleMainAndStrategyFunds(periodId, vaultId, strategyProviderIds, signature, engine);
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

        emit MainAndStrategyFundsSettled(periodId, vaultId, mainShares, strategyFundStates);
    }

    function settleAccounts(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds, bytes memory signature)
        external
        onlyOperator
    {
        _check(periodId);
        Signature.verifySettleAccount(periodId, vaultId, accountIds, signature, engine);

        AccountState[] memory accountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            Account storage account = accountById[accountIds[i]];
            account.shares = account.pendingShares;

            //for event
            accountStates[i] = AccountState({accountId: accountIds[i], shares: account.shares});
        }

        emit AccountSettled(periodId, vaultId, accountStates);
    }

    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes memory signature) external onlyOperator {
        if (periodId != latestPeriodId + 1) {
            revert InvalidPeriodId();
        }
        Signature.verifyUpdatePeriodId(periodId, vaultId, signature, engine);

        pendingLpDepositAssets = 0;
        pendingLpWithdrawShares = 0;
        latestPeriodId++;

        emit PeriodIdUpdated(periodId, vaultId);
    }

    function distributeAssets(
        uint256 periodId,
        bytes32 vaultId,
        AssetsDistribution[] memory assetsDistributions,
        bytes calldata signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyAssetsDistribution(periodId, vaultId, assetsDistributions, signature, engine);

        for (uint256 i = 0; i < assetsDistributions.length; i++) {
            //contruct StrategyExecution
            AssetsDistribution memory assetsDistribution =
                AssetsDistribution({chainId: assetsDistributions[i].chainId, assets: assetsDistributions[i].assets});

            //cross chain message
            StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
                payloadType: PayloadType.ASSETS_DISTRIBUTION,
                srcChainId: uint32(block.chainid),
                dstChainId: assetsDistributions[i].chainId,
                payload: abi.encode(periodId, assetsDistribution)
            });
            //cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit AssetsDistrubuted(periodId, vaultId);
    }

    /// @notice update user unClaimed assets info on a specific chain
    function updateUnclaimed(
        uint32 chainId,
        uint256 periodId,
        bytes32 vaultId,
        UpdateUserClaim[] memory updateUserClaims,
        bytes memory signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyUpdateUnclaimed(chainId, periodId, vaultId, updateUserClaims, signature, engine);

        //cross chain message
        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: PayloadType.UPDATE_USER_CLAIM,
            srcChainId: uint32(block.chainid),
            dstChainId: chainId,
            payload: abi.encode(periodId, updateUserClaims)
        });
        //cross-chain
        IVaultCrossChainManager(crossChainManager).sendMessage(message);

        emit UnclaimedAssetsUpdated(periodId, vaultId, updateUserClaims);
    }
    //--------------------------------------CONFIG--------------------------------------------

    function setFeeRate(bytes32[] calldata strategyProviderIds) external onlyOwner {}

    function setCrossChainManagerAddress(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;

        emit CrossChainManagerAddressSet(_crossChainManager);
    }

    function setAllowedStrategyProvider(
        bytes32 vaultId,
        address vault,
        address sp,
        bytes32 brokerHash,
        bytes32 spId,
        bool knob
    ) external onlyOwner {
        isAllowedStrategyProvider[spId] = knob;

        emit AllowedStrategyProviderSet(vaultId, vault, sp, brokerHash, spId, knob);
    }

    /// @notice Set the address of operatorManager contract
    /// @param _operator new operatorManagerAddress
    function setOperatorManager(address _operator) public onlyOwner {
        operator = _operator;

        emit OperatorManagerSet(_operator);
    }

    function setEngine(address _engine) public onlyOwner {
        engine = _engine;
    }
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function checkMainAndStrategyFund(uint256 periodId, bytes32, bytes32[] calldata strategyProviderIds)
        external
        view
        returns (uint256, StrategyFundState[] memory)
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
        return (pendingMainShares, strategyFundStates);
    }

    function checkLP(uint256 periodId, bytes32[] calldata accountIds) external view returns (AccountState[] memory) {
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

        return depositShares;
    }

    function _handleLpWithdraw(bytes32 accountId, uint256 amount) internal returns (uint256) {
        Account storage account = accountById[accountId];

        if (amount > account.frozenShares) {
            revert NotEnoughFrozenShare();
        }

        //effect
        uint256 withdrawAssets = _convertToAssets(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);

        account.pendingShares -= amount;
        account.frozenShares -= amount;
        pendingMainShares -= amount;
        pendingLpWithdrawShares += amount;

        return withdrawAssets;
    }

    function _handleSPDeposit(bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFund storage strategyFund = strategyFundById[strategyProviderId];
        PendingState storage pendingState = strategyFund.pendingState;
        if (amount > strategyFund.unAllocatedAssets) {
            revert NotEnoughSPDeposit();
        }
        uint256 depositShares =
            _convertToShares(amount, strategyFund.fundAssetsAfterFee, strategyFund.totalShares, Math.Rounding.Floor);

        pendingState.pendingTotalShares += depositShares;
        pendingState.pendingStrategyProviderShares += depositShares;
        pendingState.pendingTotalAssets += amount;
        strategyFund.unAllocatedAssets -= amount;
        return depositShares;
    }

    function _handleSpWithdraw(bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFund storage strategyFund = strategyFundById[strategyProviderId];
        PendingState storage pendingState = strategyFund.pendingState;

        if (amount > strategyFund.frozenShares) {
            revert NotEnoughFrozenShare();
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
        if (strategyFund.performanceFee > 0) {
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
