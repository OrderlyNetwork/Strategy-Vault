// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProtocolVault} from "../contracts/Vault/ProtocolVault.sol";
import {MockDexVault} from "./mock/MockDexVault.sol";

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
import {ClaimInfo} from "../contracts/Ledger/ProtocolVaultLedger.sol";
import {PayloadType, StrategyVaultCCMessage} from "../contracts/lib/types/CrossChainStruct.sol";
import {AccountToken, StrategyFundToken} from "../contracts/lib/types/LedgerStruct.sol";

contract TestProtocolVault is Base {
    error NotEnoughFee();
    error EnforcedPause();
    error NotEnoughUnclaimedAssets(uint256 amount);
    error VaultClosed();

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
        AccountToken memory accountToken = svLedger.getAccountToken(vaultId, accountId);
        assertEq(accountToken.unAllocatedAssets, amount);

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

        StrategyFundToken memory sf = svLedger.getStrategyFund(vaultId, spId);
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
        svLedger.setAccountPendingShares(vaultId, accountIds, shares);
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
        AccountToken memory accountToken = svLedger.getAccountToken(vaultId, accountId);
        assertEq(accountToken.frozenShares, withdrawShares);
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
        AccountToken memory accountToken = svLedger.getAccountToken(vaultId, accountId);
        assertEq(accountToken.frozenShares, 0);
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
        svLedger.setSpPendingShares(vaultId, spIds, shares);
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
        StrategyFundToken memory sf = svLedger.getStrategyFund(vaultId, spId);

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
        StrategyFundToken memory sf = svLedger.getStrategyFund(vaultId, spId);

        assertEq(sf.frozenShares, 0);
        assertEq(protocolVault.chainNonce(), 1);
    }

    function testLPClaim() public {
        //update user claim info
        uint256 periodId;
        uint256 amount = 100e6;

        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        //add claim info
        svLedger.setLpClaimInfo(vaultId, requestIds[0], userA_id, amount);
        svLedger.setLpClaimInfo(vaultId, requestIds[1], userB_id, amount);

        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);

        verifyPackets(srcEid, address(aVaultCrossChainManager));

        uint256 ccFeePerUser = protocolVault.crossChainFee(userA_id);

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
        protocolVault.claimWithFee{value: ccFeePerUser}(claimParams);

        ccFeePerUser = protocolVault.crossChainFee(userA_id);
        //check
        assertEq(ccFeePerUser, 0);
        userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), 0);
        assertEq(IERC20(mockToken).balanceOf(userA), amount + userBalanceBefore);
        assertEq(userClaimedInfo_A.unClaimedAssets, 0);
        assertEq(userClaimedInfo_A.requestIds.length, 0);
    }

    function testSPAndLPClaim() public {
        //update user claim info
        uint256 periodId;
        uint256 amount = 100e6;

        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        //add claim info
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        svLedger.setLpClaimInfo(vaultId, requestIds[0], userA_id, amount);
        svLedger.setSpClaimInfo(vaultId, requestIds[1], spId, amount);
        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);

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
        uint256 ccFeePerUser = protocolVault.crossChainFee(spId);

        mockToken.mint(address(protocolVault), amount);

        ClaimParams memory claimParams =
            ClaimParams({roleType: RoleType.SP, token: address(mockToken), brokerHash: ORDERLY_BROKER});
        vm.prank(sp);
        protocolVault.claimWithFee{value: ccFeePerUser}(claimParams);
        ccFeePerUser = protocolVault.crossChainFee(spId);
        //check
        assertEq(ccFeePerUser, 0);
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
        AccountToken memory accountToken = svLedger.getAccountToken(vaultId, accountId);
        assertEq(accountToken.unAllocatedAssets, convertedAmount);

        assertEq(protocolVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), amount);
    }

    function testRevertClaimNotEnough() public {
        ClaimParams memory claimParams =
            ClaimParams({roleType: RoleType.LP, token: address(mockToken), brokerHash: ORDERLY_BROKER});
        vm.prank(userA);

        vm.expectRevert(abi.encodeWithSelector(NotEnoughUnclaimedAssets.selector, 0));
        protocolVault.claimWithFee(claimParams);
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
        uint256 endTime = block.timestamp + 7 days;
        vm.prank(owner);
        protocolVault.setLpWhitelistConfig(true, endTime);

        address[] memory whitelistUsers = new address[](1);
        whitelistUsers[0] = userA;
        vm.prank(owner);
        protocolVault.updateLpWhitelist(whitelistUsers, true);

        uint256 amount = 100e6;
        uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, amount);

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

    function testLPDepositNewVault() public {
        uint256 amount = 100e6;
        uint256 nativeFee = communityVault.quoteOperation(PayloadType.LP_DEPOSIT, user, amount);
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        // Call deposit function
        vm.prank(user);
        communityVault.deposit{value: nativeFee}(depositParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        AccountToken memory accountToken = svLedger.getAccountToken(cvVaultId, accountId);
        assertEq(accountToken.unAllocatedAssets, amount);
        assertEq(communityVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(communityVault)), amount);

        //pv vault on ledger should not be affected
        accountToken = svLedger.getAccountToken(vaultId, accountId);
        assertEq(accountToken.unAllocatedAssets, 0);
        assertEq(protocolVault.chainNonce(), 0);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), 0);
    }
}
