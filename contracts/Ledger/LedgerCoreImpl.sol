// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

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
    ClaimInfo
} from "../lib/types/LedgerStruct.sol";
import {Signature} from "../lib/utils/Signature.sol";
import {PayloadType, StrategyVaultCCMessage} from "../lib/types/CrossChainStruct.sol";
import {IVaultCrossChainManager} from "../interfaces/IVaultCrossChainManager.sol";
import {IProtocolVaultLedger} from "../interfaces/IProtocolVaultLedger.sol";
import {ILedgerCoreImpl} from "../interfaces/ILedgerCoreImpl.sol";
import {LedgerBase} from "./LedgerBase.sol";
import {LedgerUtils} from "../lib/utils/LedgerUtils.sol";
import {FEE_BASE, USDC_DECIMAL, USDC_HASH} from "../lib/types/Constants.sol";

/// @title Ledger Core Implementation
/// @notice Contains core business flow methods for the protocol vault ledger
/// @dev This contract is designed to be called via delegatecall from the main ledger contract
contract LedgerCoreImpl is LedgerBase, ILedgerCoreImpl {
    using Math for uint256;

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
    ) external {
        _check(periodId, vaultId);
        //only can be called once in a period
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        if (vaultState.isUpdateStrategyFundAssets[periodId]) {
            revert AlreadyCalled();
        }
        Signature.verifyUpdateFundAssets(periodId, vaultId, strategyFundAssets, signature, engine);
        uint256 assetsAfterFee;
        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            assetsAfterFee += _processSingleFund(vaultState, strategyFundAssets[i]);
        }

        vaultState.mainAssetsAfterFee = assetsAfterFee;
        vaultState.isUpdateStrategyFundAssets[periodId] = true;

        emit StrategyFundAssetsUpdate(periodId, vaultId, assetsAfterFee, _buildEvent(vaultId, strategyFundAssets));
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
    ) external {
        _check(periodId, vaultId);
        Signature.verifyUpdateLPAndStrategyFund(periodId, vaultId, updateUserLedgerParams, signature, engine);

        OperationRes[] memory operationRes = new OperationRes[](updateUserLedgerParams.length);

        //handle lp operation
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        for (uint256 i = 0; i < updateUserLedgerParams.length; i++) {
            bytes32 requestId = updateUserLedgerParams[i].operation.requestId;
            uint256 amount;

            if (!vaultState.isOpHandled[requestId]) {
                Operation memory operation = updateUserLedgerParams[i].operation;
                bytes32 id = operation.id;
                uint256 operationAmount = operation.amount;
                OperationType operationType = updateUserLedgerParams[i].operationType;

                if (operationType == OperationType.LP_DEPOSIT) {
                    //handle LP deposit
                    amount = _handleLpDeposit(vaultId, id, operationAmount);
                } else if (operationType == OperationType.LP_WITHDRAW) {
                    //handle LP withdraw
                    amount = _handleLpWithdraw(vaultId, requestId, id, operationAmount);
                } else if (operationType == OperationType.SP_DEPOSIT) {
                    //handle SP deposit
                    amount = _handleSPDeposit(vaultId, id, operationAmount);
                } else if (operationType == OperationType.SP_WITHDRAW) {
                    //handle SP withdraw
                    amount = _handleSpWithdraw(vaultId, requestId, id, operationAmount);
                } else {
                    revert InvalidType();
                }

                operationRes[i] =
                    OperationRes({id: operation.id, requestId: requestId, amount: amount, operationType: operationType});
                vaultState.isOpHandled[requestId] = true;
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
    ) external {
        _check(periodId, vaultId);
        //only can be called once in a period
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        if (vaultState.isAllocatedToFunds[periodId]) {
            revert AlreadyCalled();
        }
        Signature.verifyAllocateToFunds(periodId, vaultId, strategyProviderIds, signature, engine);

        StrategyFundToken storage strategyFundToken;
        uint256 totalMainAssetsInFund;

        //for event
        AllocateFundRes[] memory allocateFundRes = new AllocateFundRes[](strategyProviderIds.length);

        //gas saving
        uint256 depositAssets = vaultState.pendingLpDepositAssets;
        uint256 withdrawAssets = vaultState.pendingLpWithdrawAssets;

        if (strategyProviderIds.length == 1) {
            strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderIds[0], USDC_HASH);

            //deposit
            uint256 distributeDepositShares = LedgerUtils._convertToShares(
                depositAssets, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
            );
            strategyFundToken.pendingState.pendingTotalAssets += depositAssets;
            strategyFundToken.pendingState.pendingTotalShares += distributeDepositShares;
            strategyFundToken.pendingState.pendingMainShares += distributeDepositShares;

            //withdraw
            uint256 pendingLpWithdrawShares = LedgerUtils._convertToShares(
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
                strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderIds[i], USDC_HASH);
                allocateFundRes[i].strategyProviderId = strategyProviderIds[i];
                totalMainAssetsInFund += LedgerUtils._convertToAssets(
                    strategyFundToken.mainShares,
                    strategyFundToken.fundAssetsAfterFee,
                    strategyFundToken.totalShares,
                    Math.Rounding.Floor
                );
            }
            //allocate deposit
            if (depositAssets > 0) {
                for (uint256 i = 0; i < strategyProviderIds.length; i++) {
                    strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderIds[i], USDC_HASH);

                    uint256 mainAssetsInFund = LedgerUtils._convertToAssets(
                        strategyFundToken.mainShares,
                        strategyFundToken.fundAssetsAfterFee,
                        strategyFundToken.totalShares,
                        Math.Rounding.Floor
                    );
                    uint256 distributeDepositAssets =
                        depositAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Floor);

                    uint256 distributeDepositShares = LedgerUtils._convertToShares(
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
                    strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderIds[i], USDC_HASH);

                    uint256 mainAssetsInFund = LedgerUtils._convertToAssets(
                        strategyFundToken.mainShares,
                        strategyFundToken.fundAssetsAfterFee,
                        strategyFundToken.totalShares,
                        Math.Rounding.Floor
                    );
                    uint256 distributeWithdrawAssets =
                        withdrawAssets.mulDiv(mainAssetsInFund, totalMainAssetsInFund, Math.Rounding.Ceil);
                    uint256 distributeWithdrawShares = LedgerUtils._convertToShares(
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

        vaultState.isAllocatedToFunds[periodId] = true;
        emit FundAllocated(periodId, vaultId, strategyProviderIds, allocateFundRes);
    }

    /// @notice Operator settle main and strategy fund info after checking all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyProviderIds each strategy provider id
    /// @param signature signature of BE
    function settleMainAndStrategyFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external {
        _check(periodId, vaultId);
        Signature.verifySettleMainAndStrategyFunds(periodId, vaultId, strategyProviderIds, signature, engine);
        //settle MAIN
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        vaultState.mainShares = vaultState.pendingMainShares;
        StrategyFundState[] memory strategyFundStates = new StrategyFundState[](strategyProviderIds.length);

        //settle strategy fund
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            StrategyFundToken storage strategyFundToken =
                _getStrategyFundToken(vaultId, strategyProviderIds[i], USDC_HASH);

            //hwm must be updated firstly
            strategyFundToken.hwm = _calculateHWM(vaultId, strategyProviderIds[i]);

            //update pending state to actual state
            PendingState storage pendingState = strategyFundToken.pendingState;
            strategyFundToken.totalShares = pendingState.pendingTotalShares;
            strategyFundToken.totalAssets = pendingState.pendingTotalAssets;
            strategyFundToken.mainShares = pendingState.pendingMainShares;
            strategyFundToken.strategyProviderShares = pendingState.pendingStrategyProviderShares;

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

        emit MainAndStrategyFundsSettled(periodId, vaultId, vaultState.mainShares, strategyFundStates);
    }

    /// @notice Operator settle all LP infos after checking all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param accountIds each account id
    /// @param signature signature of BE
    function settleAccounts(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds, bytes calldata signature)
        external
    {
        _check(periodId, vaultId);
        Signature.verifySettleAccount(periodId, vaultId, accountIds, signature, engine);

        AccountState[] memory accountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            AccountToken storage accountToken = _getAccountToken(vaultId, accountIds[i], USDC_HASH);
            accountToken.shares = accountToken.pendingShares;

            //for event
            accountStates[i] = AccountState({accountId: accountIds[i], shares: accountToken.shares});
        }

        emit AccountSettled(periodId, vaultId, accountStates);
    }

    /// @notice Operator update period id after last period finish
    /// @param periodId latest periodId
    /// @param vaultId vault id
    /// @param signature signature  of BE
    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes calldata signature) external {
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        if (periodId != vaultState.latestPeriodId) {
            revert InvalidPeriodId();
        }
        Signature.verifyUpdatePeriodId(periodId, vaultId, signature, engine);

        vaultState.pendingLpDepositAssets = 0;
        vaultState.pendingLpWithdrawAssets = 0;

        vaultState.latestPeriodId++;

        emit PeriodIdUpdated(periodId, vaultId);
    }

    /// @notice Distribute assets to strategy
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
        // Only can be called once in a period
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        if (vaultState.isAssetDistributed[periodId]) {
            revert AlreadyCalled();
        }

        Signature.verifyAssetsDistribution(periodId, vaultId, assetsDistributions, signature, engine);
        address vault = idToVault[vaultId];
        bytes32 broker = vaultBroker[vaultId];

        // Change state
        vaultState.isAssetDistributed[periodId] = true;

        for (uint256 i = 0; i < assetsDistributions.length; i++) {
            // Construct StrategyExecution
            AssetsDistribution memory assetsDistribution =
                AssetsDistribution({chainId: assetsDistributions[i].chainId, assets: assetsDistributions[i].assets});

            // Cross chain message
            StrategyVaultCCMessage memory message = _createCCMessage(
                PayloadType.ASSETS_DISTRIBUTION,
                assetsDistributions[i].chainId,
                abi.encode(periodId, vault, broker, assetsDistribution)
            );

            // Cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit AssetsDistributed(periodId, vaultId);
    }

    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        uint256 ccFee,
        bytes32 vaultId,
        bytes32[] memory requestIds,
        bytes calldata signature
    ) external {
        Signature.verifyUpdateUnclaimed(chainId, periodId, ccFee, vaultId, requestIds, signature, engine);

        // Length that unhandled requestId
        uint256 len;
        for (uint256 i = 0; i < requestIds.length; i++) {
            if (_isValidRequestId(vaultId, requestIds[i])) {
                len++;
            }
        }

        ClaimInfo[] memory userClaimInfos = new ClaimInfo[](len);

        // Cross chain message
        if (len != 0) {
            // New index to avoid out of range
            uint256 index;

            // Handle requestid claim
            for (uint256 i = 0; i < requestIds.length; i++) {
                // Ignore if handled
                if (_isValidRequestId(vaultId, requestIds[i])) {
                    VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
                    userClaimInfos[index] = vaultState.userClaimInfo[requestIds[i]];
                    vaultState.isUserClaimHandled[requestIds[i]] = true;
                    index++;
                    delete vaultState.userClaimInfo[requestIds[i]];
                }
            }

            address vault = idToVault[vaultId];
            bytes32 broker = vaultBroker[vaultId];

            StrategyVaultCCMessage memory message;
            if (ccFee == 0) {
                message = _createCCMessage(
                    PayloadType.UPDATE_USER_CLAIM, chainId, abi.encode(periodId, ccFee, vault, broker, userClaimInfos)
                );

                (ccFee,) = IVaultCrossChainManager(crossChainManager).quoteClaim(chainId, message);
                message = _createCCMessage(
                    PayloadType.UPDATE_USER_CLAIM,
                    chainId,
                    abi.encode(periodId, ccFee / index, vault, broker, userClaimInfos)
                );
            } else {
                message = _createCCMessage(
                    PayloadType.UPDATE_USER_CLAIM, chainId, abi.encode(periodId, ccFee, vault, broker, userClaimInfos)
                );
            }

            // Cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit UnclaimedAssetsUpdated(periodId, vaultId, userClaimInfos);
    }

    /*=========================================================================================
    *                                       INTERNAL HELPER FUNCTIONS
    *=========================================================================================*/

    /// @notice Check if period ID is valid
    /// @param periodId Period ID to check
    /// @param vaultId Vault ID to get the latest period from
    function _check(uint256 periodId, bytes32 vaultId) internal view {
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        if (periodId != vaultState.latestPeriodId) {
            revert InvalidPeriodId();
        }
    }

    function _handleLpDeposit(bytes32 vaultId, bytes32 accountId, uint256 amount) internal returns (uint256) {
        AccountToken storage accountToken = _getAccountToken(vaultId, accountId, USDC_HASH);

        if (amount > accountToken.unAllocatedAssets) {
            revert NotEnoughLPDeposit(amount);
        }

        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        uint256 depositShares = LedgerUtils._convertToShares(
            amount, vaultState.mainAssetsAfterFee, vaultState.mainShares, Math.Rounding.Floor
        );
        //effect
        accountToken.pendingShares += depositShares;
        accountToken.unAllocatedAssets -= amount;

        vaultState.pendingMainShares += depositShares;
        vaultState.pendingLpDepositAssets += amount;

        return depositShares;
    }

    function _handleLpWithdraw(bytes32 vaultId, bytes32 requestId, bytes32 accountId, uint256 amount)
        internal
        returns (uint256)
    {
        AccountToken storage accountToken = _getAccountToken(vaultId, accountId, USDC_HASH);

        LedgerUtils.requireEnoughFrozenShares(amount, accountToken.frozenShares);

        //effect
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        uint256 withdrawAssets = LedgerUtils._convertToAssets(
            amount, vaultState.mainAssetsAfterFee, vaultState.mainShares, Math.Rounding.Floor
        );

        accountToken.pendingShares -= amount;
        accountToken.frozenShares -= amount;
        vaultState.pendingMainShares -= amount;
        vaultState.pendingLpWithdrawAssets += withdrawAssets;

        vaultState.userClaimInfo[requestId].requestId = requestId;
        vaultState.userClaimInfo[requestId].accountId = accountId;
        vaultState.userClaimInfo[requestId].assets = withdrawAssets;

        return withdrawAssets;
    }

    function _handleSPDeposit(bytes32 vaultId, bytes32 strategyProviderId, uint256 amount) internal returns (uint256) {
        //gas optimization
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderId, USDC_HASH);
        PendingState storage pendingState = strategyFundToken.pendingState;
        if (amount > strategyFundToken.unAllocatedAssets) {
            revert NotEnoughSPDeposit();
        }
        uint256 depositShares = LedgerUtils._convertToShares(
            amount, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
        );

        pendingState.pendingTotalShares += depositShares;
        pendingState.pendingStrategyProviderShares += depositShares;
        pendingState.pendingTotalAssets += amount;
        strategyFundToken.unAllocatedAssets -= amount;

        return depositShares;
    }

    function _handleSpWithdraw(bytes32 vaultId, bytes32 requestId, bytes32 strategyProviderId, uint256 amount)
        internal
        returns (uint256)
    {
        //gas optimization
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderId, USDC_HASH);
        PendingState storage pendingState = strategyFundToken.pendingState;

        LedgerUtils.requireEnoughFrozenShares(amount, strategyFundToken.frozenShares);
        uint256 spWithdrawAssets = LedgerUtils._convertToAssets(
            amount, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
        );

        //effect
        pendingState.pendingTotalShares -= amount;
        pendingState.pendingStrategyProviderShares -= amount;
        pendingState.pendingTotalAssets -= spWithdrawAssets;
        strategyFundToken.frozenShares -= amount;

        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        vaultState.userClaimInfo[requestId].requestId = requestId;
        vaultState.userClaimInfo[requestId].strategyProviderId = strategyProviderId;
        vaultState.userClaimInfo[requestId].assets = spWithdrawAssets;

        return spWithdrawAssets;
    }

    /// @notice Calculate high water mark for strategy fund
    /// @param vaultId Vault ID
    /// @param strategyProviderId Strategy provider ID
    /// @return High water mark value
    function _calculateHWM(bytes32 vaultId, bytes32 strategyProviderId) internal view returns (uint256) {
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderId, USDC_HASH);

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

    function _isValidRequestId(bytes32 vaultId, bytes32 requestId) internal view returns (bool) {
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        return !vaultState.isUserClaimHandled[requestId] && vaultState.userClaimInfo[requestId].assets > 0;
    }

    function _processSingleFund(
        VaultStateStorage storage vaultState,
        UpdateStrategyFundAssetsParams calldata strategyFundAssets
    ) internal returns (uint256 assetsAfterFee) {
        StrategyFundToken storage token =
            vaultState.strategyFundTokenInfo[strategyFundAssets.strategyProviderId][USDC_HASH];

        //reset performance fee
        token.performanceFee = 0;

        uint256 fundAssets = strategyFundAssets.totalAssets;
        uint256 fundShares = token.totalShares;
        uint256 performanceFee;

        if (fundShares > 0) {
            uint256 assetPerShare = fundAssets * 10 ** USDC_DECIMAL / fundShares;

            if (assetPerShare > token.hwm) {
                performanceFee = (assetPerShare - token.hwm) * fundShares
                    * feeRateOfFund[strategyFundAssets.strategyProviderId] / FEE_BASE / 10 ** USDC_DECIMAL;

                uint256 feeShares = LedgerUtils._convertToShares(
                    performanceFee, fundAssets - performanceFee, fundShares, Math.Rounding.Floor
                );

                token.performanceFee = performanceFee;
                token.pendingState.pendingStrategyProviderShares += feeShares;
                token.pendingState.pendingTotalShares = fundShares + feeShares;
            }

            assetsAfterFee = token.mainShares * (fundAssets - performanceFee) / token.totalShares;
        }

        //Update pending state
        token.pendingState.pendingTotalAssets = fundAssets;
        token.fundAssetsAfterFee = fundAssets - performanceFee;
    }

    function _buildEvent(bytes32 vaultId, UpdateStrategyFundAssetsParams[] calldata strategyFundAssets)
        internal
        view
        returns (UpdateStrategyFundAssetsRes[] memory res)
    {
        res = new UpdateStrategyFundAssetsRes[](strategyFundAssets.length);

        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            StrategyFundToken storage token =
                _getStrategyFundToken(vaultId, strategyFundAssets[i].strategyProviderId, USDC_HASH);
            res[i] = UpdateStrategyFundAssetsRes({
                strategyProviderId: strategyFundAssets[i].strategyProviderId,
                fundAssetsAfterFee: token.fundAssetsAfterFee,
                strategyProviderShares: token.pendingState.pendingStrategyProviderShares,
                totalShares: token.pendingState.pendingTotalShares
            });
        }
    }
}
