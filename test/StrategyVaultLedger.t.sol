// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";
import {
    Account,
    StrategyFund,
    StrategyFundAssets,
    FundTransferParams,
    BasicInfo,
    StrategyExecution,
    StrategyProviderOperation,
    UpdateLedgerParams,
    PeriodState,
    UserOperation,
    AssetsDistribution,
    UpdateUserClaim,
    SettleType,
    SettleParams
} from "../contracts/StrategyVaultLedger.sol";

contract StrategyVaultLedgerTest is Base {
    uint256 shareDecimal = 1e6;
    uint256 assetDecimal = 1e6;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public spA = address(0x3);
    address public spB = address(0x4);

    bytes32 spA_id = keccak256(abi.encodePacked(spA));
    bytes32 spB_id = keccak256(abi.encodePacked(spB));

    bytes32[] public spIds;

    function setUp() override public {
        super.setUp();

        spIds.push(spA_id);
        spIds.push(spB_id);
    }

    //forge t --match-test testUpdateLedger -vv
    function testUpdateLedger() public {
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
        svLedger.initializeStrategyFund(mainshares, spIds, mainSharesInFund, spSharesInFund, StrategyFundsAssets);

        consoleState();
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
}
