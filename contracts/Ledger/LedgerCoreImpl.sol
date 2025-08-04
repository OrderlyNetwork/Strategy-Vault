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
import {LedgerBase} from "./LedgerBase.sol";
import {LedgerUtils} from "../lib/utils/LedgerUtils.sol";
import {FEE_BASE, USDC_DECIMAL} from "../lib/types/Constants.sol";

/// @title Ledger Core Implementation
/// @notice Contains core business flow methods for the protocol vault ledger
/// @dev This contract is designed to be called via delegatecall from the main ledger contract
contract LedgerCoreImpl is LedgerBase {
    using Math for uint256;

    // Events
    event StrategyFundAssetsUpdate(
        uint256 periodId,
        bytes32 vaultId,
        uint256 mainAssetsAfterFee,
        UpdateStrategyFundAssetsRes[] updateStrategyFundAssetsRes
    );
    event LPAndStrategyFundUpdated(uint256 periodId, bytes32 vaultId, OperationRes[] operationRes);
    event FundAllocated(
        uint256 periodId, bytes32 vaultId, bytes32[] strategyProviderIds, AllocateFundRes[] allocateFundRes
    );
    event MainAndStrategyFundsSettled(
        uint256 periodId, bytes32 vaultId, uint256 mainShares, StrategyFundState[] strategyFundStates
    );
    event AccountSettled(uint256 periodId, bytes32 vaultId, AccountState[] accountStates);
    event PeriodIdUpdated(uint256 latestPeriodId, bytes32 vaultId);
    event AssetsDistributed(uint256 periodId, bytes32 vaultId);
    event UnclaimedAssetsUpdated(uint256 periodId, bytes32 vaultId, ClaimInfo[] userClaimInfos);

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
        _check(periodId);
        //only can be called once in a period
        if (isUpdateStrategyFundAssets[periodId]) {
            revert IProtocolVaultLedger.AlreadyCalled();
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
                        feeShares = LedgerUtils._convertToShares(
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
    ) external {
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
                    revert IProtocolVaultLedger.InvalidType();
                }

                operationRes[i] =
                    OperationRes({id: operation.id, requestId: requestId, amount: amount, operationType: operationType});
                isOpHandled[requestId] = true;
            }
        }

        //emit event
        emit LPAndStrategyFundUpdated(periodId, vaultId, operationRes);
    }

    /*=========================================================================================
    *                                       INTERNAL HELPER FUNCTIONS
    *=========================================================================================*/

    /// @notice Check if period ID is valid
    /// @param periodId Period ID to check
    function _check(uint256 periodId) internal view {
        if (periodId != latestPeriodId) {
            revert IProtocolVaultLedger.InvalidPeriodId();
        }
    }

    function _handleLpDeposit(bytes32 accountId, uint256 amount) internal returns (uint256) {
        AccountToken storage accountToken = _getAccountToken(accountId);

        if (amount > accountToken.unAllocatedAssets) {
            revert IProtocolVaultLedger.NotEnoughLPDeposit(amount);
        }

        uint256 depositShares =
            LedgerUtils._convertToShares(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);
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
        uint256 withdrawAssets =
            LedgerUtils._convertToAssets(amount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);

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
            revert IProtocolVaultLedger.NotEnoughSPDeposit();
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

    function _handleSpWithdraw(bytes32 requestId, bytes32 strategyProviderId, uint256 amount)
        internal
        returns (uint256)
    {
        //gas optimization
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(strategyProviderId);
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

        userClaimInfo[requestId].requestId = requestId;
        userClaimInfo[requestId].strategyProviderId = strategyProviderId;
        userClaimInfo[requestId].assets = spWithdrawAssets;

        return spWithdrawAssets;
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
        _check(periodId);
        //only can be called once in a period
        if (isAllocatedToFunds[periodId]) {
            revert IProtocolVaultLedger.AlreadyCalled();
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
                strategyFundToken = _getStrategyFundToken(strategyProviderIds[i]);
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
                    strategyFundToken = _getStrategyFundToken(strategyProviderIds[i]);

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
                    strategyFundToken = _getStrategyFundToken(strategyProviderIds[i]);

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
    ) external {
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

        emit MainAndStrategyFundsSettled(periodId, vaultId, mainShares, strategyFundStates);
    }

    /// @notice Operator settle all LP infos after check all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param accountIds each account id
    /// @param signature signature of BE
    function settleAccounts(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds, bytes calldata signature)
        external
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
    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes calldata signature) external {
        if (periodId != latestPeriodId) {
            revert IProtocolVaultLedger.InvalidPeriodId();
        }
        Signature.verifyUpdatePeriodId(periodId, vaultId, signature, engine);

        pendingLpDepositAssets = 0;
        pendingLpWithdrawAssets = 0;

        latestPeriodId++;

        emit PeriodIdUpdated(periodId, vaultId);
    }

    /// @notice Calculate high water mark for strategy fund
    /// @param strategyProviderId Strategy provider ID
    /// @return High water mark value
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
        if (isAssetDistributed[periodId]) {
            revert IProtocolVaultLedger.AlreadyCalled();
        }

        Signature.verifyAssetsDistribution(periodId, vaultId, assetsDistributions, signature, engine);

        // Change state
        isAssetDistributed[periodId] = true;

        for (uint256 i = 0; i < assetsDistributions.length; i++) {
            // Construct StrategyExecution
            AssetsDistribution memory assetsDistribution =
                AssetsDistribution({chainId: assetsDistributions[i].chainId, assets: assetsDistributions[i].assets});

            // Cross chain message
            StrategyVaultCCMessage memory message = _createCCMessage(
                PayloadType.ASSETS_DISTRIBUTION,
                assetsDistributions[i].chainId,
                abi.encode(periodId, assetsDistribution)
            );

            // Cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit AssetsDistributed(periodId, vaultId);
    }

    /// @notice Update unclaimed assets after funds transfer to protocol vault
    /// @param chainId Chain ID that unclaimed assets will be updated
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
        Signature.verifyUpdateUnclaimed(chainId, periodId, vaultId, requestIds, signature, engine);

        // Length that unhandled requestId
        uint256 len;
        for (uint256 i = 0; i < requestIds.length; i++) {
            if (_isValidRequestId(requestIds[i])) {
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
                if (_isValidRequestId(requestIds[i])) {
                    userClaimInfos[index] = userClaimInfo[requestIds[i]];
                    isUserClaimHandled[requestIds[i]] = true;
                    index++;
                    delete userClaimInfo[requestIds[i]];
                }
            }

            uint256 ccFee;

            // Cross chain message
            StrategyVaultCCMessage memory message =
                _createCCMessage(PayloadType.UPDATE_USER_CLAIM, chainId, abi.encode(periodId, ccFee, userClaimInfos));
            (ccFee,) = IVaultCrossChainManager(crossChainManager).quoteClaim(chainId, message);

            // Set gas
            message = _createCCMessage(
                PayloadType.UPDATE_USER_CLAIM, chainId, abi.encode(periodId, ccFee / len, userClaimInfos)
            );

            // Cross-chain
            IVaultCrossChainManager(crossChainManager).sendMessage(message);
        }

        emit UnclaimedAssetsUpdated(periodId, vaultId, userClaimInfos);
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

    function _isValidRequestId(bytes32 requestId) internal view returns (bool) {
        return !isUserClaimHandled[requestId] && userClaimInfo[requestId].assets > 0;
    }
}
