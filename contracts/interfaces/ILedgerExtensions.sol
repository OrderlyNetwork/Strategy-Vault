// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    UpdateLedgerParams, AssetsDistribution, ClaimInfo, DexRequest, OperationRes
} from "../lib/types/LedgerStruct.sol";
import {OperationData} from "../lib/types/VaultStruct.sol";

/// @title ILedgerExtensions
/// @notice Interface for the Ledger Extensions contract
/// @dev Contains low-frequency functions that are called via delegatecall
interface ILedgerExtensions {
    // Custom errors - Extensions contract specific
    error InvalidOperator();
    error AlreadyCalled();
    error InvalidChainType();

    // Events - Extensions contract specific
    event AssetsDistributed(uint256 periodId, bytes32 vaultId);
    event UnclaimedAssetsUpdated(uint256 periodId, bytes32 vaultId, ClaimInfo[] claimInfos);
    event InvalidFrozenSharesRemoved(bytes32 vaultId, OperationRes[] operationRes);
    event DexRequestsHandled(DexRequest dexRequest);
    event DexWithdrawNotEnough(uint256 dexRequestId);
    event OperationHandled(PayloadType payloadType, uint256 chainId, OperationData operationData);

    //--------------------------------------LOW FREQUENCY FUNCTIONS-----------------------------------------

    /// @notice Handle DEX requests (low frequency)
    /// @param dexRequests Array of DEX requests
    /// @param signature Signature for verification
    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external;

    /// @notice Distribute assets to strategy (low frequency)
    /// @param periodId Period ID
    /// @param vaultId Vault ID
    /// @param assetsDistributions Asset distribution info
    /// @param signature Signature for verification
    function distributeAssets(
        uint256 periodId,
        bytes32 vaultId,
        AssetsDistribution[] memory assetsDistributions,
        bytes calldata signature
    ) external;

    /// @notice Update unclaimed assets (low frequency)
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
    ) external;

    /// @notice Remove invalid frozen shares (low frequency)
    /// @param vaultId The vault ID
    /// @param params The parameters containing the invalid frozen shares to remove
    /// @param signature The signature to verify
    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external;

    /// @notice Handle user claims
    function handleOpFromVault(uint256 payloadType, uint256 chainId, OperationData calldata operationData) external;
}
