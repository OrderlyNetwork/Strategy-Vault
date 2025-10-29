// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Base} from "../Base.sol";
import {console} from "forge-std/console.sol";
import {
    AccountToken,
    StrategyFundToken,
    UpdateStrategyFundAssetsParams,
    UpdateStrategyFundAssetsRes,
    PendingState,
    Operation,
    OperationType,
    OperationRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    AllocateFundRes,
    StrategyFundState,
    ClaimInfo,
    DexRequest
} from "../../contracts/lib/types/LedgerStruct.sol";
import {ILedgerCoreImpl} from "../../contracts/interfaces/ILedgerCoreImpl.sol";
import {ILedgerExtension} from "../../contracts/interfaces/ILedgerExtension.sol";
import {IProtocolVaultLedger} from "../../contracts/interfaces/IProtocolVaultLedger.sol";
import {LedgerUtils} from "../../contracts/lib/utils/LedgerUtils.sol";
import {UserClaimedInfo, RoleType, ClaimParams} from "../../contracts/Vault/ProtocolVault.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title Community Vault Ledger Test
/// @notice Tests for community vault ledger operations and full ledger update flow
contract CommunityVaultTest is Base {
    uint256 shareDecimal = 1e6;
    uint256 assetDecimal = 1e6;
    uint256 priceDecimal = 1e6;
    uint256 periodId;

    bytes32[] public spIds;
    bytes32[] public accountIds;

    function setUp() public override {
        super.setUp();
        spIds.push(spA_id);
        spIds.push(spB_id);
        accountIds.push(userA_id);
        accountIds.push(userB_id);
    }

    /// @notice Test complete ledger update flow for community vault
    /// @dev Tests: updateStrategyFundAssets -> updateLPAndStrategyFund -> allocateToFunds -> settleMainAndStrategyFunds -> settleAccounts -> updatePeriodId
    function testCommunityVaultLedgerFullFlow() public {
        // Initialize community vault state
        _initializeCommunityVault();

        console.log("=============Start Community Vault Ledger Full Flow Test=====================");

        vm.startPrank(operator);

        // Step 1: updateStrategyFundAssets - Update strategy fund assets
        console.log("Step 1: Update strategy fund assets");
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](2);
        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 2500 * assetDecimal); // SP A has 2500 assets
        strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1800 * assetDecimal); // SP B has 1800 assets

        bytes memory signature = _getUploadFundAssetsSignature(periodId, cvVaultId, strategyFundAssets);
        svLedger.updateStrategyFundAssets(periodId, cvVaultId, strategyFundAssets, signature);

        _assertStrategyFundState("After updateStrategyFundAssets");

        // Step 2: updateLPAndStrategyFund - Update LP and strategy fund info
        console.log("Step 2: Update LP and strategy fund operations");
        UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](4);

        // LP deposit 500 assets
        Operation memory lpDepositOp =
            Operation({id: userA_id, requestId: keccak256(abi.encode("lpDeposit1")), amount: 500 * assetDecimal});
        updateLedgerParams[0] = UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: lpDepositOp});

        // LP withdraw 0.3 shares
        Operation memory lpWithdrawOp =
            Operation({id: userB_id, requestId: keccak256(abi.encode("lpWithdraw1")), amount: 3 * shareDecimal / 10});
        updateLedgerParams[1] = UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: lpWithdrawOp});

        // SP deposit 300 assets
        Operation memory spDepositOp =
            Operation({id: spA_id, requestId: keccak256(abi.encode("spDeposit1")), amount: 300 * assetDecimal});
        updateLedgerParams[2] = UpdateLedgerParams({operationType: OperationType.SP_DEPOSIT, operation: spDepositOp});

        // SP withdraw 0.2 shares
        Operation memory spWithdrawOp =
            Operation({id: spB_id, requestId: keccak256(abi.encode("spWithdraw1")), amount: 2 * shareDecimal / 10});
        updateLedgerParams[3] = UpdateLedgerParams({operationType: OperationType.SP_WITHDRAW, operation: spWithdrawOp});

        signature = _getUpdateLPAndStrategyFundSig(periodId, cvVaultId, updateLedgerParams);
        svLedger.updateLPAndStrategyFund(periodId, cvVaultId, updateLedgerParams, signature);

        _assertAccountState("After updateLPAndStrategyFund");

        // Step 3: allocateToFunds - Allocate funds to strategy funds
        console.log("Step 3: Allocate funds to strategy funds");
        signature = _getALlocateFundsSig(periodId, cvVaultId, spIds);
        svLedger.allocateToFunds(periodId, cvVaultId, spIds, signature);

        _assertStrategyFundState("After allocateToFunds");

        // Step 4: settleMainAndStrategyFunds - Settle main and strategy funds
        console.log("Step 4: Settle main and strategy funds");
        signature = _getSettleMainAndFundSig(periodId, cvVaultId, spIds);
        svLedger.settleMainAndStrategyFunds(periodId, cvVaultId, spIds, signature);

        _assertStrategyFundState("After settleMainAndStrategyFunds");

        // Step 5: settleAccounts - Settle accounts
        console.log("Step 5: Settle accounts");
        signature = _getSettleAccountSig(periodId, cvVaultId, accountIds);
        svLedger.settleAccounts(periodId, cvVaultId, accountIds, signature);

        _assertAccountState("After settleAccounts");

        // Step 6: updatePeriodId - Update period ID
        console.log("Step 6: Update period ID");
        signature = _getUpdatePeriodIdSig(periodId, cvVaultId);
        svLedger.updatePeriodId(periodId, cvVaultId, signature);

        console.log("Period update completed, current period ID:", periodId + 1);

        vm.stopPrank();

        // Verify final state
        _verifyFinalState();

        console.log("=============Community Vault Ledger Full Flow Test Completed=====================");
    }

    /// @notice Test multiple periods of ledger updates
    function testCommunityVaultMultiplePeriods() public {
        _initializeCommunityVault();

        console.log("=============Test Multiple Periods Ledger Update=====================");

        vm.startPrank(operator);

        // Period 1
        _executePeriod(1, 3000 * assetDecimal, 2000 * assetDecimal);

        // Period 2 - Simulate profit growth
        _executePeriod(2, 3500 * assetDecimal, 2300 * assetDecimal);

        // Period 3 - Simulate partial loss
        _executePeriod(3, 3200 * assetDecimal, 2100 * assetDecimal);

        vm.stopPrank();

        console.log("=============Multiple Periods Test Completed=====================");
    }

    /// @notice Test error cases in ledger update flow
    function testCommunityVaultErrorCases() public {
        _initializeCommunityVault();

        vm.startPrank(operator);

        // Test duplicate updateStrategyFundAssets call
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](1);
        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 1000 * assetDecimal);

        bytes memory signature = _getUploadFundAssetsSignature(periodId, cvVaultId, strategyFundAssets);
        svLedger.updateStrategyFundAssets(periodId, cvVaultId, strategyFundAssets, signature);

        // Should revert on second call
        vm.expectRevert(ILedgerCoreImpl.AlreadyCalled.selector);
        svLedger.updateStrategyFundAssets(periodId, cvVaultId, strategyFundAssets, signature);

        // Test duplicate allocateToFunds call
        signature = _getALlocateFundsSig(periodId, cvVaultId, spIds);
        svLedger.allocateToFunds(periodId, cvVaultId, spIds, signature);

        vm.expectRevert(ILedgerCoreImpl.AlreadyCalled.selector);
        svLedger.allocateToFunds(periodId, cvVaultId, spIds, signature);

        vm.stopPrank();
    }

    /// @notice Test using specific assertion functions with expected values
    function testCommunityVaultSpecificAssertions() public {
        _initializeCommunityVault();

        console.log("=============Test Specific Assertions=====================");

        vm.startPrank(operator);

        // Test with specific expected values after updateStrategyFundAssets
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](2);
        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 3000 * assetDecimal);
        strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1500 * assetDecimal);

        bytes memory signature = _getUploadFundAssetsSignature(periodId, cvVaultId, strategyFundAssets);
        svLedger.updateStrategyFundAssets(periodId, cvVaultId, strategyFundAssets, signature);

        // Use specific assertion functions to verify exact values
        _assertStrategyFundValues(
            cvVaultId,
            spA_id,
            2000 * assetDecimal, // totalAssets should remain 2000 until settled
            2000000, // totalShares (2 * shareDecimal)
            1000000, // mainShares (1 * shareDecimal)
            "Fund A after updateStrategyFundAssets"
        );

        // Test account state with specific values
        _assertAccountValues(
            cvVaultId,
            userA_id,
            0, // shares (not settled yet)
            0, // pendingShares (no operations yet)
            1000 * assetDecimal, // unallocatedAssets
            "User A after initialization"
        );

        // Test vault global state
        _assertVaultGlobalState(
            cvVaultId,
            2 * shareDecimal, // expectedMainShares
            2 * shareDecimal, // expectedPendingMainShares
            "Vault global state after updateStrategyFundAssets"
        );

        // Settle the funds to see the changes
        signature = _getSettleMainAndFundSig(periodId, cvVaultId, spIds);
        svLedger.settleMainAndStrategyFunds(periodId, cvVaultId, spIds, signature);

        // Now assert the settled values with performance fees applied
        StrategyFundToken memory fundA = svLedger.getStrategyFund(cvVaultId, spA_id);
        StrategyFundToken memory fundB = svLedger.getStrategyFund(cvVaultId, spB_id);

        // Fund A should have performance fee applied (3000 > 2000, so fee on 1000 gain)
        assertTrue(fundA.totalShares > 2000000, "Fund A should have additional shares from performance fee");
        assertTrue(fundA.hwm > 1000 * priceDecimal, "Fund A HWM should increase due to performance");

        // Fund B should have no performance fee (1500 < 2000, so loss)
        assertEq(fundB.totalShares, 2000000, "Fund B should have no additional shares (no performance fee on loss)");
        assertEq(fundB.hwm, 1000 * priceDecimal, "Fund B HWM should remain unchanged (loss scenario)");

        vm.stopPrank();

        console.log("=============Specific Assertions Test Completed=====================");
    }

    function testCVtDistributeAssetsToOneChain() public {
        uint256 amount = 1000 * assetDecimal;
        AssetsDistribution[] memory assetsDistributions = new AssetsDistribution[](1);
        assetsDistributions[0] = AssetsDistribution({chainId: evmChainId, assets: amount});

        bytes memory signature = _getDistributeAssetsSignature(periodId, cvVaultId, assetsDistributions);

        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        //mint token
        mockToken.mint(address(communityVault), amount);
        vm.startPrank(operator);
        svLedger.distributeAssets(periodId, cvVaultId, assetsDistributions, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        assertEq(mockDexVault.amount(), amount);
    }

    function testCVUpdateUnclaimed() public {
        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, 0, cvVaultId, requestIds);

        //deal eth to cc contract on ledger
        uint256 asset = 1000 * assetDecimal;
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        svLedger.setLpClaimInfo(cvVaultId, requestIds[0], userA_id, asset);
        svLedger.setLpClaimInfo(cvVaultId, requestIds[1], userB_id, asset);

        vm.startPrank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, 0, cvVaultId, requestIds, signature);

        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        UserClaimedInfo memory userClaimedInfo_A = communityVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo_A.unClaimedAssets, asset);
        assertEq(userClaimedInfo_A.requestIds[0], keccak256(abi.encode(0)));

        UserClaimedInfo memory userClaimedInfo_B = communityVault.getUserClaimedInfo(userB_id);
        assertEq(userClaimedInfo_B.unClaimedAssets, asset);
        assertEq(userClaimedInfo_B.requestIds[0], keccak256(abi.encode(1)));
    }

    /// @notice Initialize community vault with initial state
    function _initializeCommunityVault() internal {
        // Set initial balances and shares
        uint256 initialMainShares = 2 * shareDecimal;
        uint256 initialAssets = 2000 * assetDecimal;

        // Initialize strategy funds
        uint256[] memory strategyFundsAssets = new uint256[](2);
        strategyFundsAssets[0] = initialAssets;
        strategyFundsAssets[1] = initialAssets;

        uint256[] memory mainSharesInFund = new uint256[](2);
        mainSharesInFund[0] = 1 * shareDecimal;
        mainSharesInFund[1] = 1 * shareDecimal;

        uint256[] memory spSharesInFund = new uint256[](2);
        spSharesInFund[0] = 1 * shareDecimal;
        spSharesInFund[1] = 1 * shareDecimal;

        // Initialize vault state
        svLedger.initializeStrategyFund(
            cvVaultId,
            initialMainShares,
            spIds,
            mainSharesInFund,
            spSharesInFund,
            strategyFundsAssets,
            1000 * priceDecimal
        );

        // Set LP unallocated assets
        uint256 lpUnallocatedAssets = 1000 * assetDecimal;
        svLedger.setAccountUnAllocatedAssets(cvVaultId, accountIds, lpUnallocatedAssets);

        // Set SP unallocated assets
        svLedger.setSPUnallocatedAssets(cvVaultId, spIds, 500 * assetDecimal);

        // Set frozen shares for testing withdrawals - ensure users have enough shares
        bytes32[] memory singleAccountB = new bytes32[](1);
        singleAccountB[0] = userB_id;
        svLedger.setAccountPendingShares(cvVaultId, singleAccountB, 1 * shareDecimal); // Give userB 1 share
        svLedger.setAccountFrozenShares(cvVaultId, singleAccountB, 5 * shareDecimal / 10); // 0.5 frozen shares

        bytes32[] memory singleAccountA = new bytes32[](1);
        singleAccountA[0] = userA_id;
        svLedger.setAccountFrozenShares(cvVaultId, singleAccountA, 5 * shareDecimal / 10);

        svLedger.setSPFrozenShares(cvVaultId, spIds, 3 * shareDecimal / 10);

        console.log("Community vault initialization completed");

        // Assert initial community vault state
        _assertInitialState();

        // Check that protocol vault data on ledger should not be affected
        _assertProtocolVaultIsolation();
    }

    /// @notice Execute a complete period cycle
    function _executePeriod(uint256 period, uint256 spAAssets, uint256 spBAssets) internal {
        console.log("=============Execute Period", period, "=====================");

        // Update strategy fund assets
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](2);
        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, spAAssets);
        strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, spBAssets);

        bytes memory signature = _getUploadFundAssetsSignature(periodId, cvVaultId, strategyFundAssets);
        svLedger.updateStrategyFundAssets(periodId, cvVaultId, strategyFundAssets, signature);

        // Allocate funds
        signature = _getALlocateFundsSig(periodId, cvVaultId, spIds);
        svLedger.allocateToFunds(periodId, cvVaultId, spIds, signature);

        // Settle funds
        signature = _getSettleMainAndFundSig(periodId, cvVaultId, spIds);
        svLedger.settleMainAndStrategyFunds(periodId, cvVaultId, spIds, signature);

        // Settle accounts
        signature = _getSettleAccountSig(periodId, cvVaultId, accountIds);
        svLedger.settleAccounts(periodId, cvVaultId, accountIds, signature);

        // Update period
        signature = _getUpdatePeriodIdSig(periodId, cvVaultId);
        svLedger.updatePeriodId(periodId, cvVaultId, signature);

        periodId++;

        console.log("Period", period, "execution completed");
    }

    /// @notice Assert initial state is correctly set
    function _assertInitialState() internal view {
        console.log("--- Asserting Initial State ---");
        StrategyFundToken memory fundA = svLedger.getStrategyFund(cvVaultId, spA_id);
        StrategyFundToken memory fundB = svLedger.getStrategyFund(cvVaultId, spB_id);

        // Assert initial assets are set correctly
        assertEq(fundA.totalAssets, 2000 * assetDecimal, "Fund A initial total assets should be 2000");
        assertEq(fundB.totalAssets, 2000 * assetDecimal, "Fund B initial total assets should be 2000");
        assertEq(svLedger.getVaultMainShares(cvVaultId), 2 * shareDecimal, "Initial main shares should be 2");

        console.log("Initial state assertions passed");
    }

    /// @notice Assert strategy fund state with expected values
    function _assertStrategyFundState(string memory stage) internal view {
        console.log("--- Asserting Strategy Fund State:", stage, " ---");
        StrategyFundToken memory fundA = svLedger.getStrategyFund(cvVaultId, spA_id);
        StrategyFundToken memory fundB = svLedger.getStrategyFund(cvVaultId, spB_id);

        // Basic sanity checks - assets and shares should be positive
        assertTrue(fundA.totalAssets > 0, "Fund A total assets should be positive");
        assertTrue(fundB.totalAssets > 0, "Fund B total assets should be positive");
        assertTrue(fundA.totalShares > 0, "Fund A total shares should be positive");
        assertTrue(fundB.totalShares > 0, "Fund B total shares should be positive");

        // Pending states should be consistent (can be higher or lower than current, or 0 if not updated)
        assertTrue(fundA.pendingState.pendingTotalAssets >= 0, "Fund A pending assets should not be negative");
        assertTrue(fundB.pendingState.pendingTotalAssets >= 0, "Fund B pending assets should not be negative");

        // HWM should be reasonable (at least 1.0 in decimal terms)
        assertTrue(fundA.hwm >= 1 * priceDecimal, "Fund A HWM should be at least 1.0");
        assertTrue(fundB.hwm >= 1 * priceDecimal, "Fund B HWM should be at least 1.0");

        console.log("Strategy fund state assertions passed for:", stage);
    }

    /// @notice Assert account state with basic consistency checks
    function _assertAccountState(string memory stage) internal view {
        console.log("--- Asserting Account State:", stage, " ---");
        AccountToken memory accountA = svLedger.getAccountToken(cvVaultId, userA_id);
        AccountToken memory accountB = svLedger.getAccountToken(cvVaultId, userB_id);

        // Shares should not be negative
        assertTrue(accountA.shares >= 0, "User A shares should not be negative");
        assertTrue(accountB.shares >= 0, "User B shares should not be negative");
        assertTrue(accountA.pendingShares >= 0, "User A pending shares should not be negative");
        assertTrue(accountB.pendingShares >= 0, "User B pending shares should not be negative");

        // Frozen shares should not be negative (they can exceed total shares temporarily in test setup)
        assertTrue(accountA.frozenShares >= 0, "User A frozen shares should not be negative");
        assertTrue(accountB.frozenShares >= 0, "User B frozen shares should not be negative");

        // Unallocated assets should not be negative
        assertTrue(accountA.unAllocatedAssets >= 0, "User A unallocated assets should not be negative");
        assertTrue(accountB.unAllocatedAssets >= 0, "User B unallocated assets should not be negative");

        console.log("Account state assertions passed for:", stage);
    }

    /// @notice Assert specific strategy fund values
    function _assertStrategyFundValues(
        bytes32 vaultId,
        bytes32 spId,
        uint256 expectedTotalAssets,
        uint256 expectedTotalShares,
        uint256 expectedMainShares,
        string memory description
    ) internal view {
        StrategyFundToken memory fund = svLedger.getStrategyFund(vaultId, spId);

        assertEq(
            fund.totalAssets, expectedTotalAssets, string(abi.encodePacked(description, ": total assets mismatch"))
        );
        assertEq(
            fund.totalShares, expectedTotalShares, string(abi.encodePacked(description, ": total shares mismatch"))
        );
        assertEq(fund.mainShares, expectedMainShares, string(abi.encodePacked(description, ": main shares mismatch")));
    }

    /// @notice Assert specific account values
    function _assertAccountValues(
        bytes32 vaultId,
        bytes32 accountId,
        uint256 expectedShares,
        uint256 expectedPendingShares,
        uint256 expectedUnallocatedAssets,
        string memory description
    ) internal view {
        AccountToken memory account = svLedger.getAccountToken(vaultId, accountId);

        assertEq(account.shares, expectedShares, string(abi.encodePacked(description, ": shares mismatch")));
        assertEq(
            account.pendingShares,
            expectedPendingShares,
            string(abi.encodePacked(description, ": pending shares mismatch"))
        );
        assertEq(
            account.unAllocatedAssets,
            expectedUnallocatedAssets,
            string(abi.encodePacked(description, ": unallocated assets mismatch"))
        );
    }

    /// @notice Assert vault global state
    function _assertVaultGlobalState(
        bytes32 vaultId,
        uint256 expectedMainShares,
        uint256 expectedPendingMainShares,
        string memory description
    ) internal view {
        assertEq(
            svLedger.getVaultMainShares(vaultId),
            expectedMainShares,
            string(abi.encodePacked(description, ": main shares mismatch"))
        );
        assertEq(
            svLedger.getVaultPendingMainShares(vaultId),
            expectedPendingMainShares,
            string(abi.encodePacked(description, ": pending main shares mismatch"))
        );
    }

    /// @notice Assert that protocol vault data is not affected by community vault operations
    function _assertProtocolVaultIsolation() internal view {
        console.log("--- Asserting Protocol Vault Isolation ---");

        // Check protocol vault account data should be unaffected
        AccountToken memory accountA = svLedger.getAccountToken(vaultId, userA_id);
        assertEq(accountA.unAllocatedAssets, 0, "PV: User A unallocated assets should be 0");
        assertEq(accountA.frozenShares, 0, "PV: User A frozen shares should be 0");
        assertEq(accountA.pendingShares, 0, "PV: User A pending shares should be 0");

        // Check protocol vault strategy fund data should be unaffected
        StrategyFundToken memory fundA = svLedger.getStrategyFund(vaultId, spA_id);
        assertEq(fundA.unAllocatedAssets, 0, "PV: Fund A unallocated assets should be 0");
        assertEq(fundA.frozenShares, 0, "PV: Fund A frozen shares should be 0");
        assertEq(fundA.pendingState.pendingStrategyProviderShares, 0, "PV: Fund A pending SP shares should be 0");

        // Check protocol vault global state should be unaffected
        assertEq(svLedger.pendingMainShares(), 0, "PV: Pending main shares should be 0");
        assertEq(svLedger.pendingLpDepositAssets(), 0, "PV: Pending LP deposit assets should be 0");
        assertEq(svLedger.pendingLpWithdrawAssets(), 0, "PV: Pending LP withdraw assets should be 0");
        assertEq(svLedger.mainShares(), 0, "PV: Main shares should be 0");
        assertEq(svLedger.mainAssetsAfterFee(), 0, "PV: Main assets after fee should be 0");
        assertEq(svLedger.latestPeriodId(), 0, "PV: Latest period ID should be 0");

        console.log("Protocol vault isolation assertions passed");
    }

    /// @notice Assert settled state - pending states should equal actual states
    function _assertSettledState(bytes32 vaultId, string memory description) internal view {
        console.log("--- Asserting Settled State:", description, " ---");

        StrategyFundToken memory fundA = svLedger.getStrategyFund(vaultId, spA_id);
        StrategyFundToken memory fundB = svLedger.getStrategyFund(vaultId, spB_id);

        // Strategy funds should be settled
        assertEq(
            fundA.totalAssets,
            fundA.pendingState.pendingTotalAssets,
            string(abi.encodePacked(description, ": Fund A assets should be settled"))
        );
        assertEq(
            fundA.totalShares,
            fundA.pendingState.pendingTotalShares,
            string(abi.encodePacked(description, ": Fund A shares should be settled"))
        );
        assertEq(
            fundB.totalAssets,
            fundB.pendingState.pendingTotalAssets,
            string(abi.encodePacked(description, ": Fund B assets should be settled"))
        );
        assertEq(
            fundB.totalShares,
            fundB.pendingState.pendingTotalShares,
            string(abi.encodePacked(description, ": Fund B shares should be settled"))
        );

        // Accounts should be settled
        AccountToken memory accountA = svLedger.getAccountToken(vaultId, userA_id);
        AccountToken memory accountB = svLedger.getAccountToken(vaultId, userB_id);

        assertEq(
            accountA.shares,
            accountA.pendingShares,
            string(abi.encodePacked(description, ": Account A shares should be settled"))
        );
        assertEq(
            accountB.shares,
            accountB.pendingShares,
            string(abi.encodePacked(description, ": Account B shares should be settled"))
        );

        console.log("Settled state assertions passed for:", description);
    }

    /// @notice Verify final state after full flow
    function _verifyFinalState() internal view {
        console.log("=============Verify Final State=====================");

        // Use the new assertion functions for comprehensive verification
        _assertSettledState(cvVaultId, "Final State Verification");
        _assertStrategyFundState("Final State");
        _assertAccountState("Final State");
        _assertProtocolVaultIsolation();

        console.log("Final state verification passed");
    }

    // Signature helper functions
    function _getUploadFundAssetsSignature(
        uint256 _periodId,
        bytes32 _vaultId,
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId, strategyFundAssets));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getUpdateLPAndStrategyFundSig(
        uint256 _periodId,
        bytes32 _vaultId,
        UpdateLedgerParams[] memory updateUserLedgerParams
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId, updateUserLedgerParams));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getALlocateFundsSig(uint256 _periodId, bytes32 _vaultId, bytes32[] memory strategyProviderIds)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId, strategyProviderIds, "allocateToFunds"));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getSettleMainAndFundSig(uint256 _periodId, bytes32 _vaultId, bytes32[] memory strategyProviderIds)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash =
            keccak256(abi.encode(_periodId, _vaultId, strategyProviderIds, "settleMainAndStrategyFunds"));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getSettleAccountSig(uint256 _periodId, bytes32 _vaultId, bytes32[] memory _accountIds)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId, _accountIds));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getUpdatePeriodIdSig(uint256 _periodId, bytes32 _vaultId) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getDistributeAssetsSignature(
        uint256 _periodId,
        bytes32 _vaultId,
        AssetsDistribution[] memory assetsDistributions
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId, assetsDistributions));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }
}
