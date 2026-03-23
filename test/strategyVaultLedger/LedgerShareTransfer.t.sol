// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "../Base.sol";
import {console} from "forge-std/console.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {PayloadType} from "../../contracts/lib/types/CrossChainStruct.sol";
import {OperationData, VaultType, VaultState, DepositParams} from "../../contracts/lib/types/VaultStruct.sol";
import {ShareTransferRequest, ShareTransferResult, AccountToken} from "../../contracts/lib/types/LedgerStruct.sol";
import {ILedgerExtension} from "../../contracts/interfaces/ILedgerExtension.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title LedgerShareTransfer Test
/// @notice Complete test suite for inner share transfer functionality
contract LedgerShareTransferTest is Base {
    uint256 public constant INITIAL_SHARES = 1000e6;
    uint256 public constant TRANSFER_AMOUNT = 100e6;

    /// @notice Set up test environment
    function setUp() public override {
        super.setUp();

        // Add users to whitelist
        vm.startPrank(owner);
        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userB;
        users[2] = spA;
        protocolVault.updateInnerTransferWhitelist(users, true);
        vm.stopPrank();

        // Directly set userA's initial shares on ledger (simulate completed deposit)
        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userA_id, USDC_HASH, INITIAL_SHARES, INITIAL_SHARES, 0);
    }

    /// @notice Test complete share transfer flow
    function testShareTransferFlow() public {
        // 1. UserA initiates transfer to UserB
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);

        // 2. Verify cross-chain message
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // 3. Verify ShareTransferRequested event was emitted
        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);
        // Verify request is stored
        ShareTransferRequest memory request = _getShareTransferRequest(requestId);
        assertEq(request.fromAccountId, userA_id, "From account ID should match");
        assertEq(request.toAccountId, userB_id, "To account ID should match");
        assertEq(request.amount, TRANSFER_AMOUNT, "Transfer amount should match");
        assertEq(request.vaultId, vaultId, "Vault ID should match");
        assertFalse(request.executed, "Request should not be executed yet");

        // 4. Check balances before execution
        AccountToken memory fromAccountBefore = svLedger.getAccountToken(vaultId, userA_id);
        AccountToken memory toAccountBefore = svLedger.getAccountToken(vaultId, userB_id);
        uint256 fromSharesBefore = fromAccountBefore.shares;
        uint256 toSharesBefore = toAccountBefore.shares;
        assertEq(fromSharesBefore, INITIAL_SHARES, "UserA should have initial shares");
        assertEq(toSharesBefore, 0, "UserB should have zero shares");

        // 5. Backend executes transfer
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        vm.prank(operator);
        svLedger.executeShareTransfer(requestIds, signature);

        // 6. Verify final balances
        AccountToken memory fromAccountAfter = svLedger.getAccountToken(vaultId, userA_id);
        AccountToken memory toAccountAfter = svLedger.getAccountToken(vaultId, userB_id);
        uint256 fromSharesAfter = fromAccountAfter.shares;
        uint256 fromPendingAfter = fromAccountAfter.pendingShares;
        uint256 toSharesAfter = toAccountAfter.shares;
        uint256 toPendingAfter = toAccountAfter.pendingShares;
        
        assertEq(fromSharesAfter, INITIAL_SHARES - TRANSFER_AMOUNT, "UserA shares should decrease");
        assertEq(fromPendingAfter, INITIAL_SHARES - TRANSFER_AMOUNT, "UserA pending shares should decrease");
        assertEq(toSharesAfter, TRANSFER_AMOUNT, "UserB shares should increase");
        assertEq(toPendingAfter, TRANSFER_AMOUNT, "UserB pending shares should increase");

        // 7. Verify request is marked as executed
        request = _getShareTransferRequest(requestId);
        assertTrue(request.executed, "Request should be marked as executed");
    }

    /// @notice Test batch transfer execution
    function testBatchShareTransfer() public {
        // Setup: UserA initiates two transfers
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        
        // Transfer 1: UserA -> UserB
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        bytes32 requestId1 = _calculateRequestId(31337, 0, vaultId);

        // Transfer 2: UserA -> spA
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(spA, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        bytes32 requestId2 = _calculateRequestId(31337, 1, vaultId);

        // Keep UserA's initial shares for batch execution (executeShareTransfer will deduct)

        // Execute batch
        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;
        bytes memory signature = _getShareTransferSignature(requestIds);

        vm.prank(operator);
        svLedger.executeShareTransfer(requestIds, signature);

        // Verify all balances
        bytes32 spAAccountId = _getAccountId(spA, ORDERLY_BROKER);
        uint256 userAShares = svLedger.getAccountToken(vaultId, userA_id).shares;
        uint256 userBShares = svLedger.getAccountToken(vaultId, userB_id).shares;
        uint256 spAShares = svLedger.getAccountToken(vaultId, spAAccountId).shares;

        assertEq(userAShares, INITIAL_SHARES - 2 * TRANSFER_AMOUNT, "UserA should have transferred twice");
        assertEq(userBShares, TRANSFER_AMOUNT, "UserB should have received once");
        assertEq(spAShares, TRANSFER_AMOUNT, "SpA should have received once");

        // Verify both requests are executed
        assertTrue(_getShareTransferRequest(requestId1).executed, "Request 1 should be executed");
        assertTrue(_getShareTransferRequest(requestId2).executed, "Request 2 should be executed");
    }

    /// @notice Test revert when not in whitelist
    function testRevertNotInWhitelist() public {
        address notWhitelisted = address(0xbad);
        vm.deal(notWhitelisted, 100 ether);
        mockToken.mint(notWhitelisted, 1000e6);
        
        vm.startPrank(notWhitelisted);
        mockToken.approve(address(protocolVault), 1000e6);
        
        vm.expectRevert(abi.encodeWithSignature("NotInInnerTransferWhitelist()"));
        protocolVault.transferShare{value: 0.01 ether}(userB, 100e6, ORDERLY_BROKER);
        vm.stopPrank();
    }

    /// @notice Test revert on self transfer
    function testRevertSelfTransfer() public {
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userA, TRANSFER_AMOUNT);
        
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSignature("InvalidReceiver()"));
        protocolVault.transferShare{value: transferFee}(userA, TRANSFER_AMOUNT, ORDERLY_BROKER);
        vm.stopPrank();
    }

    /// @notice Test revert on invalid receiver
    function testRevertInvalidReceiver() public {
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, address(0), TRANSFER_AMOUNT);
        
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSignature("InvalidReceiver()"));
        protocolVault.transferShare{value: transferFee}(address(0), TRANSFER_AMOUNT, ORDERLY_BROKER);
        vm.stopPrank();
    }

    /// @notice Test revert on zero amount
    function testRevertZeroAmount() public {
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, 0);
        
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        protocolVault.transferShare{value: transferFee}(userB, 0, ORDERLY_BROKER);
        vm.stopPrank();
    }

    /// @notice Test revert when executing already executed request
    function testRevertAlreadyExecuted() public {
        // Setup and execute first time
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        vm.prank(operator);
        svLedger.executeShareTransfer(requestIds, signature);

        // Try to execute again
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("AlreadyExecuted()"));
        svLedger.executeShareTransfer(requestIds, signature);
    }

    /// @notice Test revert when account not finalized
    function testRevertAccountNotFinalized() public {
        // Initiate transfer
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);

        // Manually set account to non-finalized state (shares != pendingShares)
        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userA_id, USDC_HASH, INITIAL_SHARES, INITIAL_SHARES + 1, 0);

        // Try to execute
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("AccountNotFinalized()"));
        svLedger.executeShareTransfer(requestIds, signature);
    }

    /// @notice Test revert when insufficient available shares
    function testRevertInsufficientAvailableShares() public {
        // Initiate transfer
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);

        // Set frozen shares to make available shares insufficient
        // frozenShares + amount > shares, so transfer should fail
        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userA_id, USDC_HASH, INITIAL_SHARES, INITIAL_SHARES, INITIAL_SHARES - TRANSFER_AMOUNT + 1);

        // Try to execute
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("InsufficientAvailableShares()"));
        svLedger.executeShareTransfer(requestIds, signature);
    }

    /// @notice Test batch revert on any failure
    function testBatchRevertOnAnyFailure() public {
        // Setup two transfers
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        bytes32 requestId1 = _calculateRequestId(31337, 0, vaultId);

        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userA_id, USDC_HASH, INITIAL_SHARES - TRANSFER_AMOUNT, INITIAL_SHARES - TRANSFER_AMOUNT, 0);

        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(spA, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        bytes32 requestId2 = _calculateRequestId(31337, 1, vaultId);

        // Execute first request separately to mark it as executed
        bytes32[] memory singleRequest = new bytes32[](1);
        singleRequest[0] = requestId1;
        bytes memory singleSignature = _getShareTransferSignature(singleRequest);
        
        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userA_id, USDC_HASH, INITIAL_SHARES - 2 * TRANSFER_AMOUNT, INITIAL_SHARES - 2 * TRANSFER_AMOUNT, 0);
        
        vm.prank(operator);
        svLedger.executeShareTransfer(singleRequest, singleSignature);

        // Try batch execution with first request already executed
        bytes32[] memory batchRequests = new bytes32[](2);
        batchRequests[0] = requestId1;
        batchRequests[1] = requestId2;
        bytes memory batchSignature = _getShareTransferSignature(batchRequests);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("AlreadyExecuted()"));
        svLedger.executeShareTransfer(batchRequests, batchSignature);

        // Verify second request was NOT executed due to atomic revert
        assertFalse(_getShareTransferRequest(requestId2).executed, "Request 2 should not be executed");
    }
    
    /// @notice Test whitelist management
    function testWhitelistManagement() public {
        address newUser = address(0xc1);
        
        // Verify not whitelisted
        assertFalse(protocolVault.innerTransferWhitelist(newUser), "Should not be whitelisted");
        
        // Add to whitelist
        vm.startPrank(owner);
        address[] memory users = new address[](1);
        users[0] = newUser;
        
        vm.expectEmit(false, false, false, true);
        emit InnerTransferWhitelistUpdated(users, true);
        protocolVault.updateInnerTransferWhitelist(users, true);
        vm.stopPrank();
        
        assertTrue(protocolVault.innerTransferWhitelist(newUser), "Should be whitelisted");
        
        // Remove from whitelist
        vm.startPrank(owner);
        vm.expectEmit(false, false, false, true);
        emit InnerTransferWhitelistUpdated(users, false);
        protocolVault.updateInnerTransferWhitelist(users, false);
        vm.stopPrank();
        
        assertFalse(protocolVault.innerTransferWhitelist(newUser), "Should be removed from whitelist");
    }

    // ==================== Category C: Boundary and Edge Case Tests ====================

    /// @notice Test transfer with frozen shares (but sufficient available shares)
    function testTransferWithFrozenShares() public {
        // Setup: UserA has 1000 shares, 200 frozen, 800 available
        uint256 frozenAmount = 200e6;
        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userA_id, USDC_HASH, INITIAL_SHARES, INITIAL_SHARES, frozenAmount);

        // Transfer 100 (within available 800)
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        // Execute transfer
        vm.prank(operator);
        svLedger.executeShareTransfer(requestIds, signature);

        // Verify balances
        AccountToken memory fromAccount = svLedger.getAccountToken(vaultId, userA_id);
        AccountToken memory toAccount = svLedger.getAccountToken(vaultId, userB_id);
        
        assertEq(fromAccount.shares, INITIAL_SHARES - TRANSFER_AMOUNT, "UserA total shares should decrease");
        assertEq(fromAccount.frozenShares, frozenAmount, "UserA frozen shares should remain unchanged");
        assertEq(fromAccount.shares - fromAccount.frozenShares, INITIAL_SHARES - TRANSFER_AMOUNT - frozenAmount, 
            "UserA available shares should be correct");
        assertEq(toAccount.shares, TRANSFER_AMOUNT, "UserB should receive transferred shares");
    }

    /// @notice Test transferring all available shares (boundary case)
    function testTransferAllAvailableShares() public {
        // Setup: UserA has 1000 shares, 300 frozen, 700 available
        uint256 frozenAmount = 300e6;
        uint256 availableShares = INITIAL_SHARES - frozenAmount;
        
        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userA_id, USDC_HASH, INITIAL_SHARES, INITIAL_SHARES, frozenAmount);

        // Transfer all 700 available shares
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, availableShares);
        
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, availableShares, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        // Execute transfer
        vm.prank(operator);
        svLedger.executeShareTransfer(requestIds, signature);

        // Verify balances
        AccountToken memory fromAccount = svLedger.getAccountToken(vaultId, userA_id);
        AccountToken memory toAccount = svLedger.getAccountToken(vaultId, userB_id);
        
        assertEq(fromAccount.shares, frozenAmount, "UserA should only have frozen shares left");
        assertEq(fromAccount.pendingShares, frozenAmount, "UserA pending shares should match");
        assertEq(fromAccount.frozenShares, frozenAmount, "UserA frozen shares unchanged");
        assertEq(fromAccount.shares - fromAccount.frozenShares, 0, "UserA should have zero available shares");
        assertEq(toAccount.shares, availableShares, "UserB should receive all available shares");
        assertEq(toAccount.pendingShares, availableShares, "UserB pending shares should match");
    }

    /// @notice Test transfer to account that already has shares
    function testTransferToExistingAccount() public {
        // Setup: UserB already has 500 shares
        uint256 userBInitialShares = 500e6;
        vm.prank(operator);
        svLedger.mockSetAccountShares(vaultId, userB_id, USDC_HASH, userBInitialShares, userBInitialShares, 0);

        // Transfer 100 from UserA to UserB
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        // Execute transfer
        vm.prank(operator);
        svLedger.executeShareTransfer(requestIds, signature);

        // Verify balances
        AccountToken memory fromAccount = svLedger.getAccountToken(vaultId, userA_id);
        AccountToken memory toAccount = svLedger.getAccountToken(vaultId, userB_id);
        
        assertEq(fromAccount.shares, INITIAL_SHARES - TRANSFER_AMOUNT, "UserA shares should decrease");
        assertEq(fromAccount.pendingShares, INITIAL_SHARES - TRANSFER_AMOUNT, "UserA pending shares should match");
        assertEq(toAccount.shares, userBInitialShares + TRANSFER_AMOUNT, "UserB shares should accumulate");
        assertEq(toAccount.pendingShares, userBInitialShares + TRANSFER_AMOUNT, "UserB pending shares should accumulate");
        
        // Verify the accumulated amount is correct
        assertEq(toAccount.shares - userBInitialShares, TRANSFER_AMOUNT, "Increment should match transfer amount");
    }

    // ==================== Category A: Vault Layer Tests ====================

    /// @notice Test revert when broker not allowed
    function testRevertBrokerNotAllowed() public {
        bytes32 invalidBroker = keccak256("INVALID_BROKER");
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSignature("BrokerNotAllowed(bytes32)", invalidBroker));
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, invalidBroker);
        vm.stopPrank();
    }

    /// @notice Test revert when vault is closed
    function testRevertVaultClosed() public {
        // Close the vault
        vm.prank(owner);
        protocolVault.setVaultState(VaultState.CLOSED);
        
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSignature("VaultClosed()"));
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        vm.stopPrank();
    }

    /// @notice Test revert when insufficient cross-chain fee provided
    function testRevertInsufficientCrosschainFee() public {
        uint256 requiredFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        uint256 insufficientFee = requiredFee - 1;
        
        vm.startPrank(userA);
        // LayerZero will revert with NotEnoughNative error
        vm.expectRevert();
        protocolVault.transferShare{value: insufficientFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        vm.stopPrank();
    }

    // ==================== Category B: Ledger Layer Tests ====================

    /// @notice Test revert when request does not exist
    function testRevertRequestNotFound() public {
        // Create a fake requestId that was never created
        bytes32 fakeRequestId = keccak256("FAKE_REQUEST");
        
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = fakeRequestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        // Execute should revert with RequestNotFound
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("RequestNotFound()"));
        svLedger.executeShareTransfer(requestIds, signature);
    }

    /// @notice Test revert when signature is invalid
    function testRevertInvalidSignature() public {
        // Setup: UserA initiates transfer
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        // Create signature with wrong private key
        uint256 wrongPrivateKey = 0x9999;
        bytes32 messageHash = keccak256(abi.encode(requestIds));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        svLedger.executeShareTransfer(requestIds, invalidSignature);
    }

    /// @notice Test revert when non-operator tries to execute
    function testRevertNonOperatorExecution() public {
        // Setup: UserA initiates transfer
        uint256 transferFee = protocolVault.quoteOperation(PayloadType.LP_SHARE_TRANSFER, userB, TRANSFER_AMOUNT);
        vm.prank(userA);
        protocolVault.transferShare{value: transferFee}(userB, TRANSFER_AMOUNT, ORDERLY_BROKER);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 requestId = _calculateRequestId(31337, 0, vaultId);
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        bytes memory signature = _getShareTransferSignature(requestIds);

        // Try to execute as non-operator (userA)
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("InvalidOperator()"));
        svLedger.executeShareTransfer(requestIds, signature);
        
        // Try to execute as owner (not operator)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidOperator()"));
        svLedger.executeShareTransfer(requestIds, signature);
    }

    // ==================== Helper Functions ====================

    /// @notice Calculate requestId consistent with backend logic
    function _calculateRequestId(uint256 chainId, uint256 chainNonce, bytes32 _vaultId)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                Strings.toString(chainId),
                Strings.toString(chainNonce),
                _vaultId
            )
        );
    }
    /// @notice Get share transfer signature
    function _getShareTransferSignature(bytes32[] memory requestIds) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(requestIds));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        return abi.encodePacked(r, s, v);
    }

    /// @notice Get share transfer request from ledger
    function _getShareTransferRequest(bytes32 requestId) internal view returns (ShareTransferRequest memory) {
        (bytes32 fromAccountId, bytes32 toAccountId, uint256 amount, bytes32 _vaultId, bool executed) =
            svLedger.shareTransferRequests(requestId);
        return ShareTransferRequest({
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            amount: amount,
            vaultId: _vaultId,
            executed: executed
        });
    }

    // ==================== Events ====================

    event OperationExecuted(PayloadType payloadType, OperationData operationData);
    event ShareTransferRequested(
        bytes32 indexed requestId,
        bytes32 indexed vaultId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount
    );
    event ShareTransferExecuted(ShareTransferResult[] results);
    event InnerTransferWhitelistUpdated(address[] users, bool isWhitelisted);
}
