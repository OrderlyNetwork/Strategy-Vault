// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AdapterDeposit} from "../lib/types/VaultStruct.sol";

interface IVaultAdapter {
    event DepositFromCeffu(AdapterDeposit adapterDeposit, bool isNative);
    event OperatorSet(address operator);
    event DexVaultSet(address dexVault);

    error Unauthorized();
    error ZeroAddress();
    error InvalidRoleType();
    error InvalidTokenHash();
    error InvalidNativeAmount();
    error BrokerNotAllowed();
    error RecordAlreadyHandled(uint256 recordId);
    error InvalidAmount();
}
