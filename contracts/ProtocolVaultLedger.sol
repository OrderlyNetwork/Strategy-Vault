// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    AccountToken,
    StrategyFundToken,
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

/// @title protocol vault ledger
/// @notice This contract is used to record all information of protocol vault
contract ProtocolVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable, IProtocolVaultLedger {
    using Math for uint256;

    uint256 public constant FEE_BASE = 100;
    bytes32 constant USDC_HASH = 0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa;

    uint256 public priceDecimal;
    uint256 public shareDecimal;
    uint256 public assetsDecimal;

    uint256 public pendingMainShares;
    uint256 public pendingLpDepositAssets;
    uint256 public pendingLpWithdrawShares;

    uint256 public mainShares;
    uint256 public mainAssetsAfterFee;
    // @dev the latest period id that contract handle
    uint256 public latestPeriodId;

    /// @dev address of cross chain manager
    address public crossChainManager;
    /// @dev address of interact with ledger
    address public operator;
    /// @dev address of upload data to contract
    address public engine;

    /// @dev fee rate of each strategy fund by vault id
    mapping(bytes32 => uint256) public feeRateOfFund;
    /// @dev allowed strategy provider
    mapping(bytes32 => bool) public isAllowedStrategyProvider;
    /// @dev strategy fund information by strategy provider id
    mapping(bytes32 => mapping(bytes32 => StrategyFundToken)) public strategyFundTokenInfo;
    /// @dev account information by account id
    mapping(bytes32 => mapping(bytes32 => AccountToken)) public accountTokenInfo;
    /// @dev Determines whether the operation corresponding to the requestId is executed
    mapping(bytes32 => bool) public isOpHandeled;
    /// @dev Determines whether the claim corresponding to the requestId is executed
    mapping(bytes32 => bool) public isClaimedHandled;

    /// @notice Require only operator can call
    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert InvalidOperator();
        }
        _;
    }

    /// @notice Require only crossChainManager can call
    modifier onlyVaultCrossChainManager() {
        if (msg.sender != crossChainManager) {
            revert InvalidVaultCrossChainManager();
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
    /// @notice Handles operations from vault
    /// @param payloadType The type of operation
    /// @param chainId The source chain ID
    /// @param operationData The operation data
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData)
        external
        onlyVaultCrossChainManager
    {
        bytes32 accountId = operationData.accountId;
        bytes32 spId = operationData.strategyProviderId;

        //gas optimization
        AccountToken storage accountToken = accountTokenInfo[accountId][operationData.tokenHash];
        StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[spId][operationData.tokenHash];

        uint256 amount = operationData.amount;

        if (payloadType == PayloadType.LP_DEPOSIT) {
            accountToken.unAllocatedAssets += amount;
            accountToken.assets += amount;
        } else if (payloadType == PayloadType.LP_WITHDRAW) {
            _checkWithdraw(amount, accountToken.frozenShares, accountToken.shares);
            accountToken.frozenShares += amount;
        } else if (payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.SP_WITHDRAW) {
            //check sp id is allowed
            if (!isAllowedStrategyProvider[spId]) {
                emit NotAllowedStrategyProvider(spId);
                return;
            }
            if (payloadType == PayloadType.SP_DEPOSIT) {
                strategyFundToken.unAllocatedAssets += amount;
            } else {
                _checkWithdraw(amount, strategyFundToken.frozenShares, strategyFundToken.totalShares);
                strategyFundToken.frozenShares += amount;
            }
        } else {
            emit InvalidPayloadType();
            return;
        }

        emit OperationHandled(payloadType, chainId, operationData);
    }

    //--------------------------------------FROM Operator--------------------------------------------
    /// @notice Operator upload NAV of each strategy fund and compute performance fee at first of the period
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyFundAssets strategy fund assets info
    /// @param signature signature of BE
    function updateStrategyFundAssets(
        uint256 periodId,
        bytes32 vaultId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes calldata signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyUpdateFundAssets(periodId, vaultId, strategyFundAssets, signature, engine);

        uint256 assetsAfterFee;
        //for event
        UpdateStrategyFundAssetsRes[] memory updateStrategyFundAssetsRes =
            new UpdateStrategyFundAssetsRes[](strategyFundAssets.length);

        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            bytes32 spId = strategyFundAssets[i].strategyProviderId;
            //gas optimization
            StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[spId][USDC_HASH];
            PendingState storage pendingState = strategyFundToken.pendingState;

            //reset performance fee
            strategyFundToken.performanceFee = 0;

            uint256 fundAssets = strategyFundAssets[i].totalAssets;
            uint256 fundShares = strategyFundToken.totalShares;

            //Performance Fee
            uint256 performanceFee;
            uint256 feeShares;

            //avoid stack too deep
            {
                uint256 assetPerShare = fundAssets * 10 ** priceDecimal / fundShares;

                if (assetPerShare > strategyFundToken.hwm) {
                    performanceFee = (assetPerShare - strategyFundToken.hwm) * fundShares * feeRateOfFund[spId]
                        / FEE_BASE / 10 ** priceDecimal;
                    feeShares =
                        _convertToShares(performanceFee, fundAssets - performanceFee, fundShares, Math.Rounding.Floor);

                    strategyFundToken.performanceFee = performanceFee;
                }
            }

            //Update pending state
            strategyFundToken.pendingState.pendingTotalAssets = fundAssets;
            strategyFundToken.fundAssetsAfterFee = fundAssets - performanceFee;
            pendingState.pendingStrategyProviderShares += feeShares;
            pendingState.pendingTotalShares = fundShares + feeShares;
            assetsAfterFee +=
                strategyFundToken.mainShares * (fundAssets - performanceFee) / strategyFundToken.totalShares;

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

    /// @notice Operator update LP and strategy fund info
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param updateUserLedgerParams update user ledger info
    /// @param signature signature of BE
    function updateLPAndStrategyFund(
        uint256 periodId,
        bytes32 vaultId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes calldata signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyUpdateLPAndStrategyFund(periodId, vaultId, updateUserLedgerParams, signature, engine);

        OperationRes[] memory operationRes = new OperationRes[](updateUserLedgerParams.length);

        //handle lp operation
        for (uint256 i = 0; i < updateUserLedgerParams.length; i++) {
            bytes32 requestId = updateUserLedgerParams[i].operation.requestId;
            uint256 amount;

            if (!isOpHandeled[requestId]) {
                Operation memory operation = updateUserLedgerParams[i].operation;
                bytes32 id = operation.id;
                uint256 operationAmount = operation.amount;
                OperationType operationType = updateUserLedgerParams[i].operationType;

                if (operationType == OperationType.LP_DEPOSIT) {
                    //handle LP deposit
                    amount = _handleLpDeposit(id, operationAmount);
                } else if (operationType == OperationType.LP_WITHDRAW) {
                    //handle LP withdraw
                    amount = _handleLpWithdraw(id, operationAmount);
                } else if (operationType == OperationType.SP_DEPOSIT) {
                    //handle SP deposit
                    amount = _handleSPDeposit(id, operationAmount);
                } else if (operationType == OperationType.SP_WITHDRAW) {
                    //handle SP withdraw
                    amount = _handleSpWithdraw(id, operationAmount);
                } else {
                    revert InvalidOpType(operationType);
                }

                operationRes[i] = OperationRes({
                    id: operation.id,
                    requestId: operation.requestId,
                    amount: amount,
                    operationType: operationType
                });
                isOpHandeled[requestId] = true;
            }
        }

        //emit event
        emit LPAndStrategyFundUpdated(periodId, vaultId, operationRes);
    }

    /// @notice Operator allocate all lp deposit and withdraw to strategy funds after handle all lp operation
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyProviderIds each strategy provider id
    /// @param signature signature of BE
    function allocatToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyAllocatToFunds(periodId, vaultId, strategyProviderIds, signature, engine);

        StrategyFundToken storage strategyFundToken;
        uint256 totalMainAssetsInFund;

        //for event
        AllocateFundRes[] memory allocateFundRes = new AllocateFundRes[](strategyProviderIds.length);

        if (strategyProviderIds.length == 1) {
            strategyFundToken = strategyFundTokenInfo[strategyProviderIds[0]][USDC_HASH];

            //deposit
            uint256 distributeDepositShares = _convertToShares(
                pendingLpDepositAssets,
                strategyFundToken.fundAssetsAfterFee,
                strategyFundToken.totalShares,
                Math.Rounding.Floor
            );
            strategyFundToken.pendingState.pendingTotalAssets += pendingLpDepositAssets;
            strategyFundToken.pendingState.pendingTotalShares += distributeDepositShares;
            strategyFundToken.pendingState.pendingMainShares += distributeDepositShares;

            //withdraw
            uint256 withdrawAssets =
                _convertToAssets(pendingLpWithdrawShares, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);
            strategyFundToken.pendingState.pendingTotalAssets -= withdrawAssets;
            strategyFundToken.pendingState.pendingMainShares -= pendingLpWithdrawShares;
            strategyFundToken.pendingState.pendingTotalShares -= pendingLpWithdrawShares;

            //event
            allocateFundRes[0] = AllocateFundRes({
                strategyProviderId: strategyProviderIds[0],
                totalDepositAssets: pendingLpDepositAssets,
                totalDepositShares: distributeDepositShares,
                totalWithdrawAssets: withdrawAssets,
                totalWithdrawShares: pendingLpWithdrawShares
            });
        } else if (strategyProviderIds.length > 1) {
            for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                strategyFundToken = strategyFundTokenInfo[strategyProviderIds[i]][USDC_HASH];
                allocateFundRes[i].strategyProviderId = strategyProviderIds[i];
                totalMainAssetsInFund += _convertToAssets(
                    strategyFundToken.mainShares,
                    strategyFundToken.fundAssetsAfterFee,
                    strategyFundToken.totalShares,
                    Math.Rounding.Floor
                );
            }
            //allocate deposit
            if (pendingLpDepositAssets > 0) {
                for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                    strategyFundToken = strategyFundTokenInfo[strategyProviderIds[i]][USDC_HASH];

                    uint256 mainAssetsInFund = _convertToAssets(
                        strategyFundToken.mainShares,
                        strategyFundToken.fundAssetsAfterFee,
                        strategyFundToken.totalShares,
                        Math.Rounding.Floor
                    );
                    uint256 distributeDepositAssets =
                        pendingLpDepositAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Floor);

                    uint256 distributeDepositShares = _convertToShares(
                        distributeDepositAssets,
                        strategyFundToken.fundAssetsAfterFee,
                        strategyFundToken.totalShares,
                        Math.Rounding.Floor
                    );
                    strategyFundToken.pendingState.pendingTotalAssets += distributeDepositAssets;
                    strategyFundToken.pendingState.pendingTotalShares += distributeDepositShares;
                    strategyFundToken.pendingState.pendingMainShares += distributeDepositShares;

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
                    strategyFundToken = strategyFundTokenInfo[strategyProviderIds[i]][USDC_HASH];

                    uint256 mainAssetsInFund = _convertToAssets(
                        strategyFundToken.mainShares,
                        strategyFundToken.fundAssetsAfterFee,
                        strategyFundToken.totalShares,
                        Math.Rounding.Floor
                    );
                    uint256 distributeWithdrawAssets =
                        withdrawAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Ceil);
                    uint256 distributeWithdrawShares = _convertToShares(
                        distributeWithdrawAssets,
                        strategyFundToken.fundAssetsAfterFee,
                        strategyFundToken.totalShares,
                        Math.Rounding.Floor
                    );
                    strategyFundToken.pendingState.pendingTotalAssets -= distributeWithdrawAssets;
                    strategyFundToken.pendingState.pendingMainShares -= distributeWithdrawShares;
                    strategyFundToken.pendingState.pendingTotalShares -= distributeWithdrawShares;
                    //event
                    allocateFundRes[i].totalWithdrawAssets = distributeWithdrawAssets;
                    allocateFundRes[i].totalWithdrawShares = distributeWithdrawShares;
                }
            }
        }

        emit FundAllocated(periodId, vaultId, strategyProviderIds, allocateFundRes);
    }

    /// @notice Operator settle main and strategy fund info after check all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyProviderIds each strategy provider id
    /// @param signature signature of BE
    function settleMainAndStrategyFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifySettleMainAndStrategyFunds(periodId, vaultId, strategyProviderIds, signature, engine);
        //settle MAIN
        mainShares = pendingMainShares;
        StrategyFundState[] memory strategyFundStates = new StrategyFundState[](strategyProviderIds.length);

        //settle strategy fund
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[strategyProviderIds[i]][USDC_HASH];

            //hwm must be updated firstly
            strategyFundToken.hwm = _calculateHWM(strategyProviderIds[i]);

            strategyFundToken.totalShares = strategyFundToken.pendingState.pendingTotalShares;
            strategyFundToken.totalAssets = strategyFundToken.pendingState.pendingTotalAssets;
            strategyFundToken.mainShares = strategyFundToken.pendingState.pendingMainShares;
            strategyFundToken.strategyProviderShares = strategyFundToken.pendingState.pendingStrategyProviderShares;

            //emit event
            strategyFundStates[i] = StrategyFundState({
                strategyProviderId: strategyProviderIds[i],
                totalShares: strategyFundToken.totalShares,
                totalAssets: strategyFundToken.totalAssets,
                mainShares: strategyFundToken.mainShares,
                strategyProviderShares: strategyFundToken.strategyProviderShares,
                hwm: strategyFundToken.hwm
            });
        }

        emit MainAndStrategyFundsSettled(periodId, vaultId, mainShares, strategyFundStates);
    }

    /// @notice Operator settle all LP infos after check all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param accountIds each account id
    /// @param signature signature of BE
    function settleAccounts(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds, bytes calldata signature)
        external
        onlyOperator
    {
        _check(periodId);
        Signature.verifySettleAccount(periodId, vaultId, accountIds, signature, engine);

        AccountState[] memory accountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            AccountToken storage accountToken = accountTokenInfo[accountIds[i]][USDC_HASH];
            accountToken.shares = accountToken.pendingShares;

            //for event
            accountStates[i] = AccountState({accountId: accountIds[i], shares: accountToken.shares});
        }

        emit AccountSettled(periodId, vaultId, accountStates);
    }

    /// @notice Operator update period id after last period finish
    /// @param periodId new period id
    /// @param vaultId vault id
    /// @param signature signature signature of BE
    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes calldata signature) external onlyOperator {
        if (periodId != latestPeriodId + 1) {
            revert InvalidPeriodId();
        }
        Signature.verifyUpdatePeriodId(periodId, vaultId, signature, engine);

        pendingLpDepositAssets = 0;
        pendingLpWithdrawShares = 0;
        latestPeriodId++;

        emit PeriodIdUpdated(periodId, vaultId);
    }

    /// @notice Operator distribute withdraw assets to strategy
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param assetsDistributions distribute infos
    /// @param signature signature signature of BE
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
                srcChainId: block.chainid,
                dstChainId: assetsDistributions[i].chainId,
                payload: abi.encode(periodId, assetsDistribution)
            });
            //cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit AssetsDistrubuted(periodId, vaultId);
    }

    /// @notice Operator update unclaimed assets after funds transfer to protocol vault
    /// @param chainId chain id that unclaimed assets will be updated
    /// @param periodId period id
    /// @param vaultId  vault id
    /// @param updateUserClaims update uers claim infos
    /// @param signature signature signature of BE
    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        bytes32 vaultId,
        UpdateUserClaim[] memory updateUserClaims,
        bytes calldata signature
    ) external onlyOperator {
        _check(periodId);
        Signature.verifyUpdateUnclaimed(chainId, periodId, vaultId, updateUserClaims, signature, engine);

        //ignore handled claim info
        UpdateUserClaim[] memory userClaims = new UpdateUserClaim[](updateUserClaims.length);
        for (uint256 i = 0; i < updateUserClaims.length; i++) {
            if (!isClaimedHandled[updateUserClaims[i].requestId]) {
                userClaims[i] = updateUserClaims[i];
                isClaimedHandled[updateUserClaims[i].requestId] = true;
            }
        }
        //cross chain message
        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: PayloadType.UPDATE_USER_CLAIM,
            srcChainId: block.chainid,
            dstChainId: chainId,
            payload: abi.encode(periodId, userClaims)
        });
        //cross-chain
        IVaultCrossChainManager(crossChainManager).sendMessage(message);

        emit UnclaimedAssetsUpdated(periodId, vaultId, userClaims);
    }
    //--------------------------------------CONFIG--------------------------------------------

    function setFeeRate(bytes32[] calldata strategyProviderIds, uint256[] calldata feeRates) external onlyOwner {
        if (strategyProviderIds.length != feeRates.length) {
            revert InvalidInput();
        }
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            feeRateOfFund[strategyProviderIds[i]] = feeRates[i];
        }
    }

    function setCrossChainManager(address _crossChainManager) external onlyOwner {
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

    function setOperatorManager(address _operator) public onlyOwner {
        operator = _operator;

        emit OperatorManagerSet(_operator);
    }

    function setEngine(address _engine) public onlyOwner {
        engine = _engine;
    }

    function setDecimal(uint256 _priceDecimal, uint256 _shareDecimal, uint256 _assetsDecimal) external onlyOwner {
        priceDecimal = _priceDecimal;
        shareDecimal = _shareDecimal;
        assetsDecimal = _assetsDecimal;
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
            StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[strategyProviderIds[i]][USDC_HASH];

            uint256 hwm = _calculateHWM(strategyProviderIds[i]);
            strategyFundStates[i] = StrategyFundState({
                strategyProviderId: strategyProviderIds[i],
                totalShares: strategyFundToken.totalShares,
                totalAssets: strategyFundToken.totalAssets,
                mainShares: strategyFundToken.mainShares,
                strategyProviderShares: strategyFundToken.strategyProviderShares,
                hwm: hwm
            });
        }
        return (pendingMainShares, strategyFundStates);
    }

    function checkLP(uint256 periodId, bytes32[] calldata accountIds) external view returns (AccountState[] memory) {
        _check(periodId);
        AccountState[] memory accountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            AccountToken storage accountToken = accountTokenInfo[accountIds[i]][USDC_HASH];
            accountStates[i] = AccountState({accountId: accountIds[i], shares: accountToken.shares});
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

    function getStrategyFund(bytes32 spId) public view returns (StrategyFundToken memory) {
        return strategyFundTokenInfo[spId][USDC_HASH];
    }
    /*=========================================================================================
    *                                       INTERNAL
    *=========================================================================================*/

    function _check(uint256 periodId) internal view {
        if (periodId != latestPeriodId) {
            revert InvalidPeriodId();
        }
    }

    function _checkWithdraw(uint256 withdrawAmount, uint256 frozenAmount, uint256 totalAmount) internal {
        if (withdrawAmount + frozenAmount > totalAmount) {
            emit NotEnoughWithdrawShare();
            return;
        }
    }

    function _handleLpDeposit(bytes32 accountId, uint256 amount) internal returns (uint256) {
        AccountToken storage accountToken = accountTokenInfo[accountId][USDC_HASH];

        if (amount > accountToken.unAllocatedAssets) {
            revert NotEnoughLPDeposit(amount);
        }

        uint256 depositShares = _convertToShares(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);
        //effect
        accountToken.pendingShares += depositShares;
        accountToken.unAllocatedAssets -= amount;

        pendingMainShares += depositShares;
        pendingLpDepositAssets += amount;

        return depositShares;
    }

    function _handleLpWithdraw(bytes32 accountId, uint256 amount) internal returns (uint256) {
        AccountToken storage accountToken = accountTokenInfo[accountId][USDC_HASH];

        if (amount > accountToken.frozenShares) {
            revert NotEnoughFrozenShare(amount);
        }

        //effect
        uint256 withdrawAssets = _convertToAssets(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);

        accountToken.pendingShares -= amount;
        accountToken.frozenShares -= amount;
        pendingMainShares -= amount;
        pendingLpWithdrawShares += amount;

        return withdrawAssets;
    }

    function _handleSPDeposit(bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[strategyProviderId][USDC_HASH];
        PendingState storage pendingState = strategyFundToken.pendingState;
        if (amount > strategyFundToken.unAllocatedAssets) {
            revert NotEnoughSPDeposit();
        }
        uint256 depositShares = _convertToShares(
            amount, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
        );

        pendingState.pendingTotalShares += depositShares;
        pendingState.pendingStrategyProviderShares += depositShares;
        pendingState.pendingTotalAssets += amount;
        strategyFundToken.unAllocatedAssets -= amount;
        return depositShares;
    }

    function _handleSpWithdraw(bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[strategyProviderId][USDC_HASH];
        PendingState storage pendingState = strategyFundToken.pendingState;

        if (amount > strategyFundToken.frozenShares) {
            revert NotEnoughFrozenShare(amount);
        }
        uint256 spWithdrawAmount = _convertToAssets(
            amount, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
        );

        //effect
        pendingState.pendingTotalShares -= amount;
        pendingState.pendingStrategyProviderShares -= amount;
        pendingState.pendingTotalAssets -= spWithdrawAmount;
        strategyFundToken.frozenShares -= amount;
        return spWithdrawAmount;
    }

    function _calculateHWM(bytes32 strategyProviderId) internal view returns (uint256) {
        StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[strategyProviderId][USDC_HASH];

        uint256 hwm = strategyFundToken.hwm;
        uint256 totalShares = strategyFundToken.totalShares;
        if (strategyFundToken.performanceFee > 0) {
            hwm = strategyFundToken.fundAssetsAfterFee * 10 ** priceDecimal / totalShares;
        } else {
            uint256 pendingTotalShares = strategyFundToken.pendingState.pendingTotalShares;
            //New issued shares greater than 0
            if (pendingTotalShares > totalShares) {
                uint256 newTotalIssuedShares = pendingTotalShares - totalShares;
                //calculate new hwm
                hwm = (
                    (
                        strategyFundToken.hwm * totalShares / 10 ** priceDecimal
                            + newTotalIssuedShares * strategyFundToken.fundAssetsAfterFee / totalShares
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
