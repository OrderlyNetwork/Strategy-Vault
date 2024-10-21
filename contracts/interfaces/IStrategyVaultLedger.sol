// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {DepositData, VaultType, PayloadType, StrategyVaultCCMessage} from "../lib/Struct.sol";

interface IStrategyVaultLedger {
    function vaultDeposit(DepositData memory depositData) external;
}
