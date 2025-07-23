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
    AllocateFundRes,
    StrategyFundState,
    ClaimInfo,
    ChainType,
    DexRequest,
    DexRequestData
} from "./lib/types/LedgerStruct.sol";
import {Signature} from "./lib/utils/Signature.sol";
import {VaultUtils} from "./lib/utils/VaultUtils.sol";
import {OperationData} from "./lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVaultLedger} from "./interfaces/IProtocolVaultLedger.sol";

/// @title protocol vault ledger
/// @notice This contract is used to record all information of protocol vault

contract ProtocolVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable, IProtocolVaultLedger {
    using Math for uint256;

    uint256 public constant FEE_BASE = 100;
    bytes32 constant USDC_HASH = 0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa;
    uint256 constant USDC_DECIMAL = 6;

    uint256 public pendingMainShares;
    uint256 public pendingLpDepositAssets;
    uint256 public pendingLpWithdrawAssets;

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

    /// @dev Token Hash to token decimal
    mapping(bytes32 => uint256) tokenDecimal;
    /// @dev fee rate of each strategy fund by vault id
    mapping(bytes32 => uint256) public feeRateOfFund;
    /// @dev strategy fund token information by strategy provider id and token hash
    mapping(bytes32 => mapping(bytes32 => StrategyFundToken)) public strategyFundTokenInfo;
    /// @dev account token information by account id and token hash
    mapping(bytes32 => mapping(bytes32 => AccountToken)) public accountTokenInfo;
    /// @dev requestId to User Claim information
    mapping(bytes32 => ClaimInfo) public userClaimInfo;
    /// @dev Determines whether the operation corresponding to the requestId is executed
    mapping(bytes32 => bool) public isOpHandled;
    /// @dev Determines whether the user claim is handled
    mapping(bytes32 => bool) public isUserClaimHandled;
    /// @dev Determines whether the assets has been uploaded in a period. Only can be called once in a period.
    mapping(uint256 => bool) public isUpdateStrategyFundAssets;
    /// @dev Determines whether the assets has been allocated in a period.
    mapping(uint256 => bool) public isAllocatedToFunds;
    /// @dev Determines whether the assets has been distributed in a period. Only can be called once in a period.
    mapping(uint256 => bool) public isAssetDistributed;
    /// @dev Determines whether the dex request has been handled
    mapping(uint256 => bool) public isDexRequestHandled;
    /// @dev vault id to sv broker hash
    mapping(bytes32 => bytes32) public vaultBroker;

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
        bytes32 id = operationData.accountId == bytes32(0) ? operationData.strategyProviderId : operationData.accountId;

        if (_handleRequest(payloadType, id, operationData.tokenHash, operationData.amount)) {
            emit OperationHandled(payloadType, chainId, operationData);
        } else {
            emit NotEnoughWithdrawShare(payloadType, chainId, operationData.chainNonce);
        }
    }

    //--------------------------------------FROM Operator--------------------------------------------
    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external onlyOperator {
        //verify engine signature
        Signature.verifyDexRequest(dexRequests, signature, engine);

        for (uint256 i = 0; i < dexRequests.length; i++) {
            DexRequest calldata request = dexRequests[i];
            uint256 requestId = request.dexRequestData.dexRequestId;
            // verify if dex request is handled
            if (isDexRequestHandled[requestId]) {
                revert AlreadyCalled();
            }

            ChainType chainType = request.chainType;
            if (chainType == ChainType.EVM) {
                _verifyEVMRequest(request);
            } else {
                revert InvalidChainType();
            }

            //update record
            bytes32 tokenHash = keccak256(abi.encodePacked(request.dexRequestData.token));
            isDexRequestHandled[requestId] = true;

            if (
                _handleRequest(request.dexRequestData.payloadType, request.id, tokenHash, request.dexRequestData.amount)
            ) {
                emit DexRequestHandled(request);
            } else {
                emit DexWithdrawNotEnough(requestId);
            }
        }
    }

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
        //only can be called once in a period
        if (isUpdateStrategyFundAssets[periodId]) {
            revert AlreadyCalled();
        }
        Signature.verifyUpdateFundAssets(periodId, vaultId, strategyFundAssets, signature, engine);

        uint256 assetsAfterFee;
        //for event
        UpdateStrategyFundAssetsRes[] memory updateStrategyFundAssetsRes =
            new UpdateStrategyFundAssetsRes[](strategyFundAssets.length);

        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            bytes32 spId = strategyFundAssets[i].strategyProviderId;
            //gas optimization
            StrategyFundToken storage strategyFundToken = _getStrategyFundToken(spId);
            PendingState storage pendingState = strategyFundToken.pendingState;

            //reset performance fee
            strategyFundToken.performanceFee = 0;

            uint256 fundAssets = strategyFundAssets[i].totalAssets;
            uint256 fundShares = strategyFundToken.totalShares;

            //Performance Fee
            uint256 performanceFee;
            uint256 feeShares;
            if (fundShares > 0) {
                //avoid stack too deep
                {
                    uint256 assetPerShare = fundAssets * 10 ** USDC_DECIMAL / fundShares;

                    if (assetPerShare > strategyFundToken.hwm) {
                        performanceFee = (assetPerShare - strategyFundToken.hwm) * fundShares * feeRateOfFund[spId]
                            / FEE_BASE / 10 ** USDC_DECIMAL;
                        feeShares = _convertToShares(
                            performanceFee, fundAssets - performanceFee, fundShares, Math.Rounding.Floor
                        );

                        strategyFundToken.performanceFee = performanceFee;
                    }
                }
                assetsAfterFee +=
                    strategyFundToken.mainShares * (fundAssets - performanceFee) / strategyFundToken.totalShares;
            }

            //Update pending state
            strategyFundToken.pendingState.pendingTotalAssets = fundAssets;
            strategyFundToken.fundAssetsAfterFee = fundAssets - performanceFee;
            pendingState.pendingStrategyProviderShares += feeShares;
            pendingState.pendingTotalShares = fundShares + feeShares;

            //Add to event
            updateStrategyFundAssetsRes[i] = UpdateStrategyFundAssetsRes({
                strategyProviderId: strategyFundAssets[i].strategyProviderId,
                fundAssetsAfterFee: fundAssets - performanceFee,
                strategyProviderShares: pendingState.pendingStrategyProviderShares,
                totalShares: fundShares + feeShares
            });
        }

        mainAssetsAfterFee = assetsAfterFee;
        isUpdateStrategyFundAssets[periodId] = true;

        emit StrategyFundAssetsUpdate(periodId, vaultId, mainAssetsAfterFee, updateStrategyFundAssetsRes);
    }

    /// @notice Remove invalid frozen shares for LP or SP that were incorrectly added
    /// @param vaultId The vault ID
    /// @param params The parameters containing the invalid frozen shares to remove
    /// @param signature The signature to verify
    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external
        onlyOperator
    {
        Signature.verifyRemoveInvalidFrozenShares(vaultId, params, signature, engine);

        OperationRes[] memory operationRes = _createOperationResArray(params.length);

        for (uint256 i = 0; i < params.length; i++) {
            bytes32 requestId = params[i].operation.requestId;

            if (!isOpHandled[requestId]) {
                Operation memory operation = params[i].operation;
                bytes32 id = operation.id;
                uint256 operationAmount = operation.amount;
                OperationType operationType = params[i].operationType;

                if (operationType == OperationType.LP_WITHDRAW) {
                    // Handle LP frozen shares removal
                    AccountToken storage accountToken = _getAccountToken(id);
                    _requireEnoughFrozenShares(operationAmount, accountToken.frozenShares);
                    accountToken.frozenShares -= operationAmount;
                } else if (operationType == OperationType.SP_WITHDRAW) {
                    // Handle SP frozen shares removal
                    StrategyFundToken storage strategyFundToken = _getStrategyFundToken(id);
                    _requireEnoughFrozenShares(operationAmount, strategyFundToken.frozenShares);
                    strategyFundToken.frozenShares -= operationAmount;
                } else {
                    revert InvalidType();
                }

                //Event
                operationRes[i] =
                    OperationRes({id: id, requestId: requestId, amount: operationAmount, operationType: operationType});

                isOpHandled[requestId] = true;
            }
        }

        emit InvalidFrozenSharesRemoved(vaultId, operationRes);
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

        OperationRes[] memory operationRes = _createOperationResArray(updateUserLedgerParams.length);

        //handle lp operation
        for (uint256 i = 0; i < updateUserLedgerParams.length; i++) {
            bytes32 requestId = updateUserLedgerParams[i].operation.requestId;
            uint256 amount;

            if (!isOpHandled[requestId]) {
                Operation memory operation = updateUserLedgerParams[i].operation;
                bytes32 id = operation.id;
                uint256 operationAmount = operation.amount;
                OperationType operationType = updateUserLedgerParams[i].operationType;

                if (operationType == OperationType.LP_DEPOSIT) {
                    //handle LP deposit
                    amount = _handleLpDeposit(id, operationAmount);
                } else if (operationType == OperationType.LP_WITHDRAW) {
                    //handle LP withdraw
                    amount = _handleLpWithdraw(requestId, id, operationAmount);
                } else if (operationType == OperationType.SP_DEPOSIT) {
                    //handle SP deposit
                    amount = _handleSPDeposit(id, operationAmount);
                } else if (operationType == OperationType.SP_WITHDRAW) {
                    //handle SP withdraw
                    amount = _handleSpWithdraw(requestId, id, operationAmount);
                } else {
                    revert InvalidType();
                }

                operationRes[i] =
                    OperationRes({id: operation.id, requestId: requestId, amount: amount, operationType: operationType});
                isOpHandled[requestId] = true;
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
    function allocateToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external onlyOperator {
        _check(periodId);
        //only can be called once in a period
        if (isAllocatedToFunds[periodId]) {
            revert AlreadyCalled();
        }
        Signature.verifyAllocateToFunds(periodId, vaultId, strategyProviderIds, signature, engine);

        StrategyFundToken storage strategyFundToken;
        uint256 totalMainAssetsInFund;

        //for event
        AllocateFundRes[] memory allocateFundRes = new AllocateFundRes[](strategyProviderIds.length);

        //gas saving
        uint256 depositAssets = pendingLpDepositAssets;
        uint256 withdrawAssets = pendingLpWithdrawAssets;

        if (strategyProviderIds.length == 1) {
            strategyFundToken = _getStrategyFundToken(strategyProviderIds[0]);

            //deposit
            uint256 distributeDepositShares = _convertToShares(
                depositAssets, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
            );
            strategyFundToken.pendingState.pendingTotalAssets += depositAssets;
            strategyFundToken.pendingState.pendingTotalShares += distributeDepositShares;
            strategyFundToken.pendingState.pendingMainShares += distributeDepositShares;

            //withdraw
            uint256 pendingLpWithdrawShares = _convertToShares(
                withdrawAssets, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
            );
            strategyFundToken.pendingState.pendingTotalAssets -= withdrawAssets;
            strategyFundToken.pendingState.pendingMainShares -= pendingLpWithdrawShares;
            strategyFundToken.pendingState.pendingTotalShares -= pendingLpWithdrawShares;

            //event
            allocateFundRes[0] = AllocateFundRes({
                strategyProviderId: strategyProviderIds[0],
                totalDepositAssets: depositAssets,
                totalDepositShares: distributeDepositShares,
                totalWithdrawAssets: withdrawAssets,
                totalWithdrawShares: pendingLpWithdrawShares
            });
        } else if (strategyProviderIds.length > 1) {
            for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                strategyFundToken = _getStrategyFundToken(strategyProviderIds[i]);
                allocateFundRes[i].strategyProviderId = strategyProviderIds[i];
                totalMainAssetsInFund += _convertToAssets(
                    strategyFundToken.mainShares,
                    strategyFundToken.fundAssetsAfterFee,
                    strategyFundToken.totalShares,
                    Math.Rounding.Floor
                );
            }
            //allocate deposit
            if (depositAssets > 0) {
                for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                    strategyFundToken = _getStrategyFundToken(strategyProviderIds[i]);

                    uint256 mainAssetsInFund = _convertToAssets(
                        strategyFundToken.mainShares,
                        strategyFundToken.fundAssetsAfterFee,
                        strategyFundToken.totalShares,
                        Math.Rounding.Floor
                    );
                    uint256 distributeDepositAssets =
                        depositAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Floor);

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
            if (withdrawAssets > 0) {
                for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                    strategyFundToken = _getStrategyFundToken(strategyProviderIds[i]);

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

        isAllocatedToFunds[periodId] = true;
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
            StrategyFundToken storage strategyFundToken = _getStrategyFundToken(strategyProviderIds[i]);

            //hwm must be updated firstly
            strategyFundToken.hwm = _calculateHWM(strategyProviderIds[i]);

            _settlePendingState(strategyFundToken);

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
            AccountToken storage accountToken = _getAccountToken(accountIds[i]);
            accountToken.shares = accountToken.pendingShares;

            //for event
            accountStates[i] = AccountState({accountId: accountIds[i], shares: accountToken.shares});
        }

        emit AccountSettled(periodId, vaultId, accountStates);
    }

    /// @notice Operator update period id after last period finish
    /// @param periodId latest periodId
    /// @param vaultId vault id
    /// @param signature signature signature of BE
    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes calldata signature) external onlyOperator {
        if (periodId != latestPeriodId) {
            revert InvalidPeriodId();
        }
        Signature.verifyUpdatePeriodId(periodId, vaultId, signature, engine);

        pendingLpDepositAssets = 0;
        pendingLpWithdrawAssets = 0;

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
        //only can be called once in a period
        if (isAssetDistributed[periodId]) {
            revert AlreadyCalled();
        }
        Signature.verifyAssetsDistribution(periodId, vaultId, assetsDistributions, signature, engine);

        //change state
        isAssetDistributed[periodId] = true;

        for (uint256 i = 0; i < assetsDistributions.length; i++) {
            //contruct StrategyExecution
            AssetsDistribution memory assetsDistribution =
                AssetsDistribution({chainId: assetsDistributions[i].chainId, assets: assetsDistributions[i].assets});

            //cross chain message
            StrategyVaultCCMessage memory message = _createCCMessage(
                PayloadType.ASSETS_DISTRIBUTION,
                assetsDistributions[i].chainId,
                abi.encode(periodId, assetsDistribution)
            );
            //cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit AssetsDistributed(periodId, vaultId);
    }

    /// @notice Operator update unclaimed assets after funds transfer to protocol vault
    /// @param chainId chain id that unclaimed assets will be updated
    /// @param periodId period id
    /// @param vaultId  vault id
    /// @param requestIds request Id array
    /// @param signature signature signature of BE
    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] memory requestIds,
        bytes calldata signature
    ) external onlyOperator {
        Signature.verifyUpdateUnclaimed(chainId, periodId, vaultId, requestIds, signature, engine);

        //length that unhandled requestId
        uint256 len;
        for (uint256 i = 0; i < requestIds.length; i++) {
            if (_isValidRequestId(requestIds[i])) {
                len++;
            }
        }

        ClaimInfo[] memory userClaimInfos = new ClaimInfo[](len);
        //cross chain message
        if (len != 0) {
            //new index to avoid out of range
            uint256 index;
            //handle requestid claim
            for (uint256 i = 0; i < requestIds.length; i++) {
                //ignore if handled
                if (_isValidRequestId(requestIds[i])) {
                    userClaimInfos[index] = userClaimInfo[requestIds[i]];

                    isUserClaimHandled[requestIds[i]] = true;
                    index++;
                    delete userClaimInfo[requestIds[i]];
                }
            }
            uint256 ccFee;

            //cross chain message
            StrategyVaultCCMessage memory message =
                _createCCMessage(PayloadType.UPDATE_USER_CLAIM, chainId, abi.encode(periodId, ccFee, userClaimInfos));
            (ccFee,) = IVaultCrossChainManager(crossChainManager).quoteClaim(chainId, message);

            //set gas
            message = _createCCMessage(
                PayloadType.UPDATE_USER_CLAIM, chainId, abi.encode(periodId, ccFee / len, userClaimInfos)
            );

            //cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit UnclaimedAssetsUpdated(periodId, vaultId, userClaimInfos);
    }

    //--------------------------------------CONFIG--------------------------------------------
    function setFeeRate(bytes32[] calldata strategyProviderIds, uint256[] calldata feeRates) external onlyOwner {
        if (strategyProviderIds.length != feeRates.length) {
            revert InvalidInput();
        }
        if (latestPeriodId != 0 && !isUpdateStrategyFundAssets[latestPeriodId - 1]) {
            revert NotAllowedTime();
        }

        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            feeRateOfFund[strategyProviderIds[i]] = feeRates[i];
        }
    }

    function setCrossChainManager(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;
    }

    function setAllowedStrategyProvider(
        bytes32 vaultId,
        address vault,
        address strategyProvider,
        bytes32 brokerHash,
        bytes32 strategyProviderId,
        bool knob
    ) external onlyOwner {
        emit AllowedStrategyProviderSet(vaultId, vault, strategyProvider, brokerHash, strategyProviderId, knob);
    }

    function setOperatorManager(address _operator) public onlyOwner {
        operator = _operator;
    }

    function setEngine(address _engine) public onlyOwner {
        engine = _engine;
    }

    function setDecimal(bytes32 tokenHash, uint256 decimal) external onlyOwner {
        tokenDecimal[tokenHash] = decimal;
    }

    function setVaultBroker(bytes32 _vaultId, bytes32 _brokerId) external onlyOwner {
        vaultBroker[_vaultId] = _brokerId;
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
        StrategyFundState[] memory pendingStrategyFundStates = new StrategyFundState[](strategyProviderIds.length);

        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            PendingState storage pendingState = _getStrategyFundToken(strategyProviderIds[i]).pendingState;

            uint256 hwm = _calculateHWM(strategyProviderIds[i]);
            pendingStrategyFundStates[i] = StrategyFundState({
                strategyProviderId: strategyProviderIds[i],
                totalShares: pendingState.pendingTotalShares,
                totalAssets: pendingState.pendingTotalAssets,
                mainShares: pendingState.pendingMainShares,
                strategyProviderShares: pendingState.pendingStrategyProviderShares,
                hwm: hwm
            });
        }

        return (pendingMainShares, pendingStrategyFundStates);
    }

    function checkLP(uint256 periodId, bytes32, bytes32[] calldata accountIds)
        external
        view
        returns (AccountState[] memory)
    {
        _check(periodId);
        AccountState[] memory pendingAccountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            AccountToken storage accountToken = _getAccountToken(accountIds[i]);
            pendingAccountStates[i] = AccountState({accountId: accountIds[i], shares: accountToken.pendingShares});
        }
        return pendingAccountStates;
    }

    function convertToShares(uint256 amount, uint256 _totalAssets, uint256 _totalShares)
        external
        view
        returns (uint256)
    {
        return _convertToShares(amount, _totalAssets, _totalShares, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _totalShares)
        external
        view
        returns (uint256)
    {
        return _convertToAssets(shares, _totalAssets, _totalShares, Math.Rounding.Floor);
    }

    function getStrategyFund(bytes32 spId) public view returns (StrategyFundToken memory) {
        return _getStrategyFundToken(spId);
    }
    /*=========================================================================================
    *                                       INTERNAL
    *=========================================================================================*/

    function _check(uint256 periodId) internal view {
        if (periodId != latestPeriodId) {
            revert InvalidPeriodId();
        }
    }

    /// @notice Create a StrategyVaultCCMessage with standard fields
    /// @param payloadType The type of cross-chain message
    /// @param dstChainId The destination chain ID
    /// @param payload The encoded payload data
    /// @return message The constructed StrategyVaultCCMessage
    function _createCCMessage(PayloadType payloadType, uint256 dstChainId, bytes memory payload)
        internal
        view
        returns (StrategyVaultCCMessage memory message)
    {
        return StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: block.chainid,
            dstChainId: dstChainId,
            payload: payload
        });
    }

    function _checkWithdraw(uint256 withdrawAmount, uint256 frozenAmount, uint256 totalAmount)
        internal
        pure
        returns (bool)
    {
        return withdrawAmount + frozenAmount <= totalAmount;
    }

    /// @notice Copy pending state to actual state for strategy fund
    /// @param strategyFundToken The strategy fund token to update
    function _settlePendingState(StrategyFundToken storage strategyFundToken) internal {
        PendingState storage pendingState = strategyFundToken.pendingState;
        strategyFundToken.totalShares = pendingState.pendingTotalShares;
        strategyFundToken.totalAssets = pendingState.pendingTotalAssets;
        strategyFundToken.mainShares = pendingState.pendingMainShares;
        strategyFundToken.strategyProviderShares = pendingState.pendingStrategyProviderShares;
    }

    /// @notice Create an array for loop results to reduce repeated array initialization
    /// @param length The length of the array to create
    /// @return result The initialized array
    function _createOperationResArray(uint256 length) internal pure returns (OperationRes[] memory result) {
        return new OperationRes[](length);
    }

    /// @notice Check if there are enough frozen shares for withdrawal
    /// @param amount Amount to withdraw
    /// @param frozenShares Available frozen shares
    /// @dev Reverts if not enough frozen shares
    function _requireEnoughFrozenShares(uint256 amount, uint256 frozenShares) internal pure {
        if (amount > frozenShares) {
            revert NotEnoughFrozenShare(amount);
        }
    }

    function _handleLpDeposit(bytes32 accountId, uint256 amount) internal returns (uint256) {
        AccountToken storage accountToken = _getAccountToken(accountId);

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

    function _handleLpWithdraw(bytes32 requestId, bytes32 accountId, uint256 amount) internal returns (uint256) {
        AccountToken storage accountToken = _getAccountToken(accountId);

        _requireEnoughFrozenShares(amount, accountToken.frozenShares);

        //effect
        uint256 withdrawAssets = _convertToAssets(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);

        accountToken.pendingShares -= amount;
        accountToken.frozenShares -= amount;
        pendingMainShares -= amount;
        pendingLpWithdrawAssets += withdrawAssets;

        userClaimInfo[requestId].requestId = requestId;
        userClaimInfo[requestId].accountId = accountId;
        userClaimInfo[requestId].assets = withdrawAssets;

        return withdrawAssets;
    }

    function _handleSPDeposit(bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(strategyProviderId);
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

    function _handleSpWithdraw(bytes32 requestId, bytes32 strategyProviderId, uint256 amount)
        internal
        returns (uint256)
    {
        //gas optimization
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(strategyProviderId);
        PendingState storage pendingState = strategyFundToken.pendingState;

        _requireEnoughFrozenShares(amount, strategyFundToken.frozenShares);
        uint256 spWithdrawAssets = _convertToAssets(
            amount, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
        );

        //effect
        pendingState.pendingTotalShares -= amount;
        pendingState.pendingStrategyProviderShares -= amount;
        pendingState.pendingTotalAssets -= spWithdrawAssets;
        strategyFundToken.frozenShares -= amount;

        userClaimInfo[requestId].requestId = requestId;
        userClaimInfo[requestId].strategyProviderId = strategyProviderId;
        userClaimInfo[requestId].assets = spWithdrawAssets;

        return spWithdrawAssets;
    }

    function _calculateHWM(bytes32 strategyProviderId) internal view returns (uint256) {
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(strategyProviderId);

        uint256 hwm = strategyFundToken.hwm;
        uint256 totalShares = strategyFundToken.totalShares;
        uint256 decimal = USDC_DECIMAL;
        if (totalShares == 0) {
            return 10 ** decimal;
        }

        uint256 sharePriceAfterFee = strategyFundToken.fundAssetsAfterFee * 10 ** decimal / totalShares;
        uint256 pendingTotalShares = strategyFundToken.pendingState.pendingTotalShares;
        uint256 newIssueShares = (pendingTotalShares > totalShares) ? pendingTotalShares - totalShares : 0;

        uint256 numerator = (totalShares * Math.max(hwm, sharePriceAfterFee)) + (newIssueShares * sharePriceAfterFee);
        uint256 denominator = totalShares + newIssueShares;

        return numerator / denominator;
    }

    function _isValidRequestId(bytes32 requestId) internal view returns (bool) {
        return !isUserClaimHandled[requestId] && userClaimInfo[requestId].assets > 0;
    }

    /**
     * @dev Internal conversion function (from assets amount to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 amount, uint256 _totalAssets, uint256 _totalShares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 decimal = USDC_DECIMAL;
        return (_totalAssets == 0)
            ? amount.mulDiv(10 ** decimal, 10 ** decimal, rounding)
            : amount.mulDiv(_totalShares, _totalAssets, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _totalShares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 decimal = USDC_DECIMAL;
        return (_totalShares == 0)
            ? shares.mulDiv(10 ** decimal, 10 ** decimal, rounding)
            : shares.mulDiv(_totalAssets, _totalShares, rounding);
    }

    function _verifyEVMRequest(DexRequest calldata request) internal view {
        DexRequestData calldata data = request.dexRequestData;

        address receiver = address(uint160(uint256(data.receiver)));
        address vault = IVaultCrossChainManager(crossChainManager).vault();

        //verify id
        VaultUtils.validateId(vault, receiver, vaultBroker[data.vaultId], request.id);

        // verify signature
        Signature.verifyEVMSig(data, request.v, request.r, request.s, request.chainId, receiver);
    }

    function _handleRequest(PayloadType payloadType, bytes32 id, bytes32 tokenHash, uint256 amount)
        internal
        returns (bool)
    {
        AccountToken storage accountToken = accountTokenInfo[id][tokenHash];
        StrategyFundToken storage strategyFundToken = strategyFundTokenInfo[id][tokenHash];

        if (payloadType == PayloadType.LP_DEPOSIT) {
            accountToken.unAllocatedAssets += amount;
        } else if (payloadType == PayloadType.LP_WITHDRAW) {
            if (_checkWithdraw(amount, accountToken.frozenShares, accountToken.pendingShares)) {
                accountToken.frozenShares += amount;
            } else {
                return false;
            }
        } else if (payloadType == PayloadType.SP_DEPOSIT) {
            strategyFundToken.unAllocatedAssets += amount;
        } else if (payloadType == PayloadType.SP_WITHDRAW) {
            if (
                _checkWithdraw(
                    amount, strategyFundToken.frozenShares, strategyFundToken.pendingState.pendingStrategyProviderShares
                )
            ) {
                strategyFundToken.frozenShares += amount;
            } else {
                return false;
            }
        } else {
            revert InvalidType();
        }
        return true;
    }

    /*=========================================================================================
    *                                   STORAGE ACCESS HELPERS
    *=========================================================================================*/

    /// @notice Get strategy fund token storage reference (reduces storage access repetition)
    /// @param spId strategy provider ID
    /// @return strategyFundToken storage reference to strategy fund token
    function _getStrategyFundToken(bytes32 spId) internal view returns (StrategyFundToken storage strategyFundToken) {
        return strategyFundTokenInfo[spId][USDC_HASH];
    }

    /// @notice Get account token storage reference (reduces storage access repetition)
    /// @param accountId account ID
    /// @return accountToken storage reference to account token
    function _getAccountToken(bytes32 accountId) internal view returns (AccountToken storage accountToken) {
        return accountTokenInfo[accountId][USDC_HASH];
    }
}
