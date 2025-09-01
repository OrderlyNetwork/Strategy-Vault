// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    AccountToken,
    StrategyFundToken,
    UpdateLedgerParams,
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
import {PayloadType} from "../lib/types/CrossChainStruct.sol";
import {IVaultCrossChainManager} from "../interfaces/IVaultCrossChainManager.sol";
import {LedgerBase} from "./LedgerBase.sol";
import {LedgerUtils} from "../lib/utils/LedgerUtils.sol";
import {ILedgerExtension} from "../interfaces/ILedgerExtension.sol";
import {OperationData} from "../lib/types/VaultStruct.sol";

/// @title Ledger Extension
/// @notice Contains request handling and other auxiliary functions for the protocol vault ledger
/// @dev This contract is designed to be called via delegatecall from the main ledger contract
contract LedgerExtension is LedgerBase, ILedgerExtension {
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
    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external {
        // Verify engine signature
        Signature.verifyDexRequest(dexRequests, signature, engine);

        for (uint256 i = 0; i < dexRequests.length; i++) {
            DexRequest calldata request = dexRequests[i];
            uint256 requestId = request.dexRequestData.dexRequestId;

            // Verify if dex request is handled
            if (isDexRequestHandled[requestId]) {
                revert AlreadyCalled();
            }

            ChainType chainType = request.chainType;
            if (chainType == ChainType.EVM) {
                _verifyEVMRequest(request);
            } else if (chainType == ChainType.SOL) {
                _verifySolRequest(request);
            } else {
                revert InvalidType();
            }

            // Update record
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
                    revert InvalidType();
                }

                // Event
                operationRes[i] =
                    OperationRes({id: id, requestId: requestId, amount: operationAmount, operationType: operationType});

                isOpHandled[requestId] = true;
            }
        }

        emit InvalidFrozenSharesRemoved(vaultId, operationRes);
    }

    /*=========================================================================================
    *                                       INTERNAL HELPER FUNCTIONS
    *=========================================================================================*/

    function _verifyEVMRequest(DexRequest calldata request) internal view {
        DexRequestData calldata data = request.dexRequestData;

        address receiver = address(uint160(uint256(data.receiver)));
        // Verify id
        if (!VaultUtils.validateId(protocolVault, receiver, vaultBroker[data.vaultId], request.id)) {
            revert InvalidId();
        }

        // Verify signature
        Signature.verifyEVMSig(data, request.v, request.r, request.s, request.chainId, receiver);
    }

    function _verifySolRequest(DexRequest calldata request) internal view {
        DexRequestData calldata data = request.dexRequestData;

        // Verify id
        if (!VaultUtils.validateAccountId(data.receiver, vaultBroker[data.vaultId], request.id)) {
            revert InvalidId();
        }

        Signature.verifySOLSig(data, request.r, request.s, request.chainId, data.receiver);
    }

    function _handleRequest(PayloadType payloadType, bytes32 id, bytes32 tokenHash, uint256 amount)
        internal
        virtual
        returns (bool)
    {
        AccountToken storage accountToken;
        StrategyFundToken storage strategyFundToken;

        if (payloadType == PayloadType.LP_DEPOSIT) {
            accountToken = accountTokenInfo[id][tokenHash];
            accountToken.unAllocatedAssets += amount;
        } else if (payloadType == PayloadType.LP_WITHDRAW) {
            accountToken = accountTokenInfo[id][tokenHash];
            if (_checkWithdraw(amount, accountToken.frozenShares, accountToken.pendingShares)) {
                accountToken.frozenShares += amount;
            } else {
                return false;
            }
        } else if (payloadType == PayloadType.SP_DEPOSIT) {
            strategyFundToken = strategyFundTokenInfo[id][tokenHash];
            strategyFundToken.unAllocatedAssets += amount;
        } else if (payloadType == PayloadType.SP_WITHDRAW) {
            strategyFundToken = strategyFundTokenInfo[id][tokenHash];
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

    function _checkWithdraw(uint256 withdrawAmount, uint256 frozenAmount, uint256 totalAmount)
        internal
        pure
        returns (bool)
    {
        return withdrawAmount + frozenAmount <= totalAmount;
    }
}
