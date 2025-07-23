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
import {OperationData} from "./lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVaultLedger} from "./interfaces/IProtocolVaultLedger.sol";
import {ILedgerExtensions} from "./interfaces/ILedgerExtensions.sol";
import {LedgerBase} from "./LedgerBase.sol";
import {LedgerUtils} from "./lib/utils/LedgerUtils.sol";

/// @title protocol vault ledger
/// @notice This contract is used to record all information of protocol vault

contract ProtocolVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable, LedgerBase, IProtocolVaultLedger {
    using Math for uint256;

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

    /*=========================================================================================
    *                                   EXTERNAL
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
        _delegateToExtensions(
            abi.encodeWithSelector(ILedgerExtensions.handleOpFromVault.selector, payloadType, chainId, operationData)
        );
    }

    /// @notice Handle DEX requests (delegated to extensions contract)
    /// @param dexRequests Array of DEX requests
    /// @param signature Signature for verification

    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external {
        _delegateToExtensions(
            abi.encodeWithSelector(ILedgerExtensions.handleDexRequests.selector, dexRequests, signature)
        );
    }

    /// @notice Distribute assets to strategy (delegated to extensions contract)
    /// @param periodId Period ID
    /// @param vaultId Vault ID
    /// @param assetsDistributions Asset distribution info
    /// @param signature Signature for verification
    function distributeAssets(
        uint256 periodId,
        bytes32 vaultId,
        AssetsDistribution[] memory assetsDistributions,
        bytes calldata signature
    ) external {
        _delegateToExtensions(
            abi.encodeWithSelector(
                ILedgerExtensions.distributeAssets.selector, periodId, vaultId, assetsDistributions, signature
            )
        );
    }

    /// @notice Update unclaimed assets (delegated to extensions contract)
    /// @param chainId Chain ID
    /// @param periodId Period ID
    /// @param vaultId Vault ID
    /// @param requestIds Request ID array
    /// @param signature Signature for verification
    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] memory requestIds,
        bytes calldata signature
    ) external {
        bytes memory data = abi.encodeWithSelector(
            ILedgerExtensions.updateUnclaimed.selector, chainId, periodId, vaultId, requestIds, signature
        );
        _delegateToExtensions(data);
    }

    /// @notice Remove invalid frozen shares (delegated to extensions contract)
    /// @param vaultId The vault ID
    /// @param params The parameters containing the invalid frozen shares to remove
    /// @param signature The signature to verify
    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external
    {
        bytes memory data =
            abi.encodeWithSelector(ILedgerExtensions.removeInvalidFrozenShares.selector, vaultId, params, signature);
        _delegateToExtensions(data);
    }

    //--------------------------------------CONFIG--------------------------------------------

    /// @notice Set fee rate for strategy providers
    /// @param strategyProviderIds Array of strategy provider IDs
    /// @param feeRates Array of fee rates
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
        //emit event
        emit FeeRateSet(strategyProviderIds, feeRates);
    }

    /// @notice Set cross chain manager address
    /// @param _crossChainManager Address of cross chain manager
    function setCrossChainManager(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;

        //emit event
        emit CrossChainManagerSet(crossChainManager);
    }

    /// @notice Set allowed strategy provider
    /// @param vaultId Vault ID
    /// @param vault Vault address
    /// @param strategyProvider Strategy provider address
    /// @param brokerHash Broker hash
    /// @param strategyProviderId Strategy provider ID
    /// @param knob Boolean flag
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

    /// @notice Set operator manager address
    /// @param _operator Operator address
    function setOperatorManager(address _operator) public onlyOwner {
        operator = _operator;

        //emit event
        emit OperatorManagerSet(operator);
    }

    /// @notice Set engine address
    /// @param _engine Engine address
    function setEngine(address _engine) public onlyOwner {
        engine = _engine;

        //emit event
        emit EngineSet(engine);
    }

    /// @notice Set token decimal
    /// @param tokenHash Token hash
    /// @param decimal Token decimal
    function setDecimal(bytes32 tokenHash, uint256 decimal) external onlyOwner {
        tokenDecimal[tokenHash] = decimal;

        //emit event
        emit DecimalSet(tokenHash, decimal);
    }

    /// @notice Set vault broker
    /// @param _vaultId Vault ID
    /// @param _brokerId Broker ID
    function setVaultBroker(bytes32 _vaultId, bytes32 _brokerId) external onlyOwner {
        vaultBroker[_vaultId] = _brokerId;

        //emit event
        emit VaultBrokerSet(_vaultId, _brokerId);
    }

    /// @notice Set ledger extensions contract address
    /// @param _ledgerExtensions Address of the ledger extensions contract
    function setLedgerExtensions(address _ledgerExtensions) external onlyOwner {
        ledgerExtensions = _ledgerExtensions;

        //emit event
        emit LedgerExtensionsSet(ledgerExtensions);
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

    /// @notice Delegate call to extensions contract
    /// @param data Encoded function call data
    function _delegateToExtensions(bytes memory data) internal {
        if (ledgerExtensions == address(0)) {
            revert LedgerExtensionsNotSet();
        }
        (bool success, bytes memory result) = ledgerExtensions.delegatecall(data);
        if (!success) {
            // Forward the revert reason
            if (result.length > 0) {
                assembly {
                    revert(add(32, result), mload(result))
                }
            } else {
                revert DelegatecallFailed();
            }
        }
    }

    function _check(uint256 periodId) internal view {
        if (periodId != latestPeriodId) {
            revert InvalidPeriodId();
        }
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

        LedgerUtils.requireEnoughFrozenShares(amount, accountToken.frozenShares);

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

        LedgerUtils.requireEnoughFrozenShares(amount, strategyFundToken.frozenShares);
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
}
