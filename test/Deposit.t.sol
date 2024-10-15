pragma solidity ^0.8.24;
// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

pragma experimental ABIEncoderV2;

import {Test} from "forge-std/Test.sol";
import {StrategyVault} from "../contracts/ProtocolVault.sol";
import {IVaultCrossChainManager} from "../contracts/interfaces/IVaultCrossChainManager.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract TestStrategyVault is Test {
    StrategyVault vault;
    IVaultCrossChainManager mockCrossChainManager;
    ERC20 mockToken;

    function setUp() public {
        // Deploy the StrategyVault contract
        vault = new StrategyVault();
        vault.initialize();

        // Deploy a mock IVaultCrossChainManager contract
        mockCrossChainManager = IVaultCrossChainManager(address(new MockCrossChainManager()));
        vault.setCrossChainManagerAddress(address(mockCrossChainManager));

        // Deploy a mock ERC20 token
        mockToken = new MockERC20("Mock Token", "MTK", 18);
    }

    function testInitialize() public {
        // Check initial state
        assertEq(vault.ledgerChainId(), 291);
    }

    function testIncrementCounter() public {
        // Call testIncrementCounter function
        vault.testIncrementCounter();

        // Validate the counter increment
        assertEq(mockCrossChainManager.counter(), 1);
    }

    function testDeposit() public {
        // Mint tokens to the test contract
        mockToken.mint(address(this), 1000);

        // Approve the vault to spend tokens
        mockToken.approve(address(vault), 1000);

        // Call deposit function
        vault.deposit(address(mockToken), address(this), 1000);

        // Validate the deposit
        // Add assertions to check the state changes
    }
}

// Mock IVaultCrossChainManager contract
contract MockCrossChainManager is IVaultCrossChainManager {
    uint256 public counter;

    function testCounter() external override {
        counter++;
    }
}

// Mock ERC20 token contract
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals)
        ERC20(name, symbol, decimals)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}