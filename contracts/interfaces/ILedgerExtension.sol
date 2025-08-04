// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {
    UpdateLedgerParams,
    DexRequest,
    OperationRes
} from "../lib/types/LedgerStruct.sol";
import {OperationData} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";

/// @title ILedgerExtension
/// @notice Interface for the Ledger Extension contract
/// @dev Contains request handling and auxiliary functions that are called via delegatecall
interface ILedgerExtension {
    // Events
    event OperationHandled(PayloadType payloadType, uint256 chainId, OperationData operationData);
    event NotEnoughWithdrawShare(PayloadType payloadType, uint256 chainId, uint256 chainNonce);
    event DexRequestsHandled(DexRequest request);
    event DexWithdrawNotEnough(uint256 requestId);
    event InvalidFrozenSharesRemoved(bytes32 vaultId, OperationRes[] operationRes);
    
    /// @notice Handles operations from vault
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData)
        external;

    /// @notice Handle DEX requests
    /// @param dexRequests Array of DEX requests
    /// @param signature Signature for verification
    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external;

    /// @notice Remove invalid frozen shares for LP or SP that were incorrectly added
    /// @param vaultId The vault ID
    /// @param params The parameters containing the invalid frozen shares to remove
    /// @param signature The signature to verify
    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external;
}
