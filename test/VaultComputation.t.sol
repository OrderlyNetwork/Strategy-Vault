// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";
// import {VaultComputation} from "../contracts/utils/VaultComputation.sol";
// import {console} from "forge-std/console.sol";
// import {StrategyFund, SPOperation} from "../contracts/lib/Struct.sol";

// contract VaultComputationTest is Test {
//     VaultComputation vaultComputation;

//     uint256 shareDecimal = 1e6;
//     uint256 assetDecimal = 1e6;

//     address public userA = address(0x1);
//     address public userB = address(0x2);
//     address public spA = address(0x3);
//     address public spB = address(0x4);

//     bytes32 spA_id = keccak256(abi.encodePacked(spA));
//     bytes32 spB_id = keccak256(abi.encodePacked(spB));

//     bytes32[] public spIds;

//     function setUp() public {
//         //Deploy VaultComputation contract
//         vaultComputation = new VaultComputation();
//         spIds.push(spA_id);
//         spIds.push(spB_id);
//     }

//     function testVaultComputationInitialize() public view {
//         // Check initial state
//         assertEq(vaultComputation.shareDecimal(), 0);
//         assertEq(vaultComputation.assetsDecimal(), 0);
//     }

//     function testAssetToShare() public view {
//         //Case 0
//         uint256 amount = 1000 * assetDecimal;
//         uint256 shares = vaultComputation.convertToShares(amount, 0, 0);
//         assertEq(shares, amount);

//         uint256 totalAssets = 1000 * assetDecimal;
//         uint256 totalShares = 500 * shareDecimal;
//         //Case 1
//         amount = 500 * assetDecimal;
//         shares = vaultComputation.convertToShares(amount, totalAssets, totalShares);
//         assertEq(shares, amount * totalShares / totalAssets);
//         //Case 2
//         amount = 1 * assetDecimal;
//         shares = vaultComputation.convertToShares(amount, totalAssets, totalShares);
//         assertEq(shares, amount * totalShares / totalAssets);
//     }

//     function testShareToAsset() public view {
//         //Case 0
//         uint256 shares = 1000 * shareDecimal;
//         uint256 amount = vaultComputation.convertToAssets(shares, 0, 0);
//         assertEq(amount, shares * assetDecimal / shareDecimal);

//         uint256 totalAssets = 1000 * assetDecimal;
//         uint256 totalShares = 500 * shareDecimal;

//         //Case 1
//         shares = 500 * shareDecimal;
//         amount = vaultComputation.convertToAssets(shares, totalAssets, totalShares);
//         assertEq(amount, shares * totalAssets / totalShares);
//         //Case 2
//         shares = 1 * shareDecimal;
//         amount = vaultComputation.convertToAssets(shares, totalAssets, totalShares);
//         assertEq(amount, shares * totalAssets / totalShares);
//     }

//     function testInitialize() public {
//         initialize();
//     }

//     function testUserDepositDistribution() public view {
//         // uint256[] memory StrategyFundsAssets = new uint256[](2);
//         // //Case 0
//         // uint256 amount = 1500 * assetDecimal;
//         // StrategyFundsAssets[0] = 1400 * assetDecimal;
//         // StrategyFundsAssets[1] = 1600 * assetDecimal;
//         // uint256[] memory res = vaultComputation.getAssetsDistribution(amount, spIds, StrategyFundsAssets);
//         // assertEq(res[0], 700 * assetDecimal);
//         // assertEq(res[1], 800 * assetDecimal);

//         // //Case 1
//         // amount = 10000 * assetDecimal;
//         // StrategyFundsAssets[0] = 2500 * assetDecimal;
//         // StrategyFundsAssets[1] = 2000 * assetDecimal;
//         // res = vaultComputation.getAssetsDistribution(amount, spIds, StrategyFundsAssets);
//         // //console.log(res[0]);
//         // assertEq(res[0], 5555555555);
//         // assertEq(res[1], 4444444444);

//         // //Case 2
//         // amount = 35 * assetDecimal / 100; //0.35
//         // res = vaultComputation.getAssetsDistribution(amount, spIds, StrategyFundsAssets);
//         // assertEq(res[0], 194444);
//         // assertEq(res[1], 155555);
//     }

//     function testGetPerformanceFee() public {
//         initialize();
//         uint256[] memory StrategyFundsAssets = new uint256[](2);
//         StrategyFundsAssets[0] = 2500 * assetDecimal;
//         StrategyFundsAssets[1] = 2000 * assetDecimal;

//         uint256 mainAssetsAfterFee = vaultComputation.getPerformanceFee(spIds, StrategyFundsAssets);
//         console.log("Main Assets After Fee: %d", mainAssetsAfterFee);
//     }

//     //forge t --match-test testUpdateLedger -vv
//     // function testUpdateLedger() public {
//     //     initialize();
//     //     console.log("-----------------------------");
//     //     uint256 depositAmount = 10000 * assetDecimal;
//     //     uint256 withdrawShare = 1 * shareDecimal / 10; //0.1 shares
//     //     uint256[] memory StrategyFundsAssets = new uint256[](2);
//     //     StrategyFundsAssets[0] = 2500 * assetDecimal;
//     //     StrategyFundsAssets[1] = 2000 * assetDecimal;

//     //     //Period 1
//     //     vaultComputation.updateLedger(depositAmount, withdrawShare, spIds, StrategyFundsAssets);
//     //     console.log("=============After Period 1=====================");
//     //     consoleState();
//     //     //Period 2
//     //     console.log("=============Start Period 2=====================");
//     //     vaultComputation.updateLedger(0, 1 * shareDecimal, spIds, StrategyFundsAssets);
//     //     console.log("=============After Period 2=====================");
//     //     consoleState();
//     // }

//     function testPeriod() public {
//         uint256 mainshares = 1 * shareDecimal;

//         uint256[] memory StrategyFundsAssets = new uint256[](2);
//         StrategyFundsAssets[0] = 2000 * assetDecimal;
//         StrategyFundsAssets[1] = 2000 * assetDecimal;

//         uint256[] memory mainSharesInFund = new uint256[](2);
//         mainSharesInFund[0] = 1 * shareDecimal;
//         mainSharesInFund[1] = 1 * shareDecimal;

//         uint256[] memory spSharesInFund = new uint256[](2);
//         spSharesInFund[0] = 1 * shareDecimal;
//         spSharesInFund[1] = 1 * shareDecimal;

//         vaultComputation.initialize(mainshares, spIds, mainSharesInFund, spSharesInFund, StrategyFundsAssets);

//         SPOperation[] memory spOperations = new SPOperation[](2);
//         consoleState();

//         //Period 1
//         uint256 depositAmount = 500 * assetDecimal;
//         StrategyFundsAssets[0] = 1000 * assetDecimal;
//         StrategyFundsAssets[1] = 1000 * assetDecimal;
//         uint256 withdrawShare = 6 * shareDecimal / 10; //0.6 shares
//         spOperations[0] = SPOperation(0, 0);
//         spOperations[1] = SPOperation(800 * assetDecimal, 0);
//         console.log("=============Start Period 1=====================");
//         vaultComputation.updateLedger(depositAmount, withdrawShare, spOperations, spIds, StrategyFundsAssets);
//         console.log("=============After Period 1=====================");
//         consoleState();

//         //Period 2
//         StrategyFundsAssets[0] = 5000 * assetDecimal;
//         StrategyFundsAssets[1] = 1250 * assetDecimal;

//         depositAmount = 0;
//         withdrawShare = 0;
//         spOperations[1] = SPOperation(0, 0);

//         console.log("=============Start Period 2=====================");
//         vaultComputation.updateLedger(depositAmount, withdrawShare, spOperations, spIds, StrategyFundsAssets);
//         console.log("=============After Period 2=====================");
//         consoleState();

//         console.log("=============Start Period 3=====================");
//         //Period 3
//         depositAmount = 10000e6;
//         withdrawShare = 0;
//         StrategyFundsAssets[0] = 750 * assetDecimal;
//         StrategyFundsAssets[1] = 1000 * assetDecimal;
//         spOperations[0] = SPOperation(0, 0);
//         spOperations[1] = SPOperation(0, 1 * shareDecimal);
//         vaultComputation.updateLedger(depositAmount, withdrawShare, spOperations, spIds, StrategyFundsAssets);
//         console.log("=============After Period 3=====================");
//         consoleState();

//         //Period 4
//         depositAmount = 0;
//         withdrawShare = 8 * shareDecimal;
//         StrategyFundsAssets[0] = 5000 * assetDecimal;
//         StrategyFundsAssets[1] = 1000 * assetDecimal;
//         spOperations[0] = SPOperation(0, 0);
//         spOperations[1] = SPOperation(0, 0);
//         console.log("=============Start Period 4=====================");
//         vaultComputation.updateLedger(depositAmount, withdrawShare, spOperations, spIds, StrategyFundsAssets);
//         console.log("=============After Period 4=====================");
//         consoleState();

//         //Period 5
//         depositAmount = 0;
//         withdrawShare = 0;
//         StrategyFundsAssets[0] = 10750 * assetDecimal;
//         StrategyFundsAssets[1] = 1000 * assetDecimal;
//         spOperations[0] = SPOperation(0, 0);
//         spOperations[1] = SPOperation(0, 0);
//         console.log("=============Start Period 5=====================");
//         vaultComputation.updateLedger(depositAmount, withdrawShare, spOperations, spIds, StrategyFundsAssets);
//         console.log("=============After Period 5=====================");
//         consoleState();

//         //Period 6
//         depositAmount = 0;
//         withdrawShare = 0;
//         StrategyFundsAssets[0] = 6000 * assetDecimal;
//         StrategyFundsAssets[1] = 1000 * assetDecimal;
//         spOperations[0] = SPOperation(10000 * assetDecimal, 0);
//         spOperations[1] = SPOperation(0, 0);
//         console.log("=============Start Period 6=====================");
//         vaultComputation.updateLedger(depositAmount, withdrawShare, spOperations, spIds, StrategyFundsAssets);
//         console.log("=============After Period 6=====================");
//         consoleState();

//         //Period 7
//         depositAmount = 0;
//         withdrawShare = 0;
//         StrategyFundsAssets[0] = 4000 * assetDecimal;
//         StrategyFundsAssets[1] = 1000 * assetDecimal;
//         spOperations[0] = SPOperation(0, 9 * shareDecimal / 10);
//         spOperations[1] = SPOperation(0, 0);
//         console.log("=============Start Period 7=====================");
//         vaultComputation.updateLedger(depositAmount, withdrawShare, spOperations, spIds, StrategyFundsAssets);
//         console.log("=============After Period 7=====================");
//         consoleState();
//     }

//     function initialize() public {
//         uint256 spAmount = 1000e6;
//         //SP deposit
//         vaultComputation.strategyProviderDeposit(spA_id, spAmount, 0);
//         vaultComputation.strategyProviderDeposit(spB_id, spAmount, 0);
//         console.log("SP A deposit amount: %d", spAmount / assetDecimal);
//         console.log("SP B deposit amount: %d", spAmount / assetDecimal);

//         //User deposit
//         uint256 amount = 2000e6;

//         uint256[] memory ratios = new uint256[](2);
//         ratios[0] = 50;
//         ratios[1] = 50;

//         vaultComputation.initiaDeposit(amount, spIds, ratios);
//         console.log("User deposit amount: %d", amount / assetDecimal);
//         assertEq(vaultComputation.mainShares(), amount);
//         assertEq(vaultComputation.mainAssets(), amount);

//         StrategyFund memory strategyFundA = vaultComputation.getStrategyFund(spA_id);
//         StrategyFund memory strategyFundB = vaultComputation.getStrategyFund(spB_id);

//         //Initial Deposit
//         assertEq(strategyFundA.totalShares, spAmount + amount * ratios[0] / 100);
//         assertEq(strategyFundA.totalAssets, spAmount + amount * ratios[0] / 100);
//         assertEq(strategyFundB.totalAssets, spAmount + amount * ratios[1] / 100);
//         assertEq(strategyFundB.totalShares, spAmount + amount * ratios[1] / 100);
//         console.log("-----------------------------");
//         console.log("Main Shares: %d", vaultComputation.mainShares());
//         console.log("Total Shares A: %d", strategyFundA.totalShares);
//         console.log("Total Shares B: %d", strategyFundB.totalShares);
//         console.log("Start Fund A Total Assets: %d", strategyFundA.totalAssets);
//         console.log("Start Fund B Total Assets: %d", strategyFundB.totalAssets);
//         console.log("User Shares in Fund A: %d", strategyFundA.mainShares);
//         console.log("User Shares in Fund B: %d", strategyFundB.mainShares);
//         console.log("SP Shares in Fund A: %d", strategyFundA.strategyProviderShares);
//         console.log("SP Shares in Fund B %d", strategyFundB.strategyProviderShares);
//         console.log("-----------------------------");

//         console.log("SF A total assets: %d", strategyFundA.totalAssets);
//         console.log("SF B total assets: %d", strategyFundB.totalAssets);
//         console.log("LP total assets: %d", vaultComputation.mainAssets());
//         console.log("-----------------------------");
//         console.log("Main share price: %d", vaultComputation.mainAssets() / vaultComputation.mainShares());
//         console.log("SP A share price: %d", strategyFundA.totalAssets / strategyFundA.totalShares);
//         console.log("SP B share price: %d", strategyFundB.totalAssets / strategyFundB.totalShares);

//         //Performance fee
//     }

//     function consoleState() public view {
//         StrategyFund memory strategyFundA = vaultComputation.getStrategyFund(spA_id);
//         StrategyFund memory strategyFundB = vaultComputation.getStrategyFund(spB_id);

//         console.log("Total Assets A: %d", strategyFundA.totalAssets);
//         console.log("Total Assets B: %d", strategyFundB.totalAssets);

//         console.log("Total Main Shares: %d", vaultComputation.mainShares());
//         console.log("Main Share in Fund A: %d", strategyFundA.mainShares);
//         console.log("Main Share in Fund B: %d", strategyFundB.mainShares);

//         console.log("SP A shares in Fund A: %d", strategyFundA.strategyProviderShares);
//         console.log("SP B shares in Fund B: %d", strategyFundB.strategyProviderShares);

//         console.log("Total Shares A: %d", strategyFundA.totalShares);
//         console.log("Total Shares B: %d", strategyFundB.totalShares);

//         console.log("HWM A: %d", strategyFundA.hwm);
//         console.log("HWM B: %d", strategyFundB.hwm);
//     }
// }
