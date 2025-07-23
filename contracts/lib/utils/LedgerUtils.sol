// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OperationRes} from "../types/LedgerStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "../types/CrossChainStruct.sol";

/// @title Ledger Utils
/// @notice Library containing utility functions for ProtocolVaultLedger and LedgerExtensions
/// @dev These functions are pure or view functions that don't depend on storage state
library LedgerUtils {
    // Custom errors
    error NotEnoughFrozenShare(uint256 amount);

    /// @notice Check if there are enough frozen shares for withdrawal
    /// @param amount Amount to withdraw
    /// @param frozenShares Available frozen shares
    /// @dev Reverts if not enough frozen shares
    function requireEnoughFrozenShares(uint256 amount, uint256 frozenShares) internal pure {
        if (amount > frozenShares) {
            revert NotEnoughFrozenShare(amount);
        }
    }
} 