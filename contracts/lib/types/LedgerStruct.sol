// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultType} from "./VaultStruct.sol";
//--------------------------------------Ledger Storage--------------------------------------------

struct AccountToken {
    ///@dev account shares amount
    uint256 shares;
    ///@dev deposit assets that unallocated to shares
    uint256 unAllocatedAssets;
    ///@dev withdraw shares that waiting for handle
    uint256 frozenShares;
    ///@dev pending shares during a period, equal to shares after a period
    uint256 pendingShares;
}

struct StrategyFundToken {
    ///@dev pending state during a period
    PendingState pendingState;
    ///@dev performance fee during a period
    uint256 performanceFee;
    ///@dev fund assets after performance fee
    uint256 fundAssetsAfterFee;
    ///@dev sp deposit assets that unallocated to shares
    uint256 unAllocatedAssets;
    ///@dev withdraw sp shares that unallocated to assets
    uint256 frozenShares;
    ///@dev fund main shares
    uint256 mainShares;
    ///@dev strategy provider shares in fund
    uint256 strategyProviderShares;
    ///@dev fund total assets
    uint256 totalAssets;
    ///@dev fund total shares
    uint256 totalShares;
    ///@dev high water mark
    uint256 hwm;
}

struct PendingState {
    ///@dev pending fund assets during a period
    uint256 pendingTotalAssets;
    ///@dev pending fund shares during a period
    uint256 pendingTotalShares;
    ///@dev pending main shares during a period
    uint256 pendingMainShares;
    ///@dev pending strategy provider shares during a period
    uint256 pendingStrategyProviderShares;
}

//--------------------------------------Ledger Update--------------------------------------------

struct UpdateStrategyFundAssetsParams {
    ///@dev keccak256(vault address, sp address, brokerHash))
    bytes32 strategyProviderId;
    ///@dev fund assets after a period
    uint256 totalAssets;
}

struct UpdateStrategyFundAssetsRes {
    ///@dev keccak256(vault address, sp address, brokerHash))
    bytes32 strategyProviderId;
    ///@dev pending fundAssetsAfterFee after update fund assets
    uint256 fundAssetsAfterFee;
    ///@dev pending strategyProviderShares after update fund assets
    uint256 strategyProviderShares;
    ///@dev pending totalShares after update fund assets
    uint256 totalShares;
}

struct UpdateLedgerParams {
    OperationType operationType;
    Operation operation;
}

enum OperationType {
    LP_DEPOSIT,
    LP_WITHDRAW,
    SP_DEPOSIT,
    SP_WITHDRAW
}

struct Operation {
    /// @dev account ID or strategy provider ID
    bytes32 id;
    /// @dev operation requestId, calculate by EVM chainId and chainNonce
    bytes32 requestId;
    /// @dev deposit assets or withdraw share
    uint256 amount;
}

//--------------------------------------Ledger Check--------------------------------------------
///@notice Event for handle operation
struct OperationRes {
    /// @dev account ID or strategy provider ID
    bytes32 id;
    /// @dev operation requestId
    bytes32 requestId;
    /// @dev deposit shares or withdraw assets by computed
    uint256 amount;
    /// @dev operation type
    OperationType operationType;
}

///@notice Event for handle fund allocation
struct AllocateFundRes {
    ///@dev keccak256(vault address, sp address, brokerHash))
    bytes32 strategyProviderId;
    uint256 totalDepositAssets;
    uint256 totalDepositShares;
    uint256 totalWithdrawAssets;
    uint256 totalWithdrawShares;
}

struct AccountState {
    bytes32 accountId;
    uint256 shares;
}

struct StrategyFundState {
    bytes32 strategyProviderId;
    uint256 totalShares;
    uint256 totalAssets;
    uint256 mainShares;
    uint256 strategyProviderShares;
    uint256 hwm;
}

//--------------------------------------Fund Transfer--------------------------------------------
enum StrategyType {
    Orderly
}

struct Strategy {
    StrategyType strategyType;
    address receiver;
}

struct AssetsDistribution {
    ///@dev chainId
    uint256 chainId;
    ///@dev assets amount to be distributed on a chain
    uint256 assets;
}
//--------------------------------------User Claim--------------------------------------------

struct UpdateUserClaim {
    ///@dev accountId or strategyProviderId
    bytes32 userId;
    ///@dev update unclaimed assets requestId
    bytes32 requestId;
}

struct ClaimInfo {
    bytes32 requestId;
    ///@dev accountId or bytes32(0) if strategyProvider
    bytes32 accountId;
    ///@dev strategyProviderId or bytes32(0) if account
    bytes32 strategyProviderId;
    ///@dev assets amount that user can claim
    uint256 assets;
}
