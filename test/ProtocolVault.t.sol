// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";

import {
    VaultType,
    RoleType,
    DepositParams,
    WithdrawParams,
    OperationData,
    UserClaimedInfo
} from "../contracts/lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "../contracts/lib/types/CrossChainStruct.sol";
import {Account, StrategyFund} from "../contracts/lib/types/LedgerStruct.sol";

contract TestProtocolVault is Base {
    function setUp() public override {
        super.setUp();
    }

    function testInitialize() public view {
        // Check initial state
        assertEq(protocolVault.ledgerChainId(), 291);
        assertEq(protocolVault.crossChainManager(), address(aVaultCrossChainManager));

        assertEq(svLedger.crossChainManagerAddress(), address(bVaultCrossChainManager));

        assertEq(bVaultCrossChainManager.ledger(), address(svLedger));

        assertEq(aVaultCrossChainManager.eid(), 1);
        assertEq(bVaultCrossChainManager.eid(), 2);
        assertEq(aVaultCrossChainManager.dstEid(), 2);
        assertEq(bVaultCrossChainManager.dstEid(), 1);
    }

    function testProtocolVaultLPDeposit() public {
        uint256 nativeFee = getEstimateFee();
        uint256 amount = 100e6;
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: user,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
        // Call deposit function
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
        uint256 nativeFee = getEstimateFee();
        uint256 amount = 100e6;
        DepositParams memory depositParams = DepositParams({
            payloadType: PayloadType.SP_DEPOSIT,
            receiver: sp,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });

        console.logAddress(address(protocolVault));

        // Call deposit function
        protocolVault.deposit{value: nativeFee}(depositParams);

        //LZ
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        //Check
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);

        StrategyFund memory sf = svLedger.getStrategyFund(spId);
        assertEq(sf.unAllocatedAssets, amount);
    }
    // function testUserVaultDeposit public {}
}
