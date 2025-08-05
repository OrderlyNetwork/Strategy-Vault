// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

/// @title Ed25519 Library Interface
/// @notice Interface for Ed25519 signature verification
interface IEd25519 {
    /// @notice Verify Ed25519 signature
    /// @param k Public key (32 bytes)
    /// @param r Signature R component (32 bytes)
    /// @param s Signature S component (32 bytes)
    /// @param m Message to verify
    /// @return success True if signature is valid
    function verify(bytes32 k, bytes32 r, bytes32 s, bytes memory m) external pure returns (bool success);
}
