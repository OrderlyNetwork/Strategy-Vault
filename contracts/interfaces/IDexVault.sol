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
    function getDepositFee(address receiver, VaultDepositFE calldata data) external view returns (uint256);
    function depositId() external view returns (uint64);
    function depositFeeEnabled() external view returns (bool);
}
