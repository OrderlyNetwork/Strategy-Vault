// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    AccountToken,
    StrategyFundToken,
    UpdateLedgerParams,
    AssetsDistribution,
    ClaimInfo,
    ChainType,
    DexRequest,
    DexRequestData,
    OperationRes,
    OperationType,
    Operation
} from "../lib/types/LedgerStruct.sol";
import {Signature} from "../lib/utils/Signature.sol";
import {VaultUtils} from "../lib/utils/VaultUtils.sol";
import {PayloadType, StrategyVaultCCMessage} from "../lib/types/CrossChainStruct.sol";
import {IVaultCrossChainManager} from "../interfaces/IVaultCrossChainManager.sol";
import {LedgerBase} from "./LedgerBase.sol";
import {LedgerUtils} from "../lib/utils/LedgerUtils.sol";
import {ILedgerExtensions} from "../interfaces/ILedgerExtensions.sol";
import {IProtocolVaultLedger} from "../interfaces/IProtocolVaultLedger.sol";
import {OperationData} from "../lib/types/VaultStruct.sol";

/// @title Ledger Extensions
/// @notice This contract contains low-frequency functions for ProtocolVaultLedger
/// @dev This contract is designed to be called via delegatecall from the main ledger contract
contract LedgerExtensions is LedgerBase, ILedgerExtensions {
    using Math for uint256;

    /// @notice Handles operations from vault
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData)
        external
    {
        bytes32 id = operationData.accountId == bytes32(0) ? operationData.strategyProviderId : operationData.accountId;

        if (_handleRequest(payloadType, id, operationData.tokenHash, operationData.amount)) {
            emit OperationHandled(payloadType, chainId, operationData);
        } else {
            emit NotEnoughWithdrawShare(payloadType, chainId, operationData.chainNonce);
        }
    }

    /// @notice Handle DEX requests
    /// @param dexRequests Array of DEX requests
    /// @param signature Signature for verification
    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external  {
        // Verify engine signature
        Signature.verifyDexRequest(dexRequests, signature, engine);

        for (uint256 i = 0; i < dexRequests.length; i++) {
            DexRequest calldata request = dexRequests[i];
            uint256 requestId = request.dexRequestData.dexRequestId;

            // Verify if dex request is handled
            if (isDexRequestHandled[requestId]) {
                revert ILedgerExtensions.AlreadyCalled();
            }

            ChainType chainType = request.chainType;
            if (chainType == ChainType.EVM) {
                _verifyEVMRequest(request);
            } else {
                revert ILedgerExtensions.InvalidChainType();
            }

            // Update record
            bytes32 tokenHash = keccak256(abi.encodePacked(request.dexRequestData.token));
            isDexRequestHandled[requestId] = true;

            if (
                _handleRequest(request.dexRequestData.payloadType, request.id, tokenHash, request.dexRequestData.amount)
            ) {
                emit DexRequestsHandled(request);
            } else {
                emit DexWithdrawNotEnough(requestId);
            }
        }
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
            revert ILedgerExtensions.AlreadyCalled();
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

    /// @notice Remove invalid frozen shares for LP or SP that were incorrectly added
    /// @param vaultId The vault ID
    /// @param params The parameters containing the invalid frozen shares to remove
    /// @param signature The signature to verify
    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external
    {
        Signature.verifyRemoveInvalidFrozenShares(vaultId, params, signature, engine);

        OperationRes[] memory operationRes = new OperationRes[](params.length);

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
                    LedgerUtils.requireEnoughFrozenShares(operationAmount, accountToken.frozenShares);
                    accountToken.frozenShares -= operationAmount;
                } else if (operationType == OperationType.SP_WITHDRAW) {
                    // Handle SP frozen shares removal
                    StrategyFundToken storage strategyFundToken = _getStrategyFundToken(id);
                    LedgerUtils.requireEnoughFrozenShares(operationAmount, strategyFundToken.frozenShares);
                    strategyFundToken.frozenShares -= operationAmount;
                } else {
                    revert IProtocolVaultLedger.InvalidType();
                }

                // Event
                operationRes[i] =
                    OperationRes({id: id, requestId: requestId, amount: operationAmount, operationType: operationType});

                isOpHandled[requestId] = true;
            }
        }

        emit InvalidFrozenSharesRemoved(vaultId, operationRes);
    }

    //--------------------------------------INTERNAL HELPER FUNCTIONS--------------------------------------------
    function _isValidRequestId(bytes32 requestId) internal view returns (bool) {
        return !isUserClaimHandled[requestId] && userClaimInfo[requestId].assets > 0;
    }

    function _verifyEVMRequest(DexRequest calldata request) internal view {
        DexRequestData calldata data = request.dexRequestData;

        address receiver = address(uint160(uint256(data.receiver)));
        address vault = IVaultCrossChainManager(crossChainManager).vault();

        // Verify id
        VaultUtils.validateId(vault, receiver, vaultBroker[data.vaultId], request.id);

        // Verify signature
        Signature.verifyEVMSig(data, request.v, request.r, request.s, request.chainId, receiver);
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

    function _handleRequest(PayloadType payloadType, bytes32 id, bytes32 tokenHash, uint256 amount)
        internal
        virtual
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
            revert IProtocolVaultLedger.InvalidType();
        }
        return true;
    }

    function _checkWithdraw(uint256 withdrawAmount, uint256 frozenAmount, uint256 totalAmount)
        internal
        pure
        returns (bool)
    {
        return withdrawAmount + frozenAmount <= totalAmount;
    }

    /// @notice Check if period ID is valid
    /// @param periodId Period ID to check
    function _check(uint256 periodId) internal view {
        if (periodId != latestPeriodId) {
            revert IProtocolVaultLedger.InvalidPeriodId();
        }
    }
}
