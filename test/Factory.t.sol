// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "forge-std/Test.sol";
import {VaultFactory} from "../contracts/VaultFactory.sol";
import {ProtocolVault} from "../contracts/ProtocolVault.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Create3FactoryTest is Test {
    VaultFactory factory;
    ProtocolVault protocolVault;
    MockERC20 mockToken;

    address vaultCrossChainManager = address(0x123);
    address dexVault = address(0x456);

    bytes32 salt = keccak256(abi.encodePacked("test_salt"));

    address owner = address(0x01);
    address manager = address(0x02);

    error NoAccess();

    function setUp() public {
        factory = new VaultFactory(owner);
    }

    function testDeployProtocolVaultContractByCreate3() public {
        address protocolVaultImpl = address(new ProtocolVault());

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                protocolVaultImpl,
                abi.encodeWithSelector(ProtocolVault.initialize.selector, dexVault, owner, address(mockToken), 0, 0)
            )
        );
        //owner deploy
        vm.startPrank(owner);
        address deployedAddress = factory.deploy(salt, bytecode);
        protocolVault = ProtocolVault(payable(deployedAddress));
        protocolVault.setCrossChainManager(vaultCrossChainManager);

        assertEq(factory.getDeployed(salt), deployedAddress);
        assertEq(protocolVault.crossChainManager(), vaultCrossChainManager);
        assertEq(protocolVault.owner(), owner);
        assertEq(protocolVault.isAllowedToken(address(mockToken)), true);

        //manager deploy
        address[] memory managers = new address[](1);
        managers[0] = manager;
        factory.setManagers(managers, true);
        vm.stopPrank();

        salt = keccak256(abi.encodePacked("test_salt_manager"));
        vm.prank(manager);
        deployedAddress = factory.deploy(salt, bytecode);
        protocolVault = ProtocolVault(payable(deployedAddress));
        vm.prank(owner);

        protocolVault.setCrossChainManager(vaultCrossChainManager);
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
        //expect to fail with reason DeploymentFailed()
        factory.deploy(salt, bytecodeB);
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

    function testGetSalt() public pure {
        (bytes32 salt1, bytes32 salt2) = _getSalt();
        console.logBytes32(salt1);
        console.logBytes32(salt2);
    }

    function _getSalt() public pure returns (bytes32, bytes32) {
        return (keccak256(abi.encodePacked("ProtocolVault")), keccak256(abi.encodePacked("CrossChainManager")));
    }
}

contract SimpleStorage {
    uint256 public value;

    function setValue(uint256 _value) public {
        value = _value;
    }
}
