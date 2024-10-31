// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CREATE3} from "solady/src/utils/CREATE3.sol";

/// @title Factory for deploying contracts to deterministic addresses via CREATE3
/// @author zefram.eth, SKYBIT
/// @notice Enables deploying contracts using CREATE3. Each deployer (msg.sender) has
/// its own namespace for deployed addresses.
contract ContractFactory {
    function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address) {
        // hash salt with the deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(msg.sender, salt));
        return CREATE3.deployDeterministic(creationCode, salt);
    }

    function getDeployed(bytes32 salt) external view returns (address) {
        // hash salt with the deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(msg.sender, salt));
        return CREATE3.predictDeterministicAddress(salt);
    }

    function deployByCreate2(bytes32 salt, bytes memory creationCode) external returns (address) {
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        address deployedContract;

        assembly {
            deployedContract := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
            if iszero(deployedContract) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        return deployedContract;
    }
}
