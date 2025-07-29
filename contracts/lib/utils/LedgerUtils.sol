// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OperationRes} from "../types/LedgerStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "../types/CrossChainStruct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {USDC_DECIMAL} from "../types/Constants.sol";

/// @title Ledger Utils
/// @notice Library containing utility functions for ProtocolVaultLedger and LedgerExtensions
/// @dev These functions are pure or view functions that don't depend on storage state
library LedgerUtils {
    error NotEnoughFrozenShare(uint256 amount);

    using Math for uint256;

    /**
     * @dev Internal conversion function (from assets amount to shares) with support for rounding direction.
     * @dev This method is kept in main contract for internal use by main contract functions
     */
    function _convertToShares(uint256 amount, uint256 _totalAssets, uint256 _totalShares, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        uint256 decimal = USDC_DECIMAL;
        return (_totalAssets == 0)
            ? amount.mulDiv(10 ** decimal, 10 ** decimal, rounding)
            : amount.mulDiv(_totalShares, _totalAssets, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     * @dev This method is kept in main contract for internal use by main contract functions
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _totalShares, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        uint256 decimal = USDC_DECIMAL;
        return (_totalShares == 0)
            ? shares.mulDiv(10 ** decimal, 10 ** decimal, rounding)
            : shares.mulDiv(_totalAssets, _totalShares, rounding);
    }

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
