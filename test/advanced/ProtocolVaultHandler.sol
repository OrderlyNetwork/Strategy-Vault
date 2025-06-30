// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Base} from "../Base.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VaultType, DepositParams, WithdrawParams} from "../../contracts/lib/types/VaultStruct.sol";
import {PayloadType} from "../../contracts/lib/types/CrossChainStruct.sol";

contract ProtocolVaultHandler is Base {
    // Ghost variables to track total deposits and withdrawals
    uint256 public ghostTotalDeposits;
    uint256 public ghostTotalWithdraws;
    uint256 public minDepositForLp;
    uint256 public minDepositForSp;

    constructor() {
        super.setUp(); // Setup base contract
    }

    function lpDeposit(uint256 amount) public {
        // Bound the input to reasonable values
        amount = bound(amount, minDepositForLp, 1000000 * 1e6); // Between min deposit and 1M USDC

        // Prepare deposit params1
        DepositParams memory params = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: msg.sender,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        // Get required fee
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, msg.sender, amount);

        // Approve tokens
        vm.startPrank(msg.sender);
        mockToken.approve(address(protocolVault), amount);

        // Execute deposit
        protocolVault.deposit{value: nativeFee}(params);
        vm.stopPrank();

        // Update ghost variable
        ghostTotalDeposits += amount;
    }

    function spDeposit(uint256 amount) public {
        // Bound the input to reasonable values
        amount = bound(amount, minDepositForSp, 1000000 * 1e6); // Between min deposit and 1M USDC

        // Prepare deposit params
        DepositParams memory params = DepositParams({
            payloadType: PayloadType.SP_DEPOSIT,
            receiver: sp,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        // Get required fee
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.SP_DEPOSIT, sp, amount);

        // Approve tokens
        vm.startPrank(sp);
        mockToken.approve(address(protocolVault), amount);

        // Execute deposit
        protocolVault.deposit{value: nativeFee}(params);
        vm.stopPrank();

        // Update ghost variable
        ghostTotalDeposits += amount;
    }

    function lpWithdraw(uint256 amount) public {
        // Bound the input
        amount = bound(amount, 1e6, ghostTotalDeposits); // Cannot withdraw more than total deposits

        // Prepare withdraw params
        WithdrawParams memory params = WithdrawParams({
            payloadType: PayloadType.LP_WITHDRAW,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        // Get required fee
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_WITHDRAW, msg.sender, amount);

        // Execute withdraw
        vm.prank(msg.sender);
        protocolVault.withdraw{value: nativeFee}(params);

        // Update ghost variable
        ghostTotalWithdraws += amount;
    }

    function spWithdraw(uint256 amount) public {
        // Bound the input
        amount = bound(amount, 1e6, ghostTotalDeposits); // Cannot withdraw more than total deposits

        // Prepare withdraw params
        WithdrawParams memory params = WithdrawParams({
            payloadType: PayloadType.SP_WITHDRAW,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        // Get required fee
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.SP_WITHDRAW, sp, amount);

        // Execute withdraw
        vm.prank(sp);
        protocolVault.withdraw{value: nativeFee}(params);

        // Update ghost variable
        ghostTotalWithdraws += amount;
    }

    // Helper functions
    function getVaultBalance() public view returns (uint256) {
        return mockToken.balanceOf(address(protocolVault));
    }

    function getGhostNetDeposits() public view returns (uint256) {
        return ghostTotalDeposits - ghostTotalWithdraws;
    }
}
