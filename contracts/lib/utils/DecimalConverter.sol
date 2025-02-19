// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

library DecimalConverter {
    /// @notice convert token amount to dst chain decimal
    /// @param tokenAmount token amount
    /// @param srcDecimal src chain decimal
    /// @param dstDecimal dst chain decimal
    function convertDecimal(uint256 tokenAmount, uint256 srcDecimal, uint256 dstDecimal)
        internal
        pure
        returns (uint256)
    {
        if (srcDecimal == dstDecimal) {
            return tokenAmount;
        } else if (srcDecimal > dstDecimal) {
            return tokenAmount / 10 ** (srcDecimal - dstDecimal);
        } else {
            return tokenAmount * 10 ** (dstDecimal - srcDecimal);
        }
    }
}
