// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract VaultFactory is Ownable2Step {
    constructor(address initialOwner) Ownable(initialOwner) {}

    function createProtocolVault(address implementation, uint256 salt_) external onlyOwner {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, salt_));
        // ERC1967Proxy deployedContract = new ERC1967Proxy{salt: salt}(
        //     _implementation,
        //     "abi.encodeWithSignature("initOwner(address)", msg.sender)"
        // );
        address deployedContract;
        bytes memory deploymentBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, abi.encodeWithSignature("initOwner(address)", msg.sender))
        );
        assembly {
            deployedContract := create2(0, add(deploymentBytecode, 0x20), mload(deploymentBytecode), salt)
            if iszero(deployedContract) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function createUserVault() external onlyOwner {}
}
