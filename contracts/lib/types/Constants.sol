// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

uint256 constant FEE_BASE = 100;
bytes32 constant USDC_HASH = 0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa;
uint256 constant USDC_DECIMAL = 6;
bytes32 constant ORDERLY_BROKER = 0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b;
uint256 constant LEDGER_CHAIN_ID = 291;

/*
    EIP712 Domain Info
*/
/// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
bytes32 constant TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
/// @dev `keccak256("DexRequest(uint8 payloadType,uint256 nonce,address receiver,uint256 amount,bytes32 vaultId,string token,string dexBrokerId)")`.
bytes32 constant REQUEST_HASH = 0x590ef38f093814e411b876bc59d8020504481133ef17b2b49abbdedc31d57084;
