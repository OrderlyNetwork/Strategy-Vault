// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultType} from "./VaultStruct.sol";
//--------------------------------------Ledger Storage--------------------------------------------

struct Account {
    ///@dev keccak256(abi.encodePacked(user address, brokerhash))
    bytes32 accountId;
    ///@dev account assets amount
    uint256 assets;
    ///@dev account shares amount
    uint256 shares;
    ///@dev deposit assets that unallocated to shares
    uint256 unAllocatedAssets;
    ///@dev withdraw shares that waiting for handle
    uint256 frozenShares;
    ///@dev pending shares during a period, equal to shares after a period
    uint256 pendingShares;
    ///@dev assets that waitting to be transferred to PV
    uint256 enableClaimedAssets;
    ///@dev assets that user can claim on all chains
    uint256 unClaimedAssets;
}

struct StrategyFund {
    ///@dev keccak256(vault address, sp address, brokerHash))
    bytes32 strategyProviderId;
    PendingState pendingState;
    ///@dev fund assets after performance fee
    uint256 fundAssetsAfterFee;
    ///@dev deposit assets that waiting for handle
    uint256 unAllocatedAssets;
    ///@dev withdraw shares that unallocated to assets
    uint256 frozenShares;
    ///@dev fund main shares
    uint256 mainShares;
    ///@dev strategy provider shares in fund
    uint256 strategyProviderShares;
    ///@dev fund assets
    uint256 totalAssets;
    ///@dev fund shares
    uint256 totalShares;
    ///@dev high water mark
    uint256 hwm;
}

struct PendingState {
    ///@dev pending performance fee during a period
    uint256 pendingPerformanceFee;
    ///@dev pending fund assets during a period
    uint256 pendingFundAssets;
    ///@dev pending fund shares during a period
    uint256 pendingFundShares;
    ///@dev pending main shares during a period
    uint256 pendingMainShares;
    ///@dev pending strategy provider shares during a period
    uint256 pendingStrategyProviderShares;
}

//--------------------------------------Ledger Update--------------------------------------------

struct UpdateLedgerParams {
    uint256 nonce;
    UserOperation[] userOperations;
    StrategyProviderOperation[] strategyProviderOperations;
}

struct StrategyFundAssets {
    bytes32 strategyProviderId;
    uint256 totalAssets;
}

struct UserOperation {
    bytes32 accountId;
    uint256 depositAssets;
    uint256 withdrawShares;
}

struct StrategyProviderOperation {
    bytes32 strategyProviderId;
    uint256 depositAssets;
    uint256 withdrawShares;
}
//--------------------------------------Ledger Check--------------------------------------------

struct AccountState {
    bytes32 accountId;
    uint256 shares;
}

struct StrategyFundState {
    bytes32 strategyProviderId;
    uint256 totalShares;
    uint256 totalAssets;
    uint256 strategyProviderShares;
    uint256 hwm;
}

struct PeriodState {
    AccountState[] accountState;
    StrategyFundState[] strategyProviderState;
    uint256 mainshares;
}
//--------------------------------------Ledger Settle--------------------------------------------

enum SettleType {
    HWM,
    MAIN,
    ACCOUNT,
    STRATEGY_PROVIDER
}

struct SettleParams {
    ///@dev settle type
    SettleType settleType;
    ///@dev account ID
    bytes32[] accountIds;
    ///@dev strategy provider ID
    bytes32[] strategyProviderIds;
}
//--------------------------------------Fund Transfer--------------------------------------------

struct BasicInfo {
    ///@dev USER or PROTOCOL
    VaultType vaultType;
    ///@dev period ID
    uint256 periodId;
    ///@dev keccak256(abi.encodePacked(vault address, brokerHash))
    bytes32 vaultId;
    ///@dev token hash
    bytes32 tokenHash;
    ///@dev keccak256(abi.encodePacked(broker address))
    bytes32 brokerHash;
}

struct AssetsDistribution {
    uint256 chainId;
    uint256 assets;
}

struct FundTransferParams {
    ///@dev total assets to be transferred
    uint256 totalAssets;
    BasicInfo basicInfo;
    ///@dev assets distribution
    AssetsDistribution[] assetsDistributions;
}

struct StrategyExecution {
    BasicInfo basicInfo;
    uint256 chainId;
    uint256 assets;
}
//--------------------------------------User Claim--------------------------------------------

struct UpdateUserClaim {
    bytes32 accountId;
    uint256 claimAssets;
}
