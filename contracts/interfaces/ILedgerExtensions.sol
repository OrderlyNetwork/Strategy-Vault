// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    UpdateLedgerParams,
    DexRequest,
    OperationRes
} from "../lib/types/LedgerStruct.sol";
import {OperationData} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/VaultStruct.sol";

/// @title ILedgerExtensions
/// @notice Interface for the Ledger Extensions contract
/// @dev Contains request handling and auxiliary functions that are called via delegatecall
interface ILedgerExtensions {
    // Custom errors - Extensions contract specific
    error InvalidOperator();
    error AlreadyCalled();
    error InvalidChainType();

    // Events - Extensions contract specific
    event InvalidFrozenSharesRemoved(bytes32 vaultId, OperationRes[] operationRes);
    event DexRequestsHandled(DexRequest dexRequest);
    event DexWithdrawNotEnough(uint256 dexRequestId);
    event OperationHandled(PayloadType payloadType, uint256 chainId, OperationData operationData);
    event NotEnoughWithdrawShare(PayloadType payloadType, uint256 chainId, uint256 chainNonce);

    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external;
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData)
        external;
    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external;
}
