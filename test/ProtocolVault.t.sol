// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";

import {
    VaultType,
    RoleType,
    ClaimParams,
    DepositParams,
    WithdrawParams,
    OperationData,
    UserClaimedInfo
} from "../contracts/lib/types/VaultStruct.sol";
import {UpdateUserClaim} from "../contracts/ProtocolVaultLedger.sol";
import {PayloadType, StrategyVaultCCMessage} from "../contracts/lib/types/CrossChainStruct.sol";
import {Account, StrategyFund} from "../contracts/lib/types/LedgerStruct.sol";

contract TestProtocolVault is Base {
    error NotEnoughWithdrawShare();
    error NotEnoughFee();

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

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        (
            , // accountId
            uint256 assets, // assets
            , // shares
            uint256 unAllocatedAssets,
            , // frozenShares
            , // pendingShares
                // enableClaimedAssets
        ) = svLedger.accountById(accountId);
        assertEq(unAllocatedAssets, amount);
        assertEq(assets, amount);
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

        // Call deposit function
        vm.prank(sp);
        protocolVault.deposit{value: nativeFee}(depositParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);

        StrategyFund memory sf = svLedger.getStrategyFund(spId);
        assertEq(sf.unAllocatedAssets, amount);
    }

    function testProtocolVaultLPWithdraw() public {
        uint256 nativeFee = getEstimateFee(PayloadType.LP_WITHDRAW);
        uint256 shares = 100e6;
        //Initialize
        svLedger.setAccountShares(_getAccountId(user, ORDERLY_BROKER), shares);
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
            , // accountId
            , // assets
            , // shares
            ,
            uint256 frozenShares, // frozenShares
            , // pendingShares
                // enableClaimedAssets
        ) = svLedger.accountById(accountId);
        assertEq(frozenShares, withdrawShares);
    }

    function testProtocolVaultSPWithdraw() public {
        uint256 nativeFee = getEstimateFee(PayloadType.SP_WITHDRAW);
        uint256 shares = 100e6;
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);

        //Initialize
        svLedger.setFundSshares(spId, shares);
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
        StrategyFund memory sf = svLedger.getStrategyFund(spId);

        assertEq(sf.frozenShares, withdrawShares);
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

        //LZ
        // vm.expectRevert(NotEnoughWithdrawShare.selector);

        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
    }

    function testLPClaim() public {
        //update user claim info
        uint256 assetDecimal = 1e6;
        uint256 periodId;
        bytes32 vaultId;

        UpdateUserClaim[] memory updateUserClaims = new UpdateUserClaim[](2);
        updateUserClaims[0] =
            UpdateUserClaim({userId: userA_id, amount: 1000 * assetDecimal, requestId: keccak256(abi.encode(1))});

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, updateUserClaims);
        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);

        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, updateUserClaims, signature);

        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        UserClaimedInfo memory userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo_A.unClaimedAssets, 1000 * assetDecimal);
        assertEq(userClaimedInfo_A.requestIds[0], keccak256(abi.encode(1)));

        //LP claim
        mockToken.mint(address(protocolVault), 100000e6);
        uint256 amount = 100e6;

        ClaimParams memory claimParams =
            ClaimParams({roleType: RoleType.LP, token: address(mockToken), amount: amount, brokerHash: ORDERLY_BROKER});
        vm.prank(userA);
        protocolVault.claim(claimParams);
    }

    function testRevertProtocolVaultLPDepositWithoutVaule() public {
        //deal eth to cc contract on ledger
        vm.deal(address(aVaultCrossChainManager), 10 ether);

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

        vm.expectRevert(NotEnoughFee.selector);
        protocolVault.deposit{value: 0}(depositParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);
        (
            , // accountId
            uint256 assets, // assets
            , // shares
            uint256 unAllocatedAssets,
            , // frozenShares
            , // pendingShares
                // enableClaimedAssets
        ) = svLedger.accountById(accountId);

        assertEq(unAllocatedAssets, 0);
        assertEq(assets, 0);
    }
}
