// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {
    UpdateStrategyFundAssetsParams,
    UpdateStrategyFundAssetsRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    StrategyFundState,
    AllocateFundRes,
    OperationRes,
    ClaimInfo
} from "../lib/types/LedgerStruct.sol";

/// @title ILedgerCoreImpl Interface
/// @notice Interface for core business flow methods in the protocol vault ledger
interface ILedgerCoreImpl {
    // Custom errors - LedgerCoreImpl specific
    error AlreadyCalled();
    error InvalidType();
    error InvalidPeriodId();
    error NotEnoughLPDeposit(uint256 amount);
    error NotEnoughSPDeposit();

    // Events
    event StrategyFundAssetsUpdate(
        uint256 periodId,
        bytes32 vaultId,
        uint256 mainAssetsAfterFee,
        UpdateStrategyFundAssetsRes[] updateStrategyFundAssetsRes
    );
    event LPAndStrategyFundUpdated(uint256 periodId, bytes32 vaultId, OperationRes[] operationRes);
    event FundAllocated(
        uint256 periodId, bytes32 vaultId, bytes32[] strategyProviderIds, AllocateFundRes[] allocateFundRes
    );
    event MainAndStrategyFundsSettled(
        uint256 periodId, bytes32 vaultId, uint256 mainShares, StrategyFundState[] strategyFundStates
    );
    event AccountSettled(uint256 periodId, bytes32 vaultId, AccountState[] accountStates);
    event PeriodIdUpdated(uint256 latestPeriodId, bytes32 vaultId);
    event AssetsDistributed(uint256 periodId, bytes32 vaultId);
    event UnclaimedAssetsUpdated(uint256 periodId, bytes32 vaultId, ClaimInfo[] userClaimInfos);
    /// @notice Operator upload NAV of each strategy fund and compute performance fee at first of the period
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyFundAssets strategy fund assets info
    /// @param signature signature of BE

    function updateStrategyFundAssets(
        uint256 periodId,
        bytes32 vaultId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes calldata signature
    ) external;

    /// @notice Operator update LP and strategy fund info
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param updateUserLedgerParams update user ledger info
    /// @param signature signature of BE
    function updateLPAndStrategyFund(
        uint256 periodId,
        bytes32 vaultId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes calldata signature
    ) external;

    /// @notice Operator allocate all lp deposit and withdraw to strategy funds after handle all lp operation
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyProviderIds each strategy provider id
    /// @param signature signature of BE
    function allocateToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external;

    /// @notice Operator settle main and strategy fund info after check all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyProviderIds each strategy provider id
    /// @param signature signature of BE
    function settleMainAndStrategyFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external;

    /// @notice Operator settle all LP infos after check all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param accountIds each account id
    /// @param signature signature of BE
    function settleAccounts(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds, bytes calldata signature)
        external;

    /// @notice Operator update period id after last period finish
    /// @param periodId latest periodId
    /// @param vaultId vault id
    /// @param signature signature of BE
    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes calldata signature) external;

    /// @notice Distribute assets to strategy
    /// @param periodId Period ID
    /// @param vaultId Vault ID
    /// @param assetsDistributions Asset distribution info
    /// @param signature Signature for verification
    function distributeAssets(
        uint256 periodId,
        bytes32 vaultId,
        AssetsDistribution[] memory assetsDistributions,
        bytes calldata signature
    ) external;

    /// @notice Update unclaimed assets after funds transfer to protocol vault
    /// @param chainId Chain ID that unclaimed assets will be updated
    /// @param periodId Period ID
    /// @param vaultId Vault ID
    /// @param requestIds Request ID array
    /// @param signature Signature for verification
    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        uint256 ccFee,
        bytes32 vaultId,
        bytes32[] memory requestIds,
        bytes calldata signature
    ) external;

    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] memory requestIds,
        bytes calldata signature
    ) external;
}
