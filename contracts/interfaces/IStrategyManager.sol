// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStrategyVault {
    function deployVault(address vault) external returns (address);
}
