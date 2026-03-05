// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IDepositFactory} from "../interfaces/IDepositFactory.sol";
import {IDepositProxyImplementation} from "../interfaces/IDepositProxyImplementation.sol";
import {DepositParams} from "../lib/types/VaultStruct.sol";
import {VaultDepositFE} from "../interfaces/IDexVault.sol";

/// @title DepositFactory
/// @notice Factory contract for deploying and managing deposit proxies using OpenZeppelin's Beacon Proxy pattern
/// @dev Acts as IBeacon for all proxies, stores current implementation address
/// @dev All deployed proxies query this contract for implementation and can be upgraded simultaneously
/// @dev This contract itself is upgradeable using UUPS pattern
contract DepositFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable, IDepositFactory, IBeacon {
    /// @notice Current implementation address (beacon)
    address public implementation;

    /// @notice DexVault contract address
    address public dexVault;

    /// @notice Authorized operator address
    address public operator;

    /// @notice Frozen BeaconProxy initCode (creationCode + constructor args) stored at initialization
    /// @dev ensuring CREATE2 addresses remain stable even if the OZ library is upgraded later
    bytes public proxyInitCode;

    /// @notice Mapping of vaultId to vault address
    mapping(bytes32 => address) public vaults;

    /// @notice Mapping of token address to supported status
    mapping(address => bool) public supportedTokens;

    /// @notice Mapping of tokenHash to token address (used for dex deposits)
    mapping(bytes32 => address) public tokenHashToAddress;

    /// @notice Mapping of depositId to processed status
    mapping(uint256 => bool) public processedDeposits;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the factory contract
    /// @param _dexVault DexVault address
    /// @param _operator Operator address
    /// @param _owner Owner address
    function initialize(address _dexVault, address _operator, address _owner)
        external
        initializer
    {
        if (_dexVault == address(0) || _operator == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }

        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        dexVault = _dexVault;
        operator = _operator;

        // Freeze the full BeaconProxy initCode at deploy time
        proxyInitCode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(this), ""));
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /// @inheritdoc IDepositFactory
    function deployAndDepositToVault(uint256 depositId, bytes32 vaultId, DepositParams memory params)
        external
        payable
        onlyOperator
        returns (address proxy)
    {
        _checkImplementationConfigured();
        _checkAndMarkDeposit(depositId);

        if (!supportedTokens[params.token]) revert TokenNotSupported(params.token);

        address vault = vaults[vaultId];
        if (vault == address(0)) revert VaultNotRegistered(vaultId);

        bytes32 accountId = keccak256(abi.encode(params.receiver, params.brokerHash));
        proxy = _deployIfNeeded(accountId, vault);

        bytes memory data = abi.encodeCall(IDepositProxyImplementation.depositToVault, (vault, params));
        _checkBalanceAndExecute(proxy, params.token, params.amount, data);

        emit DepositToVault(depositId);
    }

    /// @inheritdoc IDepositFactory
    function deployAndDepositToDex(uint256 depositId, address receiver, VaultDepositFE memory data)
        external
        payable
        onlyOperator
        returns (address proxy)
    {
        _checkImplementationConfigured();
        _checkAndMarkDeposit(depositId);

        bytes32 accountId = _getAccountId(receiver, data.brokerHash);
        if (accountId != data.accountId) revert InvalidAccountId();

        address token = _getTokenFromHash(data.tokenHash);
        if (!supportedTokens[token]) revert TokenNotSupported(token);

        proxy = _deployIfNeeded(accountId, dexVault);

        bytes memory callData =
            abi.encodeCall(IDepositProxyImplementation.depositToDex, (dexVault, receiver, token, data));
        _checkBalanceAndExecute(proxy, token, uint256(data.tokenAmount), callData);

        emit DepositToDex(depositId);
    }

    /// @inheritdoc IDepositFactory
    function isDeployed(bytes32 accountId, address vaultAddress) public view returns (bool) {
        address proxy = getDepositAddress(accountId, vaultAddress);
        return proxy.code.length > 0;
    }

    /// @inheritdoc IDepositFactory
    function getDepositAddress(bytes32 accountId, address vaultAddress) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(accountId, vaultAddress));
        return Create2.computeAddress(salt, keccak256(proxyInitCode));
    }

    /// @inheritdoc IDepositFactory
    function setImplementation(address newImpl) external onlyOwner {
        if (newImpl == address(0)) revert ZeroAddress();
        if (newImpl.code.length == 0) revert DepositFailed("Implementation must be a contract");

        address oldImpl = implementation;
        implementation = newImpl;
        emit ImplementationUpdated(oldImpl, newImpl);
    }

    /// @inheritdoc IDepositFactory
    function registerVault(bytes32 vaultId, address vaultAddress) external onlyOwner {
        if (vaultAddress == address(0)) revert ZeroAddress();
        vaults[vaultId] = vaultAddress;
        emit VaultRegistered(vaultId, vaultAddress);
    }

    /// @inheritdoc IDepositFactory
    function unregisterVault(bytes32 vaultId) external onlyOwner {
        delete vaults[vaultId];
        emit VaultUnregistered(vaultId);
    }

    /// @inheritdoc IDepositFactory
    function setSupportedToken(address token, bool supported) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    /// @inheritdoc IDepositFactory
    function setTokenHash(bytes32 tokenHash, address token) external onlyOwner {
        tokenHashToAddress[tokenHash] = token;
        emit TokenHashRegistered(tokenHash, token);
    }

    /// @inheritdoc IDepositFactory
    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        address oldOperator = operator;
        operator = newOperator;
        emit OperatorUpdated(oldOperator, newOperator);
    }

    /// @inheritdoc IDepositFactory
    function emergencyWithdraw(bytes32 accountId, address vaultAddress, address token, address to, uint256 amount)
        external
        onlyOwner
    {
        if (to == address(0)) revert ZeroAddress();

        address proxy = getDepositAddress(accountId, vaultAddress);
        if (proxy.code.length == 0) revert DepositFailed("Proxy not deployed");

        bytes memory data = abi.encodeCall(IDepositProxyImplementation.withdraw, (token, to, amount));

        (bool success, bytes memory returnData) = proxy.call(data);
        if (!success) {
            _revertWithReason(returnData);
        }

        emit EmergencyWithdrawal(accountId, vaultAddress, token, to, amount);
    }

    /// @notice Check depositId is new and mark it as processed
    /// @param depositId Deposit idempotency key
    function _checkAndMarkDeposit(uint256 depositId) internal {
        if (processedDeposits[depositId]) revert DepositAlreadyProcessed(depositId);
        processedDeposits[depositId] = true;
    }

    /// @notice Ensure beacon implementation has been configured and is a contract
    function _checkImplementationConfigured() internal view {
        if (implementation.code.length == 0) revert ImplementationNotConfigured();
    }

    /// @notice Verify proxy balance then call proxy, propagating any revert
    /// @param proxy Proxy address
    /// @param token Token to check balance of
    /// @param amount Required minimum balance
    /// @param callData Encoded call to forward to proxy
    function _checkBalanceAndExecute(address proxy, address token, uint256 amount, bytes memory callData) internal {
        uint256 balance = IERC20(token).balanceOf(proxy);
        if (balance < amount) revert InsufficientBalance(amount, balance);
        
        (bool success, bytes memory returnData) = proxy.call{value: msg.value}(callData);
        if (!success) {
            _revertWithReason(returnData);
        }
    }

    /// @notice Get account ID from receiver and broker hash
    /// @param receiver Receiver address
    /// @param brokerHash Broker hash
    /// @return Account ID
    function _getAccountId(address receiver, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(receiver, brokerHash));
    }

    /// @notice Deploy proxy if not already deployed
    /// @param accountId User account identifier
    /// @param vaultAddress Target vault address
    /// @return proxy Proxy address
    function _deployIfNeeded(bytes32 accountId, address vaultAddress) internal returns (address proxy) {
        proxy = getDepositAddress(accountId, vaultAddress);

        // Check if already deployed by checking if address has code
        if (proxy.code.length > 0) {
            return proxy;
        }

        bytes32 salt = keccak256(abi.encodePacked(accountId, vaultAddress));
        proxy = Create2.deploy(0, salt, proxyInitCode);

        emit ProxyDeployed(accountId, vaultAddress, proxy);
    }

    /// @notice Get token address from tokenHash
    /// @param tokenHash Token hash
    /// @return token Token address
    function _getTokenFromHash(bytes32 tokenHash) private view returns (address token) {
        token = tokenHashToAddress[tokenHash];
        if (token == address(0)) revert TokenNotSupported(address(0));
    }

    /// @notice Revert with the reason from a failed call
    /// @param returnData The return data from the failed call
    function _revertWithReason(bytes memory returnData) private pure {
        if (returnData.length > 0) {
            assembly {
                let returnDataSize := mload(returnData)
                revert(add(32, returnData), returnDataSize)
            }
        } else {
            revert DepositFailed("Execution failed");
        }
    }

    /// @notice Authorize upgrade (UUPS requirement)
    /// @param newImplementation New factory implementation address
    /// @dev Only owner can upgrade the factory contract itself
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
