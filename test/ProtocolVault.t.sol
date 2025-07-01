// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    VaultType,
    VaultState,
    RoleType,
    ClaimParams,
    DepositParams,
    WithdrawParams,
    OperationData,
    UserClaimedInfo
} from "../contracts/lib/types/VaultStruct.sol";
import {ClaimInfo} from "../contracts/ProtocolVaultLedger.sol";
import {PayloadType, StrategyVaultCCMessage} from "../contracts/lib/types/CrossChainStruct.sol";
import {AccountToken, StrategyFundToken} from "../contracts/lib/types/LedgerStruct.sol";

contract TestProtocolVault is Base {
    error NotEnoughFee();
    error EnforcedPause();
    error NotEnoughUnclaimedAssets(uint256 amount);
    error VaultClosed();
    error NotEnoughCrossChainFee();

    function setUp() public override {
        super.setUp();
    }

    function testInitialize() public view {
        // Check initial state
        assertEq(protocolVault.crossChainManager(), address(aVaultCrossChainManager));

        assertEq(svLedger.crossChainManager(), address(bVaultCrossChainManager));

        assertEq(bVaultCrossChainManager.ledger(), address(svLedger));

        // assertEq(aVaultCrossChainManager.dstEid(), 2);
        // assertEq(bVaultCrossChainManager.dstEid(), 1);
    }

    function testProtocolVaultLPDeposit() public {
        uint256 amount = 100e6;
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, user, amount);
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        // Call deposit function

        vm.prank(user);
        protocolVault.deposit{value: nativeFee}(depositParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        (
            , // shares
            uint256 unAllocatedAssets,
            , // frozenShares
                // pendingShares
        ) = svLedger.accountTokenInfo(accountId, USDC_HASH);
        assertEq(unAllocatedAssets, amount);

        assertEq(protocolVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), amount);
    }

    function testProtocolVaultSPDeposit() public {
        uint256 nativeFee = getEstimateFee(PayloadType.SP_DEPOSIT);
        uint256 amount = 100e6;
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.SP_DEPOSIT,
            receiver: sp,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        vm.prank(owner);
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        protocolVault.setAllowedStrategyProvider(spId, true);
        // Call deposit function
        vm.prank(sp);
        protocolVault.deposit{value: nativeFee}(depositParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        StrategyFundToken memory sf = svLedger.getStrategyFund(spId);
        assertEq(sf.unAllocatedAssets, amount);

        assertEq(protocolVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), amount);
    }

    function testProtocolVaultLPWithdraw() public {
        uint256 nativeFee = getEstimateFee(PayloadType.LP_WITHDRAW);
        uint256 shares = 100e6;
        //Initialize
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = accountId;
        svLedger.setAccountPendingShares(accountIds, shares);
        //Withdraw
        uint256 withdrawShares = 10e6;
        WithdrawParams memory withdrawParams = WithdrawParams({
            payloadType: PayloadType.LP_WITHDRAW,
            token: address(mockToken),
            amount: withdrawShares,
            brokerHash: ORDERLY_BROKER
        });
        vm.prank(user);
        protocolVault.withdraw{value: nativeFee}(withdrawParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        (
            , // shares
            ,
            uint256 frozenShares, // frozenShares
                // pendingShares
        ) = svLedger.accountTokenInfo(accountId, USDC_HASH);
        assertEq(frozenShares, withdrawShares);
    }

    function testNotEnoughProtocolVaultLPWithdraw() public {
        uint256 nativeFee = getEstimateFee(PayloadType.LP_WITHDRAW);

        //Withdraw
        uint256 withdrawShares = 10e6;
        WithdrawParams memory withdrawParams = WithdrawParams({
            payloadType: PayloadType.LP_WITHDRAW,
            token: address(mockToken),
            amount: withdrawShares,
            brokerHash: ORDERLY_BROKER
        });
        vm.prank(user);
        protocolVault.withdraw{value: nativeFee}(withdrawParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        //Check
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        (
            , // shares
            ,
            uint256 frozenShares, // frozenShares
                // pendingShares
        ) = svLedger.accountTokenInfo(accountId, USDC_HASH);
        assertEq(frozenShares, 0);
    }

    function testProtocolVaultSPWithdraw() public {
        uint256 nativeFee = getEstimateFee(PayloadType.SP_WITHDRAW);
        uint256 shares = 100e6;
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        vm.prank(owner);
        protocolVault.setAllowedStrategyProvider(spId, true);
        //Initialize
        bytes32[] memory spIds = new bytes32[](1);
        spIds[0] = spId;
        svLedger.setSpPendingShares(spIds, shares);
        //Withdraw
        vm.prank(sp);
        uint256 withdrawShares = 10e6;
        WithdrawParams memory withdrawParams = WithdrawParams({
            payloadType: PayloadType.SP_WITHDRAW,
            token: address(mockToken),
            amount: withdrawShares,
            brokerHash: ORDERLY_BROKER
        });
        protocolVault.withdraw{value: nativeFee}(withdrawParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        StrategyFundToken memory sf = svLedger.getStrategyFund(spId);

        assertEq(sf.frozenShares, withdrawShares);
        assertEq(protocolVault.chainNonce(), 1);
    }

    function testNotEnoughProtocolVaultSPWithdraw() public {
        uint256 nativeFee = getEstimateFee(PayloadType.SP_WITHDRAW);
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        vm.prank(owner);
        protocolVault.setAllowedStrategyProvider(spId, true);

        //Withdraw
        vm.prank(sp);
        uint256 withdrawShares = 10e6;
        WithdrawParams memory withdrawParams = WithdrawParams({
            payloadType: PayloadType.SP_WITHDRAW,
            token: address(mockToken),
            amount: withdrawShares,
            brokerHash: ORDERLY_BROKER
        });
        protocolVault.withdraw{value: nativeFee}(withdrawParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        StrategyFundToken memory sf = svLedger.getStrategyFund(spId);

        assertEq(sf.frozenShares, 0);
        assertEq(protocolVault.chainNonce(), 1);
    }

    function testLPClaim() public {
        //update user claim info
        uint256 periodId;
        bytes32 vaultId;
        uint256 amount = 100e6;

        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        //add claim info
        svLedger.setLpClaimInfo(requestIds[0], userA_id, amount);
        svLedger.setLpClaimInfo(requestIds[1], userB_id, amount);

        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, 0, vaultId, requestIds, signature);

        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        UserClaimedInfo memory userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo_A.unClaimedAssets, amount);
        assertEq(userClaimedInfo_A.requestIds[0], requestIds[0]);

        uint256 userBalanceBefore = IERC20(mockToken).balanceOf(userA);
        //LP claim
        mockToken.mint(address(protocolVault), amount);

        ClaimParams memory claimParams =
            ClaimParams({roleType: RoleType.LP, token: address(mockToken), brokerHash: ORDERLY_BROKER});
        vm.prank(userA);
        protocolVault.claim(claimParams);

        //check
        userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), 0);
        assertEq(IERC20(mockToken).balanceOf(userA), amount + userBalanceBefore);
        assertEq(userClaimedInfo_A.unClaimedAssets, 0);
        assertEq(userClaimedInfo_A.requestIds.length, 0);
    }

    function testSPAndLPClaim() public {
        //update user claim info
        uint256 periodId;
        bytes32 vaultId;
        uint256 amount = 100e6;

        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        //add claim info
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        svLedger.setLpClaimInfo(requestIds[0], userA_id, amount);
        svLedger.setSpClaimInfo(requestIds[1], spId, amount);
        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, 0, vaultId, requestIds, signature);

        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        UserClaimedInfo memory userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        UserClaimedInfo memory spClaimedInfo = protocolVault.getUserClaimedInfo(spId);

        assertEq(userClaimedInfo_A.unClaimedAssets, amount);
        assertEq(userClaimedInfo_A.requestIds[0], requestIds[0]);
        assertEq(spClaimedInfo.unClaimedAssets, amount);
        assertEq(spClaimedInfo.requestIds[0], requestIds[1]);

        uint256 userBalanceBefore = IERC20(mockToken).balanceOf(sp);

        //SP claim
        mockToken.mint(address(protocolVault), amount);

        ClaimParams memory claimParams =
            ClaimParams({roleType: RoleType.SP, token: address(mockToken), brokerHash: ORDERLY_BROKER});
        vm.prank(sp);
        protocolVault.claim(claimParams);

        //check
        spClaimedInfo = protocolVault.getUserClaimedInfo(spId);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), 0);
        assertEq(IERC20(mockToken).balanceOf(sp), amount + userBalanceBefore);
        assertEq(spClaimedInfo.unClaimedAssets, 0);
        assertEq(spClaimedInfo.requestIds.length, 0);
    }

    function testUnpause() public {
        vm.prank(owner);
        protocolVault.emergencyPause();
        vm.prank(owner);
        protocolVault.emergencyUnpause();

        uint256 nativeFee = getEstimateFee(PayloadType.LP_DEPOSIT);
        uint256 amount = 100e6;
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        // Call deposit function

        vm.prank(user);
        protocolVault.deposit{value: nativeFee}(depositParams);
    }

    function testEmitFailedProtocolVaultLPWithdrawNotEnoughShares() public {
        uint256 nativeFee = getEstimateFee(PayloadType.LP_WITHDRAW);
        uint256 withdrawShares = 10e6;
        WithdrawParams memory withdrawParams = WithdrawParams({
            payloadType: PayloadType.LP_WITHDRAW,
            token: address(mockToken),
            amount: withdrawShares,
            brokerHash: ORDERLY_BROKER
        });
        protocolVault.withdraw{value: nativeFee}(withdrawParams);
        assertEq(protocolVault.chainNonce(), 1);

        //LZ
        // vm.expectRevert(NotEnoughWithdrawShare.selector);

        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
    }

    function testSpecialDecimalLPDeposit() public {
        //set special token
        vm.prank(owner);
        bVaultCrossChainManager.setSpecialTokenDecimal(USDC_HASH, 31337, 18);

        uint256 nativeFee = getEstimateFee(PayloadType.LP_DEPOSIT);
        uint256 amount = 100e18;
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        // Call deposit function
        vm.prank(user);
        mockToken.approve(address(protocolVault), 100e18);
        vm.prank(user);
        protocolVault.deposit{value: nativeFee}(depositParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        uint256 convertedAmount = 100e6;
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        (
            , // shares
            uint256 unAllocatedAssets,
            , // frozenShares
                // pendingShares
        ) = svLedger.accountTokenInfo(accountId, USDC_HASH);
        assertEq(unAllocatedAssets, convertedAmount);

        assertEq(protocolVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), amount);
    }
    // function testRevertProtocolVaultLPDepositWithoutVaule() public {
    //     //deal eth to cc contract on ledger
    //     vm.deal(address(aVaultCrossChainManager), 10 ether);

    //     uint256 amount = 100e6;
    //     DepositParams memory depositParams = DepositParams({
    //         payloadType: PayloadType.LP_DEPOSIT,
    //         receiver: user,
    //         token: address(mockToken),
    //         amount: amount,
    //         brokerHash: ORDERLY_BROKER
    //     });
    //     // Call deposit function

    //     vm.prank(user);

    //     vm.expectRevert(NotEnoughFee.selector);
    //     protocolVault.deposit{value: 0}(depositParams);

    //     //LZ
    //     verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

    //     //Check
    //     bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
    //     (
    //         , // accountId
    //         uint256 assets, // assets
    //         , // shares
    //         uint256 unAllocatedAssets,
    //         , // frozenShares
    //         , // pendingShares
    //             // enableClaimedAssets
    //     ) = svLedger.accountById(accountId);

    //     assertEq(unAllocatedAssets, 0);
    //     assertEq(assets, 0);
    //     assertEq(protocolVault.chainNonce(), 0);
    // }

    // function testRevertProtocolVaultLPWithdrawWithoutVaule() public {
    //     uint256 shares = 100e6;
    //     //Initialize
    //     svLedger.setAccountShares(_getAccountId(user, ORDERLY_BROKER), shares);
    //     //Withdraw
    //     uint256 withdrawShares = 10e6;
    //     WithdrawParams memory withdrawParams = WithdrawParams({
    //         payloadType: PayloadType.LP_WITHDRAW,
    //         token: address(mockToken),
    //         amount: withdrawShares,
    //         brokerHash: ORDERLY_BROKER
    //     });
    //     vm.prank(user);

    //     vm.expectRevert(NotEnoughFee.selector);
    //     protocolVault.withdraw{value: 0}(withdrawParams);
    // }

    function testRevertClaimNotEnough() public {
        ClaimParams memory claimParams =
            ClaimParams({roleType: RoleType.LP, token: address(mockToken), brokerHash: ORDERLY_BROKER});
        vm.prank(userA);

        vm.expectRevert(abi.encodeWithSelector(NotEnoughUnclaimedAssets.selector, 0));
        protocolVault.claim(claimParams);
    }

    function testRevertPause() public {
        vm.prank(owner);
        protocolVault.emergencyPause();
        vm.expectRevert(EnforcedPause.selector);
        protocolVault.deposit{value: 0}(
            DepositParams({
                payloadType: PayloadType.LP_DEPOSIT,
                receiver: user,
                token: address(mockToken),
                amount: 100e6,
                brokerHash: ORDERLY_BROKER
            })
        );
    }

    function testAdminPause() public {
        vm.prank(owner);
        protocolVault.setAdmin(user, true);
        vm.prank(user);
        protocolVault.emergencyPause();
        vm.expectRevert(EnforcedPause.selector);
        protocolVault.deposit{value: 0}(
            DepositParams({
                payloadType: PayloadType.LP_DEPOSIT,
                receiver: user,
                token: address(mockToken),
                amount: 100e6,
                brokerHash: ORDERLY_BROKER
            })
        );
    }

    function testRevertCloseVault() public {
        vm.prank(owner);
        protocolVault.setVaultState(VaultState.CLOSED);

        vm.expectRevert(VaultClosed.selector);
        protocolVault.deposit{value: 0}(
            DepositParams({
                payloadType: PayloadType.LP_DEPOSIT,
                receiver: user,
                token: address(mockToken),
                amount: 100e6,
                brokerHash: ORDERLY_BROKER
            })
        );
    }

    function testLPWhitelist() public {
        // 设置白名单开启和结束时间（一周后）
        uint256 endTime = block.timestamp + 7 days;
        vm.prank(owner);
        protocolVault.setLpWhitelistConfig(true, endTime);

        // 添加用户A到白名单
        address[] memory whitelistUsers = new address[](1);
        whitelistUsers[0] = userA;
        vm.prank(owner);
        protocolVault.updateLpWhitelist(whitelistUsers, true);

        uint256 amount = 100e6;
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, amount);

        // 白名单用户可以存款
        vm.startPrank(userA);
        mockToken.approve(address(protocolVault), amount);
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: userA,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        protocolVault.deposit{value: nativeFee}(depositParams);
        vm.stopPrank();

        // 非白名单用户不能存款
        vm.startPrank(userB);
        mockToken.approve(address(protocolVault), amount);
        depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: userB,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        vm.expectRevert("Not in whitelist");
        protocolVault.deposit{value: nativeFee}(depositParams);
        vm.stopPrank();
    }

    function testLPWhitelistExpired() public {
        // set whitelist config
        uint256 endTime = block.timestamp - 1;
        vm.prank(owner);
        vm.expectRevert("Invalid end time");
        protocolVault.setLpWhitelistConfig(true, endTime);
    }

    function testLPWhitelistDisabled() public {
        //cloase whitelist
        vm.prank(owner);
        protocolVault.setLpWhitelistConfig(false, 0);

        uint256 amount = 100e6;
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, amount);

        //whitelist disable
        vm.startPrank(userB);
        mockToken.approve(address(protocolVault), amount);
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: userB,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        protocolVault.deposit{value: nativeFee}(depositParams);
        vm.stopPrank();
    }

    function testLPWhitelistBatchUpdate() public {
        // batch update whitelist
        address[] memory whitelistUsers = new address[](2);
        whitelistUsers[0] = userA;
        whitelistUsers[1] = userB;

        vm.startPrank(owner);
        protocolVault.updateLpWhitelist(whitelistUsers, true);

        uint256 endTime = block.timestamp + 7 days;
        protocolVault.setLpWhitelistConfig(true, endTime);
        vm.stopPrank();

        uint256 amount = 100e6;
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, amount);

        //whitelist user can deposit
        for (uint256 i = 0; i < whitelistUsers.length; i++) {
            vm.startPrank(whitelistUsers[i]);
            mockToken.approve(address(protocolVault), amount);
            DepositParams memory depositParam = DepositParams({
                payloadType: PayloadType.LP_DEPOSIT,
                receiver: whitelistUsers[i],
                token: address(mockToken),
                amount: amount,
                brokerHash: ORDERLY_BROKER
            });
            protocolVault.deposit{value: nativeFee}(depositParam);
            vm.stopPrank();
        }

        //remove whitelist user
        vm.prank(owner);
        protocolVault.updateLpWhitelist(whitelistUsers, false);

        //can not deposit
        vm.startPrank(userA);
        mockToken.approve(address(protocolVault), amount);
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: userA,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        vm.expectRevert("Not in whitelist");
        protocolVault.deposit{value: nativeFee}(depositParams);
        vm.stopPrank();
    }

    function testWithdrawCrossChainFee() public {
        // Setup: Create some cross chain fees
        uint256 periodId;
        bytes32 vaultId;
        uint256 amount = 100e6;
        uint256 ccFee = 20; // Total fee

        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        // Add claim info on ledger
        svLedger.setLpClaimInfo(requestIds[0], userA_id, amount);
        svLedger.setLpClaimInfo(requestIds[1], userB_id, amount);

        // Process unclaimed update with fees
        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, ccFee, vaultId, requestIds, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        // Calculate expected accumulated fee: feePerUser = 20/2 = 10, actualTotalFee = 10*2 = 20
        uint256 expectedAccumulatedFee = (ccFee / requestIds.length) * requestIds.length;
        assertEq(protocolVault.claimCrossChainFee(), expectedAccumulatedFee, "Cross chain fee should be accumulated correctly");

        // Mint tokens to vault to represent collected fees
        mockToken.mint(address(protocolVault), expectedAccumulatedFee);

        // Owner withdraws part of the fees
        uint256 withdrawAmount = 15;
        uint256 ownerBalanceBefore = mockToken.balanceOf(owner);
        
        vm.prank(owner);
        protocolVault.withdrawToken(address(mockToken), owner, withdrawAmount);

        // Verify withdrawal
        uint256 ownerBalanceAfter = mockToken.balanceOf(owner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, withdrawAmount, "Owner should receive withdrawn amount");
        assertEq(protocolVault.claimCrossChainFee(), expectedAccumulatedFee - withdrawAmount, "Cross chain fee should be reduced after withdrawal");
    }

    function testWithdrawCrossChainFeeExceedsAvailable() public {
        // Setup: Create some cross chain fees
        uint256 periodId;
        bytes32 vaultId;
        uint256 amount = 100e6;
        uint256 ccFee = 10;

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256(abi.encode(0));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        svLedger.setLpClaimInfo(requestIds[0], userA_id, amount);

        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, ccFee, vaultId, requestIds, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        uint256 expectedAccumulatedFee = ccFee; // Only 1 user, so actualTotalFee = ccFee
        assertEq(protocolVault.claimCrossChainFee(), expectedAccumulatedFee, "Cross chain fee should be accumulated");

        // Try to withdraw more than available
        uint256 excessiveWithdrawAmount = expectedAccumulatedFee + 1;
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotEnoughCrossChainFee.selector));
        protocolVault.withdrawToken(address(mockToken), owner, excessiveWithdrawAmount);
    }

    function testMultipleFeeAccumulationAndWithdrawal() public {
        uint256 periodId;
        bytes32 vaultId;
        uint256 amount = 100e6;

        // First batch of fees
        uint256 ccFee1 = 12;
        bytes32[] memory requestIds1 = new bytes32[](3);
        requestIds1[0] = keccak256(abi.encode(0));
        requestIds1[1] = keccak256(abi.encode(1));
        requestIds1[2] = keccak256(abi.encode(2));

        bytes memory signature1 = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds1);
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        for (uint256 i = 0; i < requestIds1.length; i++) {
            svLedger.setLpClaimInfo(requestIds1[i], userA_id, amount);
        }

        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, ccFee1, vaultId, requestIds1, signature1);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        uint256 expectedFee1 = (ccFee1 / requestIds1.length) * requestIds1.length; // 4 * 3 = 12
        assertEq(protocolVault.claimCrossChainFee(), expectedFee1, "First fee accumulation should be correct");

        // Second batch of fees
        uint256 ccFee2 = 21;
        bytes32[] memory requestIds2 = new bytes32[](2);
        requestIds2[0] = keccak256(abi.encode(3));
        requestIds2[1] = keccak256(abi.encode(4));

        bytes memory signature2 = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds2);

        for (uint256 i = 0; i < requestIds2.length; i++) {
            svLedger.setLpClaimInfo(requestIds2[i], userB_id, amount);
        }

        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, ccFee2, vaultId, requestIds2, signature2);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        uint256 expectedFee2 = (ccFee2 / requestIds2.length) * requestIds2.length; // 10 * 2 = 20
        uint256 totalExpectedFee = expectedFee1 + expectedFee2; // 12 + 20 = 32
        assertEq(protocolVault.claimCrossChainFee(), totalExpectedFee, "Total fee accumulation should be correct");

        // Mint tokens to represent collected fees
        mockToken.mint(address(protocolVault), totalExpectedFee);

        // Owner withdraws all fees
        uint256 ownerBalanceBefore = mockToken.balanceOf(owner);
        
        vm.prank(owner);
        protocolVault.withdrawToken(address(mockToken), owner, totalExpectedFee);

        // Verify complete withdrawal
        uint256 ownerBalanceAfter = mockToken.balanceOf(owner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, totalExpectedFee, "Owner should receive all fees");
        assertEq(protocolVault.claimCrossChainFee(), 0, "Cross chain fee should be zero after full withdrawal");
    }

    function testWithdrawNativeToken() public {
        // Send some native tokens to the vault
        uint256 nativeAmount = 1 ether;
        vm.deal(address(protocolVault), nativeAmount);

        uint256 ownerBalanceBefore = owner.balance;

        // Withdraw native tokens
        vm.prank(owner);
        protocolVault.withdrawToken(address(0), owner, nativeAmount);

        uint256 ownerBalanceAfter = owner.balance;
        assertEq(ownerBalanceAfter - ownerBalanceBefore, nativeAmount, "Owner should receive native tokens");
        assertEq(address(protocolVault).balance, 0, "Vault should have no native tokens left");
    }

    function testSingleUserCcFeeCollectionAndWithdrawal() public {
        // Setup: Create cross chain fee scenario with single user
        uint256 periodId;
        bytes32 vaultId;
        uint256 userAsset = 1000e6; // User has 1000 USDC to claim
        uint256 ccFee = 50; // 50 USDC cross chain fee

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256(abi.encode("singleUser"));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        // Add claim info for single user
        svLedger.setLpClaimInfo(requestIds[0], userA_id, userAsset);

        // Process unclaimed update with fees
        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, ccFee, vaultId, requestIds, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        // For single user: feePerUser = ccFee / 1 = 50, actualTotalFee = 50 * 1 = 50
        uint256 expectedFeePerUser = ccFee; // 50
        uint256 expectedActualTotalFee = ccFee; // 50 (same as ccFee for single user)
        uint256 expectedUserAssets = userAsset - expectedFeePerUser; // 1000 - 50 = 950

        // Verify user claim info (asset should be reduced by fee)
        UserClaimedInfo memory userClaimedInfo = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo.unClaimedAssets, expectedUserAssets, "User assets should be reduced by ccFee");
        assertEq(userClaimedInfo.requestIds.length, 1, "User should have 1 request ID");
        assertEq(userClaimedInfo.requestIds[0], requestIds[0], "Request ID should match");

        // Verify protocol vault accumulated the correct fee
        assertEq(protocolVault.claimCrossChainFee(), expectedActualTotalFee, "Protocol should collect exactly the ccFee amount");

        // Mint tokens to vault to represent the collected fees
        mockToken.mint(address(protocolVault), expectedActualTotalFee);
        
        // Owner withdraws the collected fees
        uint256 ownerBalanceBefore = mockToken.balanceOf(owner);
        
        vm.prank(owner);
        protocolVault.withdrawToken(address(mockToken), owner, expectedActualTotalFee);

        // Verify owner received the fees
        uint256 ownerBalanceAfter = mockToken.balanceOf(owner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, expectedActualTotalFee, "Owner should receive all collected fees");
        
        // Verify protocol vault fee counter is reset
        assertEq(protocolVault.claimCrossChainFee(), 0, "Cross chain fee should be zero after withdrawal");

        // Verify the fee amount calculation
        assertEq(expectedActualTotalFee, ccFee, "For single user, actualTotalFee should equal original ccFee");
        
        // Additional verification: User can still claim their remaining assets
        mockToken.mint(address(protocolVault), expectedUserAssets);
        
        uint256 userBalanceBefore = mockToken.balanceOf(userA);
        ClaimParams memory claimParams = ClaimParams({
            roleType: RoleType.LP, 
            token: address(mockToken), 
            brokerHash: ORDERLY_BROKER
        });
        
        vm.prank(userA);
        protocolVault.claim(claimParams);
        
        uint256 userBalanceAfter = mockToken.balanceOf(userA);
        assertEq(userBalanceAfter - userBalanceBefore, expectedUserAssets, "User should receive assets minus fee");
        
        // Final verification: User claim info should be cleared
        userClaimedInfo = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo.unClaimedAssets, 0, "User unclaimed assets should be zero after claim");
        assertEq(userClaimedInfo.requestIds.length, 0, "User request IDs should be cleared after claim");
    }
}
