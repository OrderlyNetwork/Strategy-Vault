// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {DepositData, VaultType, PayloadType, StrategyVaultCCMessage} from "../lib/Struct.sol";

interface IVaultCrossChainManager {
    function vaultSendToLedger(
      StrategyVaultCCMessage memory _message
    ) external payable;

    function testCounter() external;
}
