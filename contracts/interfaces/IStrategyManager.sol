// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IStrategyVault {
    function deployVault(address vault) external returns (address);
}
