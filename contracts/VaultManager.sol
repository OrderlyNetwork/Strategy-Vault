// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CREATE3} from "solady/src/utils/CREATE3.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Factory for deploying contracts to deterministic addresses via CREATE3
/// @notice Enables deploying contracts using CREATE3. Each deployer (msg.sender) has
/// its own namespace for deployed addresses.

contract VaultManager is Ownable2Step {
    mapping(address => bool) public isManager;

    error NoAccess();

    event ContractDeployed(address deployedContract);

    constructor(address owner) Ownable(owner) {
    }

    modifier onlyManager() {
        if (msg.sender != owner() && !isManager[msg.sender]) {
            revert NoAccess();
        }
        _;
    }

    function deploy(bytes32 salt, bytes memory creationCode) external onlyManager returns (address) {
        // hash salt with the deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(msg.sender, salt));
        address contractAddress = CREATE3.deployDeterministic(creationCode, salt);

        emit ContractDeployed(contractAddress);
        return contractAddress;
    }

    function getDeployed(bytes32 salt) external view returns (address) {
        // hash salt with keythe deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(msg.sender, salt));
        return CREATE3.predictDeterministicAddress(salt);
    }

    function setManagers(address[] calldata managers, bool knob) external onlyOwner {
        for (uint256 i = 0; i < managers.length; i++) {
            // Already set the same value
            if (isManager[managers[i]] == knob) {
                continue;
            }
            isManager[managers[i]] = knob;
        }
    }
}
