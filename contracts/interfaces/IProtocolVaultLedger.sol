// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UpdateStrategyFundAssetsParams, UpdateLedgerParams} from "../lib/types/LedgerStruct.sol";
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
    error NotAllowedTime();
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

    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData)
        external;
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
