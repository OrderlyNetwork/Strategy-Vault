// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";
import {
    Account,
    StrategyFund,
    UpdateStrategyFundAssetsParams,
    StrategyExecutionParams,
    BasicInfo,
    PendingState,
    StrategyExecution,
    Operation,
    OperationType,
    OperationRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    UpdateUserClaim,
    AllocateFundRes,
    SettleType,
    StrategyFundState,
    SettleParams
} from "../contracts/StrategyVaultLedger.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract StrategyVaultLedgerTest is Base {
    uint256 shareDecimal = 1e6;
    uint256 assetDecimal = 1e6;
    uint256 priceDecimal = 1e6;
    uint256 periodId;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public spA = address(0x3);
    address public spB = address(0x4);

    bytes32 spA_id = keccak256(abi.encodePacked(spA));
    bytes32 spB_id = keccak256(abi.encodePacked(spB));
    bytes32 userA_id = keccak256(abi.encodePacked(userA));
    bytes32 userB_id = keccak256(abi.encodePacked(userB));

    bytes32[] public spIds;

    function setUp() public override {
        super.setUp();
        spIds.push(spA_id);
        spIds.push(spB_id);
    }

    //forge t --match-test testUpgradeFundAssetsSignature -vv
    function testUpgradeFundAssetsSignature() public {
        initialize();
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](2);

        strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 1000 * assetDecimal);
        strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);

        bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);

        vm.startPrank(operator);
        svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);
    }
    //forge t --match-test testUpdateLPAndStrategyFund -vv
    // function testUpdateLPAndStrategyFund() public {
    //     //initialize UpdateLedgerParams dymnamic arrary
    //     initialize();
    //     UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](3);
    //     Operation memory newOperation_1 = Operation({id: userA_id, nonce: 0, amount: 1});
    //     updateLedgerParams[0] = UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: newOperation_1});
    //     bytes32 messageHash = keccak256(abi.encode(periodId, updateLedgerParams));
    //     (uint8 v, bytes32 r, bytes32 s) =
    //         vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     vm.startPrank(operator);
    //     svLedger.updateLPAndStrategyFund(periodId, updateLedgerParams, signature);
    // }

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

            bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);
            uint256 depositAmount = 500 * assetDecimal;
            uint256 withdrawShare = 6 * shareDecimal / 10; //0.6 shares
            uint256 spDepositAmount = 800 * assetDecimal;

            Operation memory newOperation_1 = Operation({id: userA_id, nonce: 0, amount: depositAmount});
            Operation memory newOperation_2 = Operation({id: userA_id, nonce: 1, amount: withdrawShare});
            Operation memory newOperation_3 = Operation({id: spB_id, nonce: 2, amount: spDepositAmount});

            //initialize UpdateLedgerParams dymnamic arrary
            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](3);

            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: newOperation_1});
            updateLedgerParams[1] =
                UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: newOperation_2});
            updateLedgerParams[2] =
                UpdateLedgerParams({operationType: OperationType.SP_DEPOSIT, operation: newOperation_3});

            signature = _getUpdateLPAndStrategyFundSig(periodId, updateLedgerParams);
            svLedger.updateLPAndStrategyFund(periodId, updateLedgerParams, signature);

            svLedger.allocatToFunds(spIds);
            svLedger.settleMainAndStrategyFunds(periodId, spIds);
            svLedger.settleAccounts(periodId, accountIds);
            console.log("=============After Period 1=====================");
            consoleState();
            svLedger.updatePeriodId();
        }
        //Period 2
        console.log("=============Start Period 2=====================");
        {
            //initialize
            periodId++;
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 5000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1250 * assetDecimal);

            bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);
            svLedger.settleMainAndStrategyFunds(periodId, spIds);
            svLedger.settleAccounts(periodId, accountIds);
            console.log("=============After Period 2=====================");
            consoleState();
            svLedger.updatePeriodId();
        }
        //Period 3
        console.log("=============Start Period 3=====================");
        {
            //initialize
            periodId++;

            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 750 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);
            bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);

            uint256 depositAmount = 10000 * assetDecimal;
            uint256 withdrawShare = 1 * shareDecimal;
            Operation memory newOperation_1 = Operation({id: userA_id, nonce: 3, amount: depositAmount});
            Operation memory newOperation_2 = Operation({id: spB_id, nonce: 4, amount: withdrawShare});

            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](2);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.LP_DEPOSIT, operation: newOperation_1});
            updateLedgerParams[1] =
                UpdateLedgerParams({operationType: OperationType.SP_WITHDRAW, operation: newOperation_2});
            signature = _getUpdateLPAndStrategyFundSig(periodId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, updateLedgerParams, signature);

            svLedger.allocatToFunds(spIds);
            svLedger.settleMainAndStrategyFunds(periodId, spIds);
            svLedger.settleAccounts(periodId, accountIds);
            console.log("=============After Period 3=====================");
            consoleState();
            svLedger.updatePeriodId();
        }
        {
            //Period 4
            periodId++;
            console.log("=============Start Period 4=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 5000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);
            bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);

            svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);

            uint256 withdrawShare = 8 * shareDecimal;
            Operation memory newOperation_1 = Operation({id: userA_id, nonce: 5, amount: withdrawShare});
            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](1);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.LP_WITHDRAW, operation: newOperation_1});
            signature = _getUpdateLPAndStrategyFundSig(periodId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, updateLedgerParams, signature);
            svLedger.allocatToFunds(spIds);
            svLedger.settleMainAndStrategyFunds(periodId, spIds);
            svLedger.settleAccounts(periodId, accountIds);
            console.log("=============After Period 4=====================");
            consoleState();
            svLedger.updatePeriodId();
        }
        {
            //Period 5
            periodId++;
            console.log("=============Start Period 5=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 10750 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);
            bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);

            svLedger.settleMainAndStrategyFunds(periodId, spIds);
            svLedger.settleAccounts(periodId, accountIds);
            console.log("=============After Period 5=====================");
            consoleState();
            svLedger.updatePeriodId();
        }
        {
            //Period 6
            periodId++;
            console.log("=============Start Period 6=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 6000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);
            bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);

            uint256 depositAssets = 10000 * assetDecimal;
            Operation memory newOperation_1 = Operation({id: spA_id, nonce: 6, amount: depositAssets});
            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](1);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.SP_DEPOSIT, operation: newOperation_1});
            signature = _getUpdateLPAndStrategyFundSig(periodId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, updateLedgerParams, signature);
            svLedger.allocatToFunds(spIds);
            svLedger.settleMainAndStrategyFunds(periodId, spIds);
            svLedger.settleAccounts(periodId, accountIds);
            console.log("=============After Period 6=====================");
            consoleState();
            svLedger.updatePeriodId();
        }
        {
            //Period 7
            periodId++;
            console.log("=============Start Period 7=====================");
            strategyFundAssets[0] = UpdateStrategyFundAssetsParams(spA_id, 4000 * assetDecimal);
            strategyFundAssets[1] = UpdateStrategyFundAssetsParams(spB_id, 1000 * assetDecimal);
            bytes memory signature = _getUploadFundAssetsSignature(periodId, strategyFundAssets);
            svLedger.updateStrategyFundAssets(periodId, strategyFundAssets, signature);

            uint256 withdrawShare = 9 * shareDecimal / 10;
            Operation memory newOperation_1 = Operation({id: spA_id, nonce: 7, amount: withdrawShare});
            UpdateLedgerParams[] memory updateLedgerParams = new UpdateLedgerParams[](1);
            updateLedgerParams[0] =
                UpdateLedgerParams({operationType: OperationType.SP_WITHDRAW, operation: newOperation_1});
            signature = _getUpdateLPAndStrategyFundSig(periodId, updateLedgerParams);

            svLedger.updateLPAndStrategyFund(periodId, updateLedgerParams, signature);
            svLedger.allocatToFunds(spIds);
            svLedger.settleMainAndStrategyFunds(periodId, spIds);
            svLedger.settleAccounts(periodId, accountIds);
            console.log("=============After Period 7=====================");
            consoleState();
            svLedger.updatePeriodId();
        }
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
        StrategyFund memory strategyFundA = svLedger.getStrategyFund(spA_id);
        StrategyFund memory strategyFundB = svLedger.getStrategyFund(spB_id);

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
        StrategyFund memory strategyFundA = svLedger.getStrategyFund(spA_id);
        StrategyFund memory strategyFundB = svLedger.getStrategyFund(spB_id);

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

    function _getUploadFundAssetsSignature(
        uint256 _periodId,
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(_periodId, strategyFundAssets));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getUpdateLPAndStrategyFundSig(uint256 _periodId, UpdateLedgerParams[] memory updateUserLedgerParams)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(_periodId, updateUserLedgerParams));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }
}
