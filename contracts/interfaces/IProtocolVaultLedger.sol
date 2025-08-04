// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    AccountToken,
    StrategyFundToken,
    UpdateStrategyFundAssetsParams,
    UpdateStrategyFundAssetsRes,
    UpdateLedgerParams,
    AccountState,
    AllocateFundRes,
    StrategyFundState,
    OperationRes
} from "../lib/types/LedgerStruct.sol";

import {OperationData} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";

/// @title IProtocolVaultLedger
/// @notice Interface for the main Protocol Vault Ledger contract
/// @dev Contains high-frequency functions and configuration methods
interface IProtocolVaultLedger {
    // Custom errors - Main contract specific
    error InvalidPeriodId();
    error InvalidOperator();
    error InvalidVaultCrossChainManager();
    error NotEnoughLPDeposit(uint256 amount);
    error NotEnoughSPDeposit();
    error InvalidType();
    error NotEnoughFrozenShare(uint256 amount);
    error InvalidInput();
    error AlreadyCalled();
    error NotAllowedTime();
    error InvalidNonce();
    error DelegatecallFailed();
    error LedgerExtensionsNotSet();
    error LedgerCoreImplNotSet();

    // Events - Main contract specific
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
    event NotEnoughWithdrawShare(PayloadType payloadType, uint256 chainId, uint256 chainNonce);
    
    // Configuration events
    event FeeRateSet(bytes32[] strategyProviderIds, uint256[] feeRates);
    event CrossChainManagerSet(address crossChainManager);
    event AllowedStrategyProviderSet(
        bytes32 vaultId, address vault, address sp, bytes32 brokerHash, bytes32 spId, bool knob
    );
    event OperatorManagerSet(address operator);
    event EngineSet(address engine);
    event DecimalSet(bytes32 tokenHash, uint256 decimal);
    event VaultBrokerSet(bytes32 vaultId, bytes32 brokerId);
    event LedgerExtensionsSet(address ledgerExtensions);
    event LedgerCoreImplSet(address ledgerCoreImpl);

    //--------------------------------------HIGH FREQUENCY FUNCTIONS-----------------------------------------
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData) external;
    function updateStrategyFundAssets(
        uint256 periodId,
        bytes32 vaultId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes calldata signature
    ) external;
    function updateLPAndStrategyFund(
        uint256 periodId,
        bytes32 vaultId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes calldata signature
    ) external;
    function allocateToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external;
}
