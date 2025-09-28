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
import {UserClaimedInfo, RoleType, ClaimParams} from "../../contracts/ProtocolVault.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {StrategyVaultCCMessage, PayloadType} from "../../contracts/lib/types/CrossChainStruct.sol";

contract ProtocolVaultTest is Base {
    // Contract-specific errors (not related to ledger implementation)
    error NotEnoughCCFee();
    error InvalidClaimToken(address token);
    error NotEnoughUnclaimedAssets(uint256 amount);

    uint256 shareDecimal = 1e6;
    uint256 assetDecimal = 1e6;
    uint256 priceDecimal = 1e6;
    uint256 periodId;
    bytes32 vaultId;

    bytes32[] public spIds;

    function setUp() public override {
        super.setUp();
        spIds.push(spA_id);
        spIds.push(spB_id);
    }

    function testSetOperator() public {
        vm.prank(owner);
        svLedger.setOperatorManager(operator);
    }

    function testGetCCFee() public {
        ClaimInfo[] memory userClaimInfos = new ClaimInfo[](1);
        //fill userClaimInfos[0]
        userClaimInfos[0] = ClaimInfo({
            requestId: keccak256(abi.encode(0)),
            accountId: userA_id,
            strategyProviderId: spA_id,
            assets: 1000 * assetDecimal
        });
        bytes memory payload = abi.encode(1, 100, userClaimInfos);
        console.logBytes(payload);

        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: PayloadType.ASSETS_DISTRIBUTION,
            srcChainId: 291,
            dstChainId: 42161,
            payload: "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e56308ebb1554556e92cdfbd346e3a4f5bc7898eaa8e3f0151919b4df433e900df707c3c3a62e6b14b3017c0c347bf113e6fa9c4bbfc118b66bf02c9366b2ba12e97000000000000000000000000000000000000000000000000000000003b9aca00"
        });
    }

    function testWithdrawETHFromCCManager() public {
        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        vm.prank(owner);
        bVaultCrossChainManager.withdrawNativeToken(payable(owner), 10 ether);
        assertEq(address(bVaultCrossChainManager).balance, 0);
        assertEq(owner.balance, 10 ether);
    }

    function testDistributeAssetsToOneChain() public {
        uint256 amount = 1000 * assetDecimal;
        AssetsDistribution[] memory assetsDistributions = new AssetsDistribution[](1);
        assetsDistributions[0] = AssetsDistribution({chainId: evmChainId, assets: amount});

        bytes memory signature = _getDistributeAssetsSignature(periodId, vaultId, assetsDistributions);

        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        //mint token
        mockToken.mint(address(protocolVault), amount);
        vm.startPrank(operator);
        uint256 gasBefore = gasleft();
        svLedger.distributeAssets(periodId, vaultId, assetsDistributions, signature);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console.log("Gas used:", gasUsed);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        assertEq(mockDexVault.amount(), amount);
        uint256 balance = address(bVaultCrossChainManager).balance;
        console.log("cc fee:", 10 * 10 ** 18 - balance);
    }

    function testRevertWithTwiceCallDistributeAssets() public {
        uint256 amount = 1000 * assetDecimal;
        AssetsDistribution[] memory assetsDistributions = new AssetsDistribution[](1);
        assetsDistributions[0] = AssetsDistribution({chainId: evmChainId, assets: amount});

        bytes memory signature = _getDistributeAssetsSignature(periodId, vaultId, assetsDistributions);

        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        vm.startPrank(operator);

        svLedger.distributeAssets(periodId, vaultId, assetsDistributions, signature);

        //revert
        vm.expectRevert(ILedgerCoreImpl.AlreadyCalled.selector);
        svLedger.distributeAssets(periodId, vaultId, assetsDistributions, signature);
        vm.stopPrank();
    }

    function testSpecialDecimalDistributeAssetsToOneChain() public {
        //set special decimal
        vm.prank(owner);
        aVaultCrossChainManager.setSpecialTokenDecimal(USDC_HASH, evmChainId, 18);

        uint256 amount = 1000 * assetDecimal;
        AssetsDistribution[] memory assetsDistributions = new AssetsDistribution[](1);
        assetsDistributions[0] = AssetsDistribution({chainId: evmChainId, assets: amount});

        bytes memory signature = _getDistributeAssetsSignature(periodId, vaultId, assetsDistributions);

        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        //mint token
        mockToken.mint(address(protocolVault), 1000 * 10 ** 18);

        vm.startPrank(operator);
        svLedger.distributeAssets(periodId, vaultId, assetsDistributions, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        uint256 convertedAmount = 1000e18;
        assertEq(mockDexVault.amount(), convertedAmount);
    }

    function testUpdateUnclaimed() public {
        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);

        //deal eth to cc contract on ledger
        uint256 asset = 1000 * assetDecimal;
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        svLedger.setLpClaimInfo(requestIds[0], userA_id, asset);
        svLedger.setLpClaimInfo(requestIds[1], userB_id, asset);

        vm.startPrank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);

        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        UserClaimedInfo memory userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo_A.unClaimedAssets, asset);
        assertEq(userClaimedInfo_A.requestIds[0], keccak256(abi.encode(0)));

        UserClaimedInfo memory userClaimedInfo_B = protocolVault.getUserClaimedInfo(userB_id);
        assertEq(userClaimedInfo_B.unClaimedAssets, asset);
        assertEq(userClaimedInfo_B.requestIds[0], keccak256(abi.encode(1)));
    }

    function testEstimateUpdateUnclaimed() public {
        bytes32[] memory requestIds = new bytes32[](3);
        for (uint256 i = 0; i < requestIds.length; i++) {
            requestIds[i] = keccak256(abi.encode(i));
        }

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);

        //deal eth to cc contract on ledger
        uint256 asset = 1000 * assetDecimal;
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        for (uint256 i = 0; i < requestIds.length; i++) {
            svLedger.setLpClaimInfo(requestIds[i], userA_id, asset);
        }

        vm.startPrank(operator);
        uint256 gasBefore = gasleft();
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console.log("Gas used:", gasUsed);
        verifyPackets(srcEid, address(aVaultCrossChainManager));
    }

    function testClaimWithCrosschainFee() public {
        // Setup: Create a withdrawal that needs to be claimed
        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);

        // Set up the claim info on the ledger
        uint256 asset = 1000 * assetDecimal;
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        svLedger.setLpClaimInfo(requestIds[0], userA_id, asset);
        svLedger.setLpClaimInfo(requestIds[1], userB_id, asset);

        // Process the unclaimed assets update
        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        // Verify ccFee is recorded correctly
        UserClaimedInfo memory userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo_A.unClaimedAssets, asset);
        uint256 ccFeePerUser = protocolVault.crossChainFee(userA_id);
        console.log("Cross-chain fee per user:", ccFeePerUser);
        // User A claims with correct fee
        mockToken.mint(address(protocolVault), asset * 2);

        vm.deal(userA, ccFeePerUser);
        ClaimParams memory claimParams =
            ClaimParams({roleType: RoleType.LP, token: address(mockToken), brokerHash: ORDERLY_BROKER});
        uint256 usdcBalanceBefore = mockToken.balanceOf(userA);

        vm.prank(userA);
        protocolVault.claimWithFee{value: ccFeePerUser}(claimParams);

        uint256 usdcBalanceAfter = mockToken.balanceOf(userA);

        // Verify user received the assets
        assertEq(usdcBalanceAfter - usdcBalanceBefore, asset, "User should receive the correct amount of assets");

        // Verify the claim state is reset
        userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo_A.unClaimedAssets, 0, "Unclaimed assets should be reset to 0");
        assertEq(userClaimedInfo_A.requestIds.length, 0, "Request IDs should be cleared");

        // Check that the protocol vault has received the cross-chain fee
        assertEq(address(protocolVault).balance, ccFeePerUser, "Protocol vault should receive the cross-chain fee");
    }

    function testUpdateUnclaimedCrossChainFeeAccumulate() public {
        // Setup: Create a withdrawal that needs to be claimed
        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);

        // Set up the claim info on the ledger
        uint256 asset = 1000 * assetDecimal;
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        svLedger.setLpClaimInfo(requestIds[0], userA_id, asset);
        svLedger.setLpClaimInfo(requestIds[1], userA_id, asset);

        // Process the unclaimed assets update
        vm.prank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        // Verify ccFee is recorded correctly
        UserClaimedInfo memory userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        uint256 ccFeePerUser = protocolVault.crossChainFee(userA_id);
        console.log("Cross-chain fee per user:", ccFeePerUser);
        assertEq(userClaimedInfo_A.unClaimedAssets, asset * 2);
    }

    function testSpecialDecimalUpdateUnclaimed() public {
        //set special decimal
        vm.prank(owner);
        aVaultCrossChainManager.setSpecialTokenDecimal(USDC_HASH, evmChainId, 18);

        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = keccak256(abi.encode(0));
        requestIds[1] = keccak256(abi.encode(1));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);

        //deal eth to cc contract on ledger
        uint256 asset = 1000 * assetDecimal;
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        svLedger.setLpClaimInfo(requestIds[0], userA_id, asset);
        svLedger.setLpClaimInfo(requestIds[1], userB_id, asset);

        vm.startPrank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);

        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //check
        uint256 convertedAmount = 1000e18;

        UserClaimedInfo memory userClaimedInfo_A = protocolVault.getUserClaimedInfo(userA_id);
        assertEq(userClaimedInfo_A.unClaimedAssets, convertedAmount);
        assertEq(userClaimedInfo_A.requestIds[0], keccak256(abi.encode(0)));

        UserClaimedInfo memory userClaimedInfo_B = protocolVault.getUserClaimedInfo(userB_id);
        assertEq(userClaimedInfo_B.unClaimedAssets, convertedAmount);
        assertEq(userClaimedInfo_B.requestIds[0], keccak256(abi.encode(1)));
    }

    function testRepeatClaim() public {
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256(abi.encode(0));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        //deal eth to cc contract on ledger
        uint256 asset = 1000 * assetDecimal;
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        svLedger.setLpClaimInfo(requestIds[0], userA_id, asset);

        vm.startPrank(operator);
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);
        verifyPackets(srcEid, address(aVaultCrossChainManager));

        //repeat requestId
        bytes32[] memory newRequestIds = new bytes32[](2);
        newRequestIds[0] = keccak256(abi.encode(0));
        newRequestIds[1] = keccak256(abi.encode(1));
        svLedger.setLpClaimInfo(newRequestIds[1], userB_id, asset);

        bytes memory new_signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, newRequestIds);

        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, newRequestIds, new_signature);
    }

    function testClaimZero() public {
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256(abi.encode(0));

        bytes memory signature = _getUpdateUnclaimedSignature(evmChainId, periodId, vaultId, requestIds);
        //deal eth to cc contract on ledger
        vm.deal(address(bVaultCrossChainManager), 10 ether);
        svLedger.setLpClaimInfo(requestIds[0], userA_id, 0);

        vm.startPrank(operator);
        //will not happen cc
        svLedger.updateUnclaimed(evmChainId, periodId, vaultId, requestIds, signature);
    }

    function testUpgradeFundAssetsSignature() public {
        initialize();
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](2);

        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 1000 * assetDecimal);
        strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

        bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);

        vm.startPrank(operator);
        svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);
    }

    function testRevertWithTwiceCallPpdateStrategyFundAssets() public {
        initialize();
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](2);

        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 1000 * assetDecimal);
        strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

        bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);

        vm.startPrank(operator);
        svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

        //revert
        vm.expectRevert(ILedgerCoreImpl.AlreadyCalled.selector);
        svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);
    }

    function testRevertWithTwiceCallAllocateFunds() public {
        bytes memory signature = _getALlocateFundsSig(periodId, vaultId, spIds);
        vm.prank(operator);
        svLedger.allocateToFunds(periodId, vaultId, spIds, signature);

        //revert
        vm.expectRevert(ILedgerCoreImpl.AlreadyCalled.selector);
        vm.prank(operator);
        svLedger.allocateToFunds(periodId, vaultId, spIds, signature);
    }

    function testEstimateUpdateLpGas() public {
        //mock
        uint256 lpDeposit = 1000 * assetDecimal;
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = userA_id;
        svLedger.setAccountUnAllocatedAssets(accountIds, lpDeposit);

        UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](1000);
        uint256 depositAmount = 1 * assetDecimal;
        uint256 requestId;
        for (uint256 i = 0; i < updateLedgerParams.length; i++) {
            Operation memory newOperation =
                Operation({id: userA_id, requestId: keccak256(abi.encode(requestId)), amount: depositAmount});
            updateLedgerParams[i] =
                UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: newOperation});
            requestId++;
        }
        bytes memory signature = _getUpdateLPAndStrategyFundSig(periodId, vaultId, updateLedgerParams);

        uint256 gasBefore = gasleft();
        vm.prank(operator);
        svLedger.updateLPAndStrategyFund(periodId, vaultId, updateLedgerParams, signature);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console.log("Gas used:", gasUsed);
    }

    function testEstimateSettleAccounts() public {
        bytes32[] memory accountIds = new bytes32[](600);
        for (uint256 i = 0; i < accountIds.length; i++) {
            accountIds[i] = userA_id;
        }

        svLedger.setAccountPendingShares(accountIds, 10 * shareDecimal);

        bytes memory signature = _getSettleAccountSig(periodId, vaultId, accountIds);
        uint256 gasBefore = gasleft();
        vm.prank(operator);
        svLedger.settleAccounts(periodId, vaultId, accountIds, signature);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console.log("Gas used:", gasUsed);
    }

    function testUpdateLedger() public {
        initialize();
        bytes32[] memory accountIds = new bytes32[](1);
        bytes32[] memory strategyProviderIds = new bytes32[](2);
        accountIds[0] = userA_id;

        strategyProviderIds[0] = spA_id;
        strategyProviderIds[1] = spB_id;

        uint256 initVault = 1000000 * assetDecimal;
        svLedger.setAccountState(userA_id, initVault, initVault, initVault);
        svLedger.setSPUnallocatedAssets(strategyProviderIds, initVault);
        svLedger.setSPUnallocatedShares(strategyProviderIds, initVault);
        consolePendingState();

        //Period 1
        console.log("=============Start Period 1=====================");
        vm.startPrank(operator);

        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](2);
        {
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 1000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);
            uint256 depositAmount = 500 * assetDecimal;
            uint256 withdrawShare = 6 * shareDecimal / 10; //0.6 shares
            uint256 spDepositAmount = 800 * assetDecimal;
            {
                Operation memory newOperation_1 = Operation({id: userA_id, requestId: 0, amount: depositAmount});
                Operation memory newOperation_2 =
                    Operation({id: userA_id, requestId: keccak256(abi.encode(1)), amount: withdrawShare});
                Operation memory newOperation_3 =
                    Operation({id: spB_id, requestId: keccak256(abi.encode(2)), amount: spDepositAmount});

                //initialize UpdateLedgerParams dymnamic arrary
                UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](3);

                updateLedgerParams[0] =
                    UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: newOperation_1});
                updateLedgerParams[1] =
                    UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: newOperation_2});
                updateLedgerParams[2] =
                    UpdateLedgerParams({operationType: OperationType.SP_DEPOSIT, operation: newOperation_3});

                signature = _getUpdateLPAndStrategyFundSig(periodId, vaultId, updateLedgerParams);
                svLedger.updateLPAndStrategyFund(periodId, vaultId, updateLedgerParams, signature);
            }

            signature = _getALlocateFundsSig(periodId, vaultId, strategyProviderIds);
            svLedger.allocateToFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
            svLedger.settleMainAndStrategyFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleAccountSig(periodId, vaultId, accountIds);
            svLedger.settleAccounts(periodId, vaultId, accountIds, signature);
            console.log("=============After Period 1=====================");
            consoleState();

            signature = _getUpdatePeriodIdSig(periodId, vaultId);
            uint256 gasBefore = gasleft();
            svLedger.updatePeriodId(periodId, vaultId, signature);
            uint256 gasAfter = gasleft();
            uint256 gasUsed = gasBefore - gasAfter;
            console.log("Gas used:", gasUsed);
        }
        //Period 2
        console.log("=============Start Period 2=====================");
        {
            //initialize
            periodId++;
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 5000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1250 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

            signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
            svLedger.settleMainAndStrategyFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleAccountSig(periodId, vaultId, accountIds);
            svLedger.settleAccounts(periodId, vaultId, accountIds, signature);

            console.log("=============After Period 2=====================");
            consoleState();

            signature = _getUpdatePeriodIdSig(periodId, vaultId);
            svLedger.updatePeriodId(periodId, vaultId, signature);
        }
        //Period 3
        console.log("=============Start Period 3=====================");
        {
            //initialize
            periodId++;

            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 750 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

            uint256 depositAmount = 10000 * assetDecimal;
            uint256 withdrawShare = 1 * shareDecimal;
            Operation memory newOperation_1 =
                Operation({id: userA_id, requestId: keccak256(abi.encode(3)), amount: depositAmount});
            Operation memory newOperation_2 =
                Operation({id: spB_id, requestId: keccak256(abi.encode(4)), amount: withdrawShare});

            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](2);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: newOperation_1});
            updateLedgerParams[1] =
                UpdateLedgerParams({operationType: OperationType.SP_WITHDRAW, operation: newOperation_2});

            signature = _getUpdateLPAndStrategyFundSig(periodId, vaultId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, vaultId, updateLedgerParams, signature);

            signature = _getALlocateFundsSig(periodId, vaultId, strategyProviderIds);
            svLedger.allocateToFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
            svLedger.settleMainAndStrategyFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleAccountSig(periodId, vaultId, accountIds);
            svLedger.settleAccounts(periodId, vaultId, accountIds, signature);

            console.log("=============After Period 3=====================");
            consoleState();

            signature = _getUpdatePeriodIdSig(periodId, vaultId);
            svLedger.updatePeriodId(periodId, vaultId, signature);
        }
        {
            //Period 4
            periodId++;
            console.log("=============Start Period 4=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 5000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);

            svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

            uint256 withdrawShare = 8 * shareDecimal;
            Operation memory newOperation_1 =
                Operation({id: userA_id, requestId: keccak256(abi.encode(5)), amount: withdrawShare});
            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](1);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: newOperation_1});

            signature = _getUpdateLPAndStrategyFundSig(periodId, vaultId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, vaultId, updateLedgerParams, signature);

            signature = _getALlocateFundsSig(periodId, vaultId, strategyProviderIds);
            svLedger.allocateToFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
            svLedger.settleMainAndStrategyFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleAccountSig(periodId, vaultId, accountIds);
            svLedger.settleAccounts(periodId, vaultId, accountIds, signature);

            console.log("=============After Period 4=====================");
            consoleState();
            signature = _getUpdatePeriodIdSig(periodId, vaultId);
            svLedger.updatePeriodId(periodId, vaultId, signature);
        }
        {
            //Period 5
            periodId++;
            console.log("=============Start Period 5=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 10750 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

            signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
            svLedger.settleMainAndStrategyFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleAccountSig(periodId, vaultId, accountIds);
            svLedger.settleAccounts(periodId, vaultId, accountIds, signature);
            console.log("=============After Period 5=====================");
            consoleState();

            signature = _getUpdatePeriodIdSig(periodId, vaultId);
            svLedger.updatePeriodId(periodId, vaultId, signature);
        }
        {
            //Period 6
            periodId++;
            console.log("=============Start Period 6=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 6000 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

            uint256 depositAssets = 10000 * assetDecimal;
            Operation memory newOperation_1 =
                Operation({id: spA_id, requestId: keccak256(abi.encode(6)), amount: depositAssets});
            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](1);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.SP_DEPOSIT, operation: newOperation_1});

            signature = _getUpdateLPAndStrategyFundSig(periodId, vaultId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, vaultId, updateLedgerParams, signature);

            signature = _getALlocateFundsSig(periodId, vaultId, strategyProviderIds);
            svLedger.allocateToFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
            svLedger.settleMainAndStrategyFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleAccountSig(periodId, vaultId, accountIds);
            svLedger.settleAccounts(periodId, vaultId, accountIds, signature);
            console.log("=============After Period 6=====================");
            consoleState();

            signature = _getUpdatePeriodIdSig(periodId, vaultId);
            svLedger.updatePeriodId(periodId, vaultId, signature);
        }
        {
            //Period 7
            periodId++;
            console.log("=============Start Period 7=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 4000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

            uint256 withdrawShare = 9 * shareDecimal / 10;
            Operation memory newOperation_1 =
                Operation({id: spA_id, requestId: keccak256(abi.encode(7)), amount: withdrawShare});
            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](1);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.SP_WITHDRAW, operation: newOperation_1});

            signature = _getUpdateLPAndStrategyFundSig(periodId, vaultId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, vaultId, updateLedgerParams, signature);

            signature = _getALlocateFundsSig(periodId, vaultId, strategyProviderIds);
            svLedger.allocateToFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
            svLedger.settleMainAndStrategyFunds(periodId, vaultId, spIds, signature);

            signature = _getSettleAccountSig(periodId, vaultId, accountIds);
            svLedger.settleAccounts(periodId, vaultId, accountIds, signature);
            console.log("=============After Period 7=====================");
            consoleState();

            signature = _getUpdatePeriodIdSig(periodId, vaultId);
            svLedger.updatePeriodId(periodId, vaultId, signature);
        }
    }

    function testInitializeVault() public {
        //mock deposit
        uint256 lpDeposit = 100 * assetDecimal;
        uint256 spDeposit = 1000 * assetDecimal;
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = userA_id;
        svLedger.setAccountUnAllocatedAssets(accountIds, lpDeposit);

        bytes32[] memory strategyProviderIds = new bytes32[](1);
        strategyProviderIds[0] = spA_id;
        svLedger.setSPUnallocatedAssets(strategyProviderIds, spDeposit);

        //update fund assets
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](1);

        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 0);

        bytes memory signature = _getUploadFundAssetsSignature(periodId, vaultId, strategyFundAssets);
        vm.startPrank(operator);
        svLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);

        assertEq(svLedger.mainAssetsAfterFee(), 0);

        //update
        UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](2);

        Operation memory newOperation_1 = Operation({id: userA_id, requestId: 0, amount: lpDeposit});
        Operation memory newOperation_2 =
            Operation({id: spA_id, requestId: keccak256(abi.encode(1)), amount: spDeposit});

        updateLedgerParams[0] = UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: newOperation_1});
        updateLedgerParams[1] = UpdateLedgerParams({operationType: OperationType.SP_DEPOSIT, operation: newOperation_2});

        signature = _getUpdateLPAndStrategyFundSig(periodId, vaultId, updateLedgerParams);
        svLedger.updateLPAndStrategyFund(periodId, vaultId, updateLedgerParams, signature);

        assertEq(svLedger.pendingMainShares(), lpDeposit);

        //allocate funds

        signature = _getALlocateFundsSig(periodId, vaultId, strategyProviderIds);
        svLedger.allocateToFunds(periodId, vaultId, strategyProviderIds, signature);

        StrategyFundToken memory strategyFund = svLedger.getStrategyFund(spA_id);
        assertEq(strategyFund.pendingState.pendingTotalAssets, spDeposit + lpDeposit);
        assertEq(strategyFund.pendingState.pendingMainShares, lpDeposit);

        //settle

        signature = _getSettleMainAndFundSig(periodId, vaultId, strategyProviderIds);
        svLedger.settleMainAndStrategyFunds(periodId, vaultId, strategyProviderIds, signature);

        strategyFund = svLedger.getStrategyFund(spA_id);
        assertEq(svLedger.mainShares(), lpDeposit);
        assertEq(strategyFund.totalAssets, spDeposit + lpDeposit);
        assertEq(strategyFund.mainShares, lpDeposit);
        assertEq(strategyFund.strategyProviderShares, spDeposit);
        assertEq(strategyFund.totalShares, spDeposit + lpDeposit);
        assertEq(strategyFund.hwm, 1 * assetDecimal);
    }

    function initialize() public {
        uint256 mainshares = 1 * shareDecimal;

        uint256[] memory StrategyFundsAssets = new uint256[](2);
        StrategyFundsAssets[0] = 2000 * assetDecimal;
        StrategyFundsAssets[1] = 2000 * assetDecimal;

        uint256[] memory mainSharesInFund = new uint256[](2);
        mainSharesInFund[0] = 1 * shareDecimal;
        mainSharesInFund[1] = 1 * shareDecimal;

        uint256[] memory spSharesInFund = new uint256[](2);
        spSharesInFund[0] = 1 * shareDecimal;
        spSharesInFund[1] = 1 * shareDecimal;
        //initialize
        svLedger.initializeStrategyFund(
            mainshares, spIds, mainSharesInFund, spSharesInFund, StrategyFundsAssets, 1000 * priceDecimal
        );
    }

    function consolePendingState() public view {
        StrategyFundToken memory strategyFundA = svLedger.getStrategyFund(spA_id);
        StrategyFundToken memory strategyFundB = svLedger.getStrategyFund(spB_id);

        console.log("Total Assets A: %d", strategyFundA.pendingState.pendingTotalAssets);
        console.log("Total Assets B: %d", strategyFundB.pendingState.pendingTotalAssets);

        console.log("Total Main Shares: %d", svLedger.pendingMainShares());
        console.log("Main Share in Fund A: %d", strategyFundA.pendingState.pendingMainShares);
        console.log("Main Share in Fund B: %d", strategyFundB.pendingState.pendingMainShares);

        console.log("SP A shares in Fund A: %d", strategyFundA.pendingState.pendingStrategyProviderShares);
        console.log("SP B shares in Fund B: %d", strategyFundB.pendingState.pendingStrategyProviderShares);

        console.log("Total Shares A: %d", strategyFundA.pendingState.pendingTotalShares);
        console.log("Total Shares B: %d", strategyFundB.pendingState.pendingTotalShares);

        uint256[] memory hwms = new uint256[](spIds.length);

        hwms = svLedger.getFundHWM(spIds);

        console.log("HWM A: %d", hwms[0]);
        console.log("HWM B: %d", hwms[1]);
    }

    function consoleState() public view {
        StrategyFundToken memory strategyFundA = svLedger.getStrategyFund(spA_id);
        StrategyFundToken memory strategyFundB = svLedger.getStrategyFund(spB_id);

        console.log("Total Assets A: %d", strategyFundA.totalAssets);
        console.log("Total Assets B: %d", strategyFundB.totalAssets);

        console.log("Total Main Shares: %d", svLedger.mainShares());
        console.log("Main Share in Fund A: %d", strategyFundA.mainShares);
        console.log("Main Share in Fund B: %d", strategyFundB.mainShares);

        console.log("SP A shares in Fund A: %d", strategyFundA.strategyProviderShares);
        console.log("SP B shares in Fund B: %d", strategyFundB.strategyProviderShares);

        console.log("Total Shares A: %d", strategyFundA.totalShares);
        console.log("Total Shares B: %d", strategyFundB.totalShares);

        console.log("HWM A: %d", strategyFundA.hwm);
        console.log("HWM B: %d", strategyFundB.hwm);
    }

    function testRemoveInvalidFrozenShares() public {
        // Initialize: Set frozen shares for LP and SP
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = userA_id;
        uint256 lpFrozenShares = 5 * shareDecimal;
        svLedger.setAccountFrozenShares(accountIds, lpFrozenShares);

        bytes32[] memory strategyProviderIds = new bytes32[](1);
        strategyProviderIds[0] = spA_id;
        uint256 spFrozenShares = 10 * shareDecimal;
        svLedger.setSPFrozenShares(strategyProviderIds, spFrozenShares);

        // Create parameters for removing frozen shares
        UpdateLedgerParams[] memory params = new UpdateLedgerParams[](2);

        // LP withdraw frozen shares removal
        Operation memory lpOperation =
            Operation({id: userA_id, requestId: keccak256(abi.encode("lpWithdraw")), amount: 2 * shareDecimal});
        params[0] = UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: lpOperation});

        // SP withdraw frozen shares removal
        Operation memory spOperation =
            Operation({id: spA_id, requestId: keccak256(abi.encode("spWithdraw")), amount: 3 * shareDecimal});
        params[1] = UpdateLedgerParams({operationType: OperationType.SP_WITHDRAW, operation: spOperation});

        // Sign the transaction
        bytes memory signature = _getRemoveInvalidFrozenSharesSignature(vaultId, params);

        // Execute removeInvalidFrozenShares
        vm.prank(operator);
        svLedger.removeInvalidFrozenShares(vaultId, params, signature);

        // Verify LP frozen shares decreased
        assertEq(svLedger.getAccountFrozenShares(userA_id), lpFrozenShares - 2 * shareDecimal);

        // Verify SP frozen shares decreased
        assertEq(svLedger.getSPFrozenShares(spA_id), spFrozenShares - 3 * shareDecimal);
    }

    function testRemoveInvalidFrozenSharesIdempotency() public {
        // Initialize: Set frozen shares
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = userA_id;
        uint256 lpFrozenShares = 5 * shareDecimal;
        svLedger.setAccountFrozenShares(accountIds, lpFrozenShares);

        // Create operation parameters
        UpdateLedgerParams[] memory params = new UpdateLedgerParams[](1);
        Operation memory lpOperation =
            Operation({id: userA_id, requestId: keccak256(abi.encode("lpWithdraw")), amount: 2 * shareDecimal});
        params[0] = UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: lpOperation});

        bytes memory signature = _getRemoveInvalidFrozenSharesSignature(vaultId, params);

        // First call
        vm.prank(operator);
        svLedger.removeInvalidFrozenShares(vaultId, params, signature);

        // Verify shares decreased
        assertEq(svLedger.getAccountFrozenShares(userA_id), lpFrozenShares - 2 * shareDecimal);

        // Second call with the same request, should not decrease shares again
        vm.prank(operator);
        svLedger.removeInvalidFrozenShares(vaultId, params, signature);

        // Verify shares did not decrease further
        assertEq(svLedger.getAccountFrozenShares(userA_id), lpFrozenShares - 2 * shareDecimal);
    }

    function testRevertRemoveInvalidFrozenSharesNotEnoughShares() public {
        // Initialize: Set small frozen shares
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = userA_id;
        uint256 lpFrozenShares = 1 * shareDecimal;
        svLedger.setAccountFrozenShares(accountIds, lpFrozenShares);

        // Create operation parameters, attempting to remove more than actual frozen amount
        UpdateLedgerParams[] memory params = new UpdateLedgerParams[](1);
        Operation memory lpOperation = Operation({
            id: userA_id,
            requestId: keccak256(abi.encode("lpWithdraw")),
            amount: 2 * shareDecimal // More than actual frozen amount
        });
        params[0] = UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: lpOperation});

        bytes memory signature = _getRemoveInvalidFrozenSharesSignature(vaultId, params);

        // Expected to fail due to insufficient shares
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(LedgerUtils.NotEnoughFrozenShare.selector, 2 * shareDecimal));
        svLedger.removeInvalidFrozenShares(vaultId, params, signature);
    }

    function testRevertRemoveInvalidFrozenSharesInvalidType() public {
        // Initialize
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = userA_id;
        svLedger.setAccountFrozenShares(accountIds, 5 * shareDecimal);

        // Create invalid operation type
        UpdateLedgerParams[] memory params = new UpdateLedgerParams[](1);
        Operation memory lpOperation =
            Operation({id: userA_id, requestId: keccak256(abi.encode("lpDeposit")), amount: 2 * shareDecimal});
        params[0] = UpdateLedgerParams({
            operationType: OperationType.LP_DEPOSIT, // Using incorrect operation type
            operation: lpOperation
        });

        bytes memory signature = _getRemoveInvalidFrozenSharesSignature(vaultId, params);

        // Expected to fail due to invalid operation type
        vm.prank(operator);
        vm.expectRevert(ILedgerExtension.InvalidType.selector);
        svLedger.removeInvalidFrozenShares(vaultId, params, signature);
    }

    function _getRemoveInvalidFrozenSharesSignature(bytes32 _vaultId, UpdateLedgerParams[] memory params)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(_vaultId, params));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

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

    function _getSettleAccountSig(uint256 _periodId, bytes32 _vaultId, bytes32[] memory accountIds)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId, accountIds));
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

    function testDistributeSig() public pure {
        AssetsDistribution[] memory assetsDistributions = new AssetsDistribution[](1);
        assetsDistributions[0] = AssetsDistribution({chainId: 11155111, assets: 20000});

        bytes32 _vaultId = 0x0557859bbf4cd066a1afddf7899147516ea4e73f48928b58551caf5db46a5c9e;
        uint256 _periodId = 2;

        bytes32 messageHash = keccak256(abi.encode(_periodId, _vaultId, assetsDistributions));
        console.logBytes(abi.encode(_periodId, _vaultId, assetsDistributions));
        console.logBytes32(messageHash);
    }
}
