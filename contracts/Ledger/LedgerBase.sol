// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccountToken, StrategyFundToken, ClaimInfo} from "../lib/types/LedgerStruct.sol";
import {USDC_HASH} from "../lib/types/Constants.sol";

/// @title Ledger Storage
/// @notice This contract contains all storage variables for ProtocolVaultLedger
/// @dev This contract should be inherited by both main contract and extensions contract
abstract contract LedgerBase {
    using Math for uint256;

    uint256 public pendingMainShares;
    uint256 public pendingLpDepositAssets;
    uint256 public pendingLpWithdrawAssets;
    
    uint256 public mainShares;
    uint256 public mainAssetsAfterFee;
    // @dev the latest period id that contract handle
    uint256 public latestPeriodId;

    /// @dev address of cross chain manager
    address public crossChainManager;
    /// @dev address of interact with ledger
    address public operator;
    /// @dev address of upload data to contract
    address public engine;
    /// @dev address of ledger extensions contract for low frequency functions
    address public ledgerExtensions;
    /// @dev address of ledger core implementation contract for core business flow
    address public ledgerCoreImpl;

    /// @dev Token Hash to token decimal
    mapping(bytes32 => uint256) tokenDecimal;
    /// @dev fee rate of each strategy fund by vault id
    mapping(bytes32 => uint256) public feeRateOfFund;
    /// @dev strategy fund token information by strategy provider id and token hash
    mapping(bytes32 => mapping(bytes32 => StrategyFundToken)) public strategyFundTokenInfo;
    /// @dev account token information by account id and token hash
    mapping(bytes32 => mapping(bytes32 => AccountToken)) public accountTokenInfo;
    /// @dev requestId to User Claim information
    mapping(bytes32 => ClaimInfo) public userClaimInfo;
    /// @dev Determines whether the operation corresponding to the requestId is executed
    mapping(bytes32 => bool) public isOpHandled;
    /// @dev Determines whether the user claim is handled
    mapping(bytes32 => bool) public isUserClaimHandled;
    /// @dev Determines whether the assets has been uploaded in a period. Only can be called once in a period.
    mapping(uint256 => bool) public isUpdateStrategyFundAssets;
    /// @dev Determines whether the assets has been allocated in a period.
    mapping(uint256 => bool) public isAllocatedToFunds;
    /// @dev Determines whether the assets has been distributed in a period. Only can be called once in a period.
    mapping(uint256 => bool) public isAssetDistributed;
    /// @dev Determines whether the dex request has been handled
    mapping(uint256 => bool) public isDexRequestHandled;
    /// @dev vault id to sv broker hash
    mapping(bytes32 => bytes32) public vaultBroker;

    /// @notice Get strategy fund token storage reference (reduces storage access repetition)
    /// @param spId strategy provider ID
    /// @return strategyFundToken storage reference to strategy fund token
    function _getStrategyFundToken(bytes32 spId)
        internal
        view
        virtual
        returns (StrategyFundToken storage strategyFundToken)
    {
        return strategyFundTokenInfo[spId][USDC_HASH];
    }

    /// @notice Get account token storage reference (reduces storage access repetition)
    /// @param accountId account ID
    /// @return accountToken storage reference to account token
    function _getAccountToken(bytes32 accountId) internal view virtual returns (AccountToken storage accountToken) {
        return accountTokenInfo[accountId][USDC_HASH];
    }
}
