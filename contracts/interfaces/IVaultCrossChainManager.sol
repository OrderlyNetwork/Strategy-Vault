// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {DepositData,VaultType,PayloadType,StrategyVaultCCMessage} from "../lib/Struct.sol";


interface IVaultCrossChainManager {
    function vaultSendToLedger(StrategyVaultCCMessage memory strategyVaultCCMessage) external;
    function testCounter() external;
}