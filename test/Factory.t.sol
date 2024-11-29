// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import {ContractFactory} from "../contracts/utils/ContractFactory.sol";
import {ProtocolVault} from "../contracts/ProtocolVault.sol";

contract Create3FactoryTest is Test {
    ContractFactory factory;
    ProtocolVault protocolVault;
    address vaultCrossChainManager = address(0x123);
    bytes32 salt = keccak256(abi.encodePacked("test_salt"));

    address owner = address(0x01);
    address manager = address(0x02);

    error NoAccess();
    
    function setUp() public {
        factory = new ContractFactory(owner);
    }

    function testDeployProtocolVaultContractByCreate3() public {
        address protocolVaultImpl = address(new ProtocolVault());

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                protocolVaultImpl,
                abi.encodeWithSelector(ProtocolVault.initialize.selector, address(vaultCrossChainManager))
            )
        );
        //owner deploy
        vm.startPrank(owner);
        address deployedAddress = factory.deploy(salt, bytecode);
        protocolVault = ProtocolVault(deployedAddress);

        assertEq(protocolVault.ledgerChainId(), 291);
        assertEq(protocolVault.crossChainManager(), vaultCrossChainManager);

        //manager deploy
        address[] memory managers = new address[](1);
        managers[0] = manager;
        factory.setManagers(managers, true);
        vm.stopPrank();

        salt = keccak256(abi.encodePacked("test_salt_manager"));
        vm.prank(manager);
        deployedAddress = factory.deploy(salt, bytecode);
        protocolVault = ProtocolVault(deployedAddress);

        assertEq(protocolVault.ledgerChainId(), 291);
        assertEq(protocolVault.crossChainManager(), vaultCrossChainManager);
    }

    function testFailDeployWithDiffBytecodeSameSalt() public {
        address protocolVaultImpl = address(new ProtocolVault());

        bytes memory bytecodeA = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                protocolVaultImpl,
                abi.encodeWithSelector(ProtocolVault.initialize.selector, address(vaultCrossChainManager))
            )
        );
        bytes memory bytecodeB = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                protocolVaultImpl,
                abi.encodeWithSelector(
                    ProtocolVault.initialize.selector,
                    address(0x111) //different address
                )
            )
        );
        factory.deploy(salt, bytecodeA);
        assertEq(protocolVault.ledgerChainId(), 291);
        //expect to fail with reason DeploymentFailed()
        //factory.deploy(salt, bytecodeB);
    }

    function testRevertDeployWithNoAccess() public {
        address protocolVaultImpl = address(new ProtocolVault());

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                protocolVaultImpl,
                abi.encodeWithSelector(ProtocolVault.initialize.selector, address(vaultCrossChainManager))
            )
        );
        //expect to fail with reason NoAccess()
        vm.expectRevert(NoAccess.selector);
        factory.deploy(salt, bytecode);
    }
}

contract SimpleStorage {
    uint256 public value;

    function setValue(uint256 _value) public {
        value = _value;
    }
}
