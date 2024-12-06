// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PayloadType} from "./CrossChainStruct.sol";
enum VaultType {
    PROTOCOL,
    USER
}

enum RoleType{
    LP,
    SP
}
enum VaultState {
    OPEN,
    SHUTDOWN,
    CLOSED
}

struct OperationParams {
    PayloadType payloadType;
    address receiver;
    uint256 amount;
    bytes32 brokerHash;
    bytes32 tokenHash;
}

struct OperationData {
    ///@dev USER or PROTOCOL
    VaultType vaultType;
    ///@dev sender
    address sender;
    ///@dev receiver
    address receiver;
    ///@dev deposit nonce on a specific chain
    uint256 chainNonce;
    ///@dev deposit assets amount or withdraw shares amount
    uint256 amount;
    ///@dev keccak256(abi.encodePacked(brokerHash, vault address))
    bytes32 vaultId;
    ///@dev keccak256(abi.encodePacked(receiver, brokerHash))
    bytes32 accountId;
    ///@dev bytes32(0)for LP_Deposit, keccak256(vault address, sp address, brokerHash)) for SP_Deposit
    bytes32 strategyProviderId;
    ///@dev token hash
    bytes32 tokenHash;
    ///@dev keccak256(abi.encodePacked(broker address))
    bytes32 brokerHash;
}

struct UserClaimedInfo {
    uint256 unClaimedAssets;
    uint256[] requests;
}
