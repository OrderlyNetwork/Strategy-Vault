pragma solidity ^0.8.26;

enum VaultType {
    PROTOCOL,
    USER
}
enum VaultState {
    OPEN,
    SHUTDOWN,
    CLOSED
}
enum PayloadType {
    LP_DEPOSIT,
    SP_DEPOSIT,
    LP_WITHDRAW,
    SP_WITHDRAW,
    TRANSFER_TO_ORDERLY_DEX
}

struct OperationParams {
    PayloadType payloadType;
    address token;
    address receiver;
    uint256 amount;
    bytes32 brokerHash;
}

struct OperationData {
    ///@dev USER or PROTOCOL
    VaultType vaultType;
    ///@dev sender
    address sender;
    ///@dev receiver
    address receiver;
    ///@dev global deposit nonce
    uint256 nonce;
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