// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*




*/


interface ILedger {
    mapping(address => mapping(address => uint256)) public strategyBalances;  

}
