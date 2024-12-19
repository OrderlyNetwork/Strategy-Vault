// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct VaultDepositFE {
    bytes32 accountId;
    bytes32 brokerHash;
    bytes32 tokenHash;
    uint128 tokenAmount;
}

interface IDexVault {
    function depositTo(address receiver, VaultDepositFE calldata data) external payable;
}
