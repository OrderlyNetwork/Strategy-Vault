// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "../Base.sol";
import {ProtocolVault} from "../../contracts/ProtocolVault.sol";
import {
    VaultType,
    VaultState,
    RoleType,
    ClaimParams,
    DepositParams,
    WithdrawParams,
    OperationData,
    UserClaimedInfo
} from "../../contracts/lib/types/VaultStruct.sol";
import {PayloadType} from "../../contracts/lib/types/CrossChainStruct.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

contract ProtocolVaultFuzzTest is Base {
    error NotEnoughUnclaimedAssets(uint256 amount);
    error VaultClosed();

    function setUp() public override {
        super.setUp();
    }

    // Fuzz test for LP deposit function with varying amounts
    function testFuzz_LpDeposit(uint256 amount) public {
        // Bound the amount to a reasonable range
        amount = bound(amount, 1e6, 1000e6);

        vm.startPrank(user);

        // Approve tokens for the specific amount
        mockToken.approve(address(protocolVault), amount);

        // Record balances before deposit
        uint256 userBalanceBefore = mockToken.balanceOf(user);
        uint256 vaultBalanceBefore = mockToken.balanceOf(address(protocolVault));

        // Calculate estimated fee
        uint256 estimatedFee = getEstimateFee(PayloadType.LP_DEPOSIT);

        // Perform LP deposit
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        protocolVault.deposit{value: estimatedFee}(depositParams);

        // Verify balances after deposit
        assertEq(mockToken.balanceOf(user), userBalanceBefore - amount, "User balance did not decrease correctly");
        assertEq(
            mockToken.balanceOf(address(protocolVault)),
            vaultBalanceBefore + amount,
            "Vault balance did not increase correctly"
        );

        // Verify cross-chain message was sent
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Check ledger state
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        (
            , // shares
            uint256 unAllocatedAssets,
            , // frozenShares
                // pendingShares
        ) = svLedger.accountTokenInfo(accountId, USDC_HASH);
        assertEq(unAllocatedAssets, amount);

        vm.stopPrank();
    }

    // Fuzz test for SP deposit function with varying amounts
    function testFuzz_SpDeposit(uint256 amount) public {
        // Bound the amount to a reasonable range
        amount = bound(amount, 1e6, 1000e6);

        // Set SP as allowed strategy provider
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        vm.prank(owner);
        protocolVault.setAllowedStrategyProvider(spId, true);

        vm.startPrank(sp);

        // Approve tokens for the specific amount
        mockToken.approve(address(protocolVault), amount);

        // Record balances before deposit
        uint256 userBalanceBefore = mockToken.balanceOf(sp);
        uint256 vaultBalanceBefore = mockToken.balanceOf(address(protocolVault));

        // Calculate estimated fee
        uint256 estimatedFee = getEstimateFee(PayloadType.SP_DEPOSIT);

        // Perform SP deposit
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.SP_DEPOSIT,
            receiver: sp,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        protocolVault.deposit{value: estimatedFee}(depositParams);

        // Verify balances after deposit
        assertEq(mockToken.balanceOf(sp), userBalanceBefore - amount, "SP balance did not decrease correctly");
        assertEq(
            mockToken.balanceOf(address(protocolVault)),
            vaultBalanceBefore + amount,
            "Vault balance did not increase correctly"
        );

        // Verify cross-chain message was sent
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Check strategy fund
        assertEq(protocolVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), amount);

        vm.stopPrank();
    }

    // Fuzz test for LP withdraw function with varying amounts
    function testFuzz_LpWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound the amounts to reasonable ranges
        depositAmount = bound(depositAmount, 10e6, 1000e6);
        withdrawAmount = bound(withdrawAmount, 1e6, depositAmount);

        // First perform a deposit
        vm.startPrank(user);
        mockToken.approve(address(protocolVault), depositAmount);

        uint256 depositFee = getEstimateFee(PayloadType.LP_DEPOSIT);
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: depositAmount,
            brokerHash: ORDERLY_BROKER
        });

        protocolVault.deposit{value: depositFee}(depositParams);

        // Verify cross-chain message was sent
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Setup shares on the ledger for the user
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = accountId;
        svLedger.setAccountPendingShares(accountIds, depositAmount);

        // Now perform a withdrawal
        uint256 withdrawFee = getEstimateFee(PayloadType.LP_WITHDRAW);
        WithdrawParams memory withdrawParams = WithdrawParams({
            payloadType: PayloadType.LP_WITHDRAW,
            token: address(mockToken),
            amount: withdrawAmount,
            brokerHash: ORDERLY_BROKER
        });

        protocolVault.withdraw{value: withdrawFee}(withdrawParams);

        // Verify withdrawal cross-chain message was sent
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Check ledger state for frozen shares
        (
            , // shares
            ,
            uint256 frozenShares, // frozenShares
                // pendingShares
        ) = svLedger.accountTokenInfo(accountId, USDC_HASH);
        assertEq(frozenShares, withdrawAmount);

        vm.stopPrank();
    }

    // Fuzz test for SP withdraw function with varying amounts
    function testFuzz_SpWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound the amounts to reasonable ranges
        depositAmount = bound(depositAmount, 10e6, 1000e6);
        withdrawAmount = bound(withdrawAmount, 1e6, depositAmount);

        // Set SP as allowed strategy provider
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        vm.prank(owner);
        protocolVault.setAllowedStrategyProvider(spId, true);

        // First perform a deposit
        vm.startPrank(sp);
        mockToken.approve(address(protocolVault), depositAmount);

        uint256 depositFee = getEstimateFee(PayloadType.SP_DEPOSIT);
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.SP_DEPOSIT,
            receiver: sp,
            token: address(mockToken),
            amount: depositAmount,
            brokerHash: ORDERLY_BROKER
        });

        protocolVault.deposit{value: depositFee}(depositParams);

        // Verify cross-chain message was sent
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Setup shares on the ledger for the SP
        bytes32[] memory spIds = new bytes32[](1);
        spIds[0] = spId;
        svLedger.setSpPendingShares(spIds, depositAmount);

        // Now perform a withdrawal
        uint256 withdrawFee = getEstimateFee(PayloadType.SP_WITHDRAW);
        WithdrawParams memory withdrawParams = WithdrawParams({
            payloadType: PayloadType.SP_WITHDRAW,
            token: address(mockToken),
            amount: withdrawAmount,
            brokerHash: ORDERLY_BROKER
        });

        protocolVault.withdraw{value: withdrawFee}(withdrawParams);

        // Verify withdrawal cross-chain message was sent
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        vm.stopPrank();
    }

    // Fuzz test for admin functions
    function testFuzz_AdminFunctions(address newAdmin, bool permission) public {
        // Exclude invalid addresses
        vm.assume(newAdmin != address(0));
        vm.assume(newAdmin != owner);

        vm.startPrank(owner);

        // Set admin permissions
        protocolVault.setAdmin(newAdmin, permission);

        // Verify the permission was set correctly
        assertEq(protocolVault.isAllowedAdmin(newAdmin), permission, "Admin permission not set correctly");

        vm.stopPrank();

        // Test access control based on the permission
        vm.startPrank(newAdmin);
        if (permission) {
            // Should be able to call admin functions
            protocolVault.emergencyPause();
            assertTrue(protocolVault.paused(), "Contract should be paused");
        } else {
            // Should not be able to call admin functions
            vm.expectRevert();
            protocolVault.emergencyPause();
        }
        vm.stopPrank();
    }

    // Fuzz test for cross-chain fee validation
    function testFuzz_CrossChainFeeValidation(uint256 amount, uint256 feeMultiplier) public {
        // Bound the amount and fee multiplier to reasonable ranges
        amount = bound(amount, 1e6, 100e6);
        // Bound the fee multiplier (0.5x to 2x of estimated fee)
        feeMultiplier = bound(feeMultiplier, 50, 200);

        vm.startPrank(user);

        // Approve tokens
        mockToken.approve(address(protocolVault), amount);

        // Calculate estimated fee
        uint256 estimatedFee = getEstimateFee(PayloadType.LP_DEPOSIT);
        uint256 providedFee = (estimatedFee * feeMultiplier) / 100;

        // Prepare deposit params
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        // If provided fee is less than required, expect revert
        if (providedFee < estimatedFee) {
            vm.expectRevert();
            protocolVault.deposit{value: providedFee}(depositParams);
        } else {
            // Otherwise deposit should succeed
            protocolVault.deposit{value: providedFee}(depositParams);

            // Verify cross-chain message was sent
            verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        }

        vm.stopPrank();
    }

    // Fuzz test for pause/unpause functionality
    function testFuzz_PauseUnpause(bool shouldPause) public {
        vm.startPrank(owner);

        if (shouldPause) {
            protocolVault.emergencyPause();
            assertTrue(protocolVault.paused(), "Contract should be paused");

            // Try to deposit while paused - should revert
            vm.stopPrank();
            vm.startPrank(user);

            DepositParams memory depositParams = DepositParams({
                payloadType: PayloadType.LP_DEPOSIT,
                receiver: user,
                token: address(mockToken),
                amount: 1e6,
                brokerHash: ORDERLY_BROKER
            });

            vm.expectRevert();
            protocolVault.deposit{value: 1 ether}(depositParams);
        } else {
            if (protocolVault.paused()) {
                protocolVault.emergencyUnpause();
            }
            assertFalse(protocolVault.paused(), "Contract should not be paused");

            // Try to deposit while not paused - should work
            vm.stopPrank();
            vm.startPrank(user);

            uint256 depositFee = getEstimateFee(PayloadType.LP_DEPOSIT);
            mockToken.approve(address(protocolVault), 1e6);

            DepositParams memory depositParams = DepositParams({
                payloadType: PayloadType.LP_DEPOSIT,
                receiver: user,
                token: address(mockToken),
                amount: 1e6,
                brokerHash: ORDERLY_BROKER
            });

            protocolVault.deposit{value: depositFee}(depositParams);

            // Verify cross-chain message was sent
            verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        }

        vm.stopPrank();
    }

    // Fuzz test for vault state changes
    function testFuzz_VaultState() public {
        vm.startPrank(owner);

        // Close the vault
        protocolVault.setVaultState(VaultState.CLOSED);

        vm.stopPrank();

        // Try to deposit to a closed vault - should revert
        vm.startPrank(user);
        mockToken.approve(address(protocolVault), 1e6);

        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: 1e6,
            brokerHash: ORDERLY_BROKER
        });

        vm.expectRevert(VaultClosed.selector);
        protocolVault.deposit{value: 1 ether}(depositParams);

        vm.stopPrank();
    }

    // Fuzz test for multiple LP concurrent deposits
    function testFuzz_MultiLpConcurrentDeposits(uint256[5] memory amounts) public {
        // Create multiple LP users
        address[] memory lpUsers = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            lpUsers[i] = makeAddr(string(abi.encodePacked("lpUser", i)));
            vm.deal(lpUsers[i], 10 ether); // Give each user ETH for gas
            mockToken.mint(lpUsers[i], 1000e6); // Mint tokens to each user
        }

        // Bound the deposit amounts to reasonable ranges
        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = bound(amounts[i], 1e6, 50e6);
        }

        // Track initial balances
        uint256 initialVaultBalance = mockToken.balanceOf(address(protocolVault));
        uint256 totalDeposited = 0;

        // Simulate multiple LP users depositing concurrently
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(lpUsers[i]);

            // Approve tokens for spending
            mockToken.approve(address(protocolVault), amounts[i]);

            // Record user's initial balance
            uint256 userBalanceBefore = mockToken.balanceOf(lpUsers[i]);

            // Calculate cross-chain fee
            uint256 depositFee = getEstimateFee(PayloadType.LP_DEPOSIT);

            // Create deposit parameters
            DepositParams memory depositParams = DepositParams({
                payloadType: PayloadType.LP_DEPOSIT,
                receiver: lpUsers[i],
                token: address(mockToken),
                amount: amounts[i],
                brokerHash: ORDERLY_BROKER
            });

            // Execute the deposit
            protocolVault.deposit{value: depositFee}(depositParams);

            // Verify user balance decreased correctly
            assertEq(
                mockToken.balanceOf(lpUsers[i]), userBalanceBefore - amounts[i], "User balance not updated correctly"
            );

            // Add to total deposited amount
            totalDeposited += amounts[i];

            vm.stopPrank();
        }

        // Verify cross-chain messages were sent
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Verify vault received all deposits
        assertEq(
            mockToken.balanceOf(address(protocolVault)),
            initialVaultBalance + totalDeposited,
            "Vault balance didn't increase by total deposit amount"
        );

        // Check ledger state for each LP's deposit
        for (uint256 i = 0; i < 5; i++) {
            bytes32 accountId = _getAccountId(lpUsers[i], ORDERLY_BROKER);
            (
                , // shares
                uint256 unAllocatedAssets,
                , // frozenShares
                    // pendingShares
            ) = svLedger.accountTokenInfo(accountId, USDC_HASH);

            // Verify unallocated assets match the deposit amount
            assertEq(unAllocatedAssets, amounts[i], "Unallocated assets don't match deposit amount");
        }
    }
}
