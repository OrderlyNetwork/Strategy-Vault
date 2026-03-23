// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    UpdateStrategyFundAssetsParams,
    UpdateLedgerParams,
    UpdateStrategyFundAssetsRes,
    OperationRes,
    AllocateFundRes,
    StrategyFundState,
    AccountState,
    ClaimInfo,
    DexRequest,
    AssetsDistribution,
    ShareTransferResult
} from "../lib/types/LedgerStruct.sol";
import {OperationData} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";

/// @title IProtocolVaultLedger
/// @notice Interface for the main Protocol Vault Ledger contract
/// @dev Contains high-frequency functions and configuration methods
interface IProtocolVaultLedger {
    // Custom errors - ProtocolVaultLedger specific
    error InvalidPeriodId();
    error InvalidOperator();
    error InvalidVaultCrossChainManager();
    error InvalidInput();
    error DelegatecallFailed();
    error LedgerExtensionsNotSet();
    error InvalidStrategyProviderId();

    event FeeRateSet(bytes32[] strategyProviderIds, uint256[] feeRates);
    event CrossChainManagerSet(address crossChainManager);
    event AllowedStrategyProviderSet(
        bytes32 vaultId, address vault, address sp, bytes32 brokerHash, bytes32 spId, bool knob
    );
    event OperatorManagerSet(address operator);
    event EngineSet(address engine);
    event DecimalSet(bytes32 tokenHash, uint256 decimal);
    event VaultBrokerSet(bytes32 vaultId, bytes32 brokerId);
    event CoreSet(address core);
    event ExtensionSet(address extension);
    event ProtocolVaultSet(address protocolVault);
    event VaultSet(bytes32 vaultId, address vault);

    //Core Event
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
    //Extension Event
    event OperationHandled(PayloadType payloadType, uint256 chainId, OperationData operationData);
    event NotEnoughWithdrawShare(PayloadType payloadType, uint256 chainId, uint256 chainNonce, bytes32 vaultId);
    event DexRequestHandled(DexRequest request);
    event DexWithdrawNotEnough(uint256 requestId);
    event InvalidFrozenSharesRemoved(bytes32 vaultId, OperationRes[] operationRes);
    event ShareTransferExecuted(ShareTransferResult[] results);
    //core
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

    //extension
    /// @notice Handles operations from vault
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData) external;

    /// @notice Handle DEX requests
    /// @param dexRequests Array of DEX requests
    /// @param signature Signature for verification
    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external;

    /// @notice Remove invalid frozen shares for LP or SP that were incorrectly added
    /// @param vaultId The vault ID
    /// @param params The parameters containing the invalid frozen shares to remove
    /// @param signature The signature to verify
    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external;
}
