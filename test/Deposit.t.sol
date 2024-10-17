pragma solidity ^0.8.24;
// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {Test} from "forge-std/Test.sol";
import {ProtocolVault} from "../contracts/ProtocolVault.sol";
import {VaultCrossChainManager} from "../contracts/VaultCrossChainManager.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {console} from "forge-std/console.sol";

// Mock ERC20 token contract
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol, decimals) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TestProtocolVault is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    ProtocolVault protocolVault;
    VaultCrossChainManager aVaultCrossChainManager;
    VaultCrossChainManager bVaultCrossChainManager;

    ERC20 mockToken;

    function setUp() public virtual override {
        // Call the base setup function from the TestHelperOz5 contract
        super.setUp();
        // Initialize 2 endpoints, using UltraLightNode as the library type
        setUpEndpoints(2, LibraryType.UltraLightNode);
        address[] memory uas = setupOApps(
            type(VaultCrossChainManager).creationCode,
            1,
            2
        );

        aVaultCrossChainManager = VaultCrossChainManager(payable(uas[0]));
        bVaultCrossChainManager = VaultCrossChainManager(payable(uas[1]));

        // Deploy the ProtocolVault contract
        address protocolVaultImpl = address(new ProtocolVault());
        address proxy = address(new ERC1967Proxy(protocolVaultImpl, abi.encodeWithSelector(ProtocolVault.initialize.selector, address(aVaultCrossChainManager))));
        protocolVault = ProtocolVault(proxy);
    }

    function testInitialize() public view {
        // Check initial state
        assertEq(protocolVault.ledgerChainId(), 291);
        assertEq(aVaultCrossChainManager.LEDGER_EID(), 1);
    }

    // function testIncrementCounter() public {
    //     // Call testIncrementCounter function
    //     vault.testIncrementCounter();

    //     // Validate the counter increment
    //     assertEq(mockCrossChainManager.counter(), 1);
    // }

    // function testDeposit() public {
    //     // Mint tokens to the test contract
    //     mockToken.mint(address(this), 1000);

    //     // Approve the vault to spend tokens
    //     mockToken.approve(address(vault), 1000);

    //     // Call deposit function
    //     vault.deposit(address(mockToken), address(this), 1000);

    //     // Validate the deposit
    //     // Add assertions to check the state changes
    // }
}
