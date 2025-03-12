// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolVaultHandler} from "./ProtocolVaultHandler.sol";

contract VaultOperationInvariants is Test {
    ProtocolVaultHandler public handler;

    function setUp() public {
        handler = new ProtocolVaultHandler();

        // Target the handler contract
        targetContract(address(handler));

        // Fund accounts with tokens and ETH for fees
        // handler.mockToken().mint(address(this), 1000000 * 1e6);
        // handler.mockToken().mint(handler.sp(), 1000000 * 1e6);
        vm.deal(address(this), 100 ether);
        vm.deal(handler.sp(), 100 ether);
    }

    function invariant_VaultBalance() public view {
        // Vault's actual token balance should equal net deposits tracked by ghost variables
        assertEq(handler.getVaultBalance(), handler.getGhostNetDeposits(), "Vault balance mismatch");
    }

    function invariant_DepositWithdrawLimits() public view {
        // Total withdrawals should never exceed total deposits
        assertLe(handler.ghostTotalWithdraws(), handler.ghostTotalDeposits(), "Withdrawals exceeded deposits");
    }
}
