// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// imports oz
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";

contract TestProtocolVault is Base {
    function setUp() public override {
        super.setUp();
    }

    function testInitialize() public view {
        // Check initial state
        assertEq(protocolVault.ledgerChainId(), 291);
        assertEq(
            protocolVault.crossChainManager(),
            address(aVaultCrossChainManager)
        );

        assertEq(
            svLedger.crossChainManagerAddress(),
            address(bVaultCrossChainManager)
        );

        assertEq(bVaultCrossChainManager.svLedger(), address(svLedger));

        assertEq(aVaultCrossChainManager.eid(), 1);
        assertEq(bVaultCrossChainManager.eid(), 2);
        assertEq(aVaultCrossChainManager.dstEid(), 2);
        assertEq(bVaultCrossChainManager.dstEid(), 1);
    }

    function testProtocolDeposit() public {
        uint256 nativeFee = getEstimateFee();
        // Call deposit function
        protocolVault.deposit{value: nativeFee}(
            address(mockToken),
            user,
            100e6
        );

        verifyPackets(
            ledgerEid,
            addressToBytes32(address(bVaultCrossChainManager))
        );
    }

    // function testUserVaultDeposit public {}

}
