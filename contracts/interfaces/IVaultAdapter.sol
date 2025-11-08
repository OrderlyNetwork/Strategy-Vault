// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AdapterDeposit, AdapterDepositLegacy} from "../lib/types/VaultStruct.sol";

interface IVaultAdapter {
    event DepositFromCeffu(AdapterDeposit adapterDeposit, bool isNative);
    event OperatorSet(address operator);
    event DexVaultSet(address dexVault);
    event EngineSet(address engine);
    event BrokerAllowedSet(bytes32 brokerHash, bool isAllowed);
    event TokenHashToTokenSet(bytes32 tokenHash, address token);
    event ProtocolVaultSet(address protocolVault);
    event DepositFromCeffu(AdapterDepositLegacy adapterDeposit, bool isNative);

    //0x82b42900
    error Unauthorized();
    //0xd92e233d
    error ZeroAddress();
    //0x6eaf1c06
    error InvalidRoleType();
    //0x29a3ee79
    error InvalidTokenHash();
    //0x44e8bd2c
    error InvalidNativeAmount();
    error BrokerNotAllowed();
    error RecordAlreadyHandled(uint256 recordId);
    error InvalidAmount();

    function depositTo(AdapterDeposit memory adapterDeposit, bytes calldata signature) external;
    function depositNative(AdapterDeposit memory adapterDeposit, bytes calldata signature) external;
}
