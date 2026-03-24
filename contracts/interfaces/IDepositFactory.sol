// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DepositParams} from "../lib/types/VaultStruct.sol";
import {VaultDepositFE} from "./IDexVault.sol";

/// @title IDepositFactory
/// @notice Interface for DepositFactory contract that manages deposit proxy deployments and deposits
interface IDepositFactory {
    /// @notice Emitted when a new proxy is deployed
    /// @param accountId User account identifier
    /// @param vaultAddress Target vault address
    /// @param proxyAddress Deployed proxy address
    event ProxyDeployed(bytes32 accountId, address vaultAddress, address proxyAddress);

    event DepositToVault(uint256 depositId);
    event DepositToDex(uint256 depositId);

    /// @notice Emitted when a vault is registered
    /// @param vaultId Vault identifier
    /// @param vaultAddress Vault contract address
    event VaultRegistered(bytes32 vaultId, address vaultAddress);

    /// @notice Emitted when a vault is unregistered
    /// @param vaultId Vault identifier
    event VaultUnregistered(bytes32 vaultId);

    /// @notice Emitted when a token support status is updated
    /// @param token Token address
    /// @param supported Whether token is supported
    event TokenSupportUpdated(address token, bool supported);

    /// @notice Emitted when a tokenHash to address mapping is updated
    /// @param tokenHash Token hash identifier
    /// @param token Token contract address
    event TokenHashRegistered(bytes32 tokenHash, address token);

    /// @notice Emitted when emergency withdrawal is executed
    /// @param accountId User account identifier
    /// @param vaultAddress Vault address
    /// @param token Token address
    /// @param to Recipient address
    /// @param amount Withdrawal amount
    event EmergencyWithdrawal(bytes32 accountId, address vaultAddress, address token, address to, uint256 amount);

    /// @notice Emitted when operator address is updated
    /// @param oldOperator Previous operator address
    /// @param newOperator New operator address
    event OperatorUpdated(address oldOperator, address newOperator);

    /// @notice Emitted when implementation is updated
    /// @param oldImplementation Previous implementation address
    /// @param newImplementation New implementation address
    event ImplementationUpdated(address oldImplementation, address newImplementation);

    error UnauthorizedCaller(address caller);
    error InsufficientBalance(uint256 required, uint256 available);
    error InvalidAccountId();
    error TokenNotSupported(address token);
    error VaultNotRegistered(bytes32 vaultId);
    error ProxyAlreadyDeployed(address proxy);
    error DepositFailed(string reason);
    error InvalidAmount(uint256 amount);
    error ZeroAddress();
    error TransferFailed();
    error DepositAlreadyProcessed(uint256 depositId);
    error ImplementationNotConfigured();

    /// @notice Get the deterministic deposit address for a user and vault
    /// @param accountId User account identifier
    /// @param vaultAddress Target vault address
    /// @return Computed deposit address
    function getDepositAddress(bytes32 accountId, address vaultAddress) external view returns (address);

    /// @notice Deploy proxy and deposit to a registered vault
    /// @param depositId Unique identifier for this deposit request (idempotency key, derived from transfer tx hash + log index off-chain)
    /// @param vaultId Vault identifier
    /// @param params Deposit parameters
    /// @return proxy Deployed or existing proxy address
    function deployAndDepositToVault(uint256 depositId, bytes32 vaultId, DepositParams memory params)
        external
        payable
        returns (address proxy);

    /// @notice Deploy proxy and deposit to DexVault
    /// @dev accountId is read from data.accountId (VaultDepositFE already contains it)
    /// @param depositId Unique identifier for this deposit request (idempotency key)
    /// @param data Vault deposit data (contains accountId, brokerHash, tokenHash, tokenAmount)
    /// @param receiver Receiver address
    /// @return proxy Deployed or existing proxy address
    function deployAndDepositToDex(uint256 depositId, address receiver, VaultDepositFE memory data)
        external
        payable
        returns (address proxy);

    /// @notice Check if proxy is deployed for given accountId and vault
    /// @param accountId User account identifier
    /// @param vaultAddress Target vault address
    /// @return True if proxy is deployed
    function isDeployed(bytes32 accountId, address vaultAddress) external view returns (bool);
    /// @notice Set new implementation address
    /// @param newImpl New implementation address
    function setImplementation(address newImpl) external;

    /// @notice Register a vault
    /// @param vaultId Vault identifier
    /// @param vaultAddress Vault contract address
    function registerVault(bytes32 vaultId, address vaultAddress) external;

    /// @notice Unregister a vault
    /// @param vaultId Vault identifier
    function unregisterVault(bytes32 vaultId) external;

    /// @notice Set token support status
    /// @param token Token address
    /// @param supported Whether token is supported
    function setSupportedToken(address token, bool supported) external;

    /// @notice Register a tokenHash to token address mapping
    /// @param tokenHash Token hash identifier
    /// @param token Token contract address (zero address to remove)
    function setTokenHash(bytes32 tokenHash, address token) external;

    /// @notice Get token address by tokenHash
    /// @param tokenHash Token hash identifier
    /// @return Token contract address
    function tokenHashToAddress(bytes32 tokenHash) external view returns (address);

    /// @notice Set operator address
    /// @param newOperator New operator address
    function setOperator(address newOperator) external;

    /// @notice Emergency withdrawal from a proxy
    /// @param accountId User account identifier
    /// @param vaultAddress Vault address
    /// @param token Token address
    /// @param to Recipient address
    /// @param amount Withdrawal amount
    function emergencyWithdraw(bytes32 accountId, address vaultAddress, address token, address to, uint256 amount)
        external;

    /// @notice Get operator address
    /// @return Current operator address
    function operator() external view returns (address);

    /// @notice Get DexVault address
    /// @return DexVault address
    function dexVault() external view returns (address);

    /// @notice Get vault address by vaultId
    /// @param vaultId Vault identifier
    /// @return Vault address
    function vaults(bytes32 vaultId) external view returns (address);

    /// @notice Check if token is supported
    /// @param token Token address
    /// @return True if token is supported
    function supportedTokens(address token) external view returns (bool);

    /// @notice Check if a depositId has already been processed
    /// @param depositId Deposit idempotency key
    /// @return True if already processed
    function processedDeposits(uint256 depositId) external view returns (bool);

    /// @notice Frozen BeaconProxy initCode (creationCode + constructor args) stored at initialization
    /// @dev Both address prediction and deployment use this value; stable across OZ version upgrades
    /// @return Full initCode bytes written once during initialize
    function proxyInitCode() external view returns (bytes memory);
}
