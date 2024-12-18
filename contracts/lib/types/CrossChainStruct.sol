// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

enum PayloadType {
    LP_DEPOSIT,
    SP_DEPOSIT,
    LP_WITHDRAW,
    SP_WITHDRAW,
    ASSETS_DISTRIBUTION,
    UPDATE_USER_CLAIM  
}

struct StrategyVaultCCMessage {
    /// @dev payloadType is the type of the payload
    PayloadType payloadType;
    uint256 srcChainId;
    uint256 dstChainId;
    /// @dev payload is the data to be sent
    bytes payload;
}

struct LzOptions {
    uint128 gas;
    uint128 value;
}

