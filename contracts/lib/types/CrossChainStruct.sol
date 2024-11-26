// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
enum PayloadType {
    LP_DEPOSIT,
    SP_DEPOSIT,
    LP_WITHDRAW,
    SP_WITHDRAW,
    TRANSFER_TO_ORDERLY_DEX
}
struct StrategyVaultCCMessage {
    /// @dev payloadType is the type of the payload
    uint8 payloadType;
    /// @dev chainId is the chain id of the destination chain
    uint256 chainId;
    /// @dev payload is the data to be sent
    bytes payload;
}

