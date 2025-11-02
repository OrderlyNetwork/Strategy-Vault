// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Address.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Signature} from "./lib/utils/Signature.sol";
import {AdapterDeposit, RoleType, AdapterDepositLegacy} from "./lib/types/VaultStruct.sol";
import {VaultDepositFE, IDexVault} from "./interfaces/IDexVault.sol";
import {VaultUtils} from "./lib/utils/VaultUtils.sol";
import {IVaultAdapter} from "./interfaces/IVaultAdapter.sol";
import {ORDERLY_BROKER} from "./lib/types/Constants.sol";

contract VaultAdapter is IVaultAdapter, Ownable2StepUpgradeable, UUPSUpgradeable {
    using Address for address payable;

    address public operator;
    address public dexVault;
    address public engine;
    address public protocolVault;

    /// @dev Broker Id => isAllowed
    mapping(bytes32 => bool) public isAllowedBroker;
    /// @dev Token string hash  => Token address
    mapping(bytes32 => address) public tokenHashToToken;
    /// @dev Determines whether the withdraw tx corresponding to the recordId is executed
    mapping(uint256 => bool) public isRecordHandled;

    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert Unauthorized();
        }
        _;
    }

    //receive native token
    receive() external payable {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initialize the contract
     * @param _operator Address with operator privileges
     * @param _dexVault DexVault contract address
     * @param _engine BE signer address
     * @param owner Owner address
     */
    function initialize(address _operator, address _dexVault, address _engine, address _usdc, address owner)
        external
        initializer
    {
        __Ownable2Step_init();
        __Ownable_init(owner);
        __UUPSUpgradeable_init();

        operator = _operator;
        dexVault = _dexVault;
        engine = _engine;

        isAllowedBroker[ORDERLY_BROKER] = true;
        tokenHashToToken[0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa] = _usdc; //USDC HASH
    }

    /// @notice withdraw native token
    /// @param to the receiver address
    /// @param amount the amount to withdraw
    function withdrawNativeToken(address payable to, uint256 amount) external onlyOwner {
        to.sendValue(amount);
    }

    /**
     * @notice Deposit native token (ETH) to the specified receiver
     * @param adapterDeposit The deposit parameters
     * @param signature The signature for validation
     */
    function depositNative(AdapterDeposit memory adapterDeposit, bytes calldata signature) external onlyOperator {
        // Process the deposit
        (uint256 fee, VaultDepositFE memory depositData) = _processDeposit(adapterDeposit, signature);
        //Transfer native tokens to the DexVault
        uint256 totalValue = adapterDeposit.amount + fee;
        IDexVault(dexVault).depositTo{value: totalValue}(adapterDeposit.receiver, depositData);

        // Emit event
        emit DepositFromCeffu(adapterDeposit, true);
    }

    /**
     * @notice Deposit ERC20 token to the specified receiver
     * @param adapterDeposit The deposit parameters
     * @param signature The signature for validation
     */
    function depositTo(AdapterDeposit memory adapterDeposit, bytes calldata signature) external onlyOperator {
        bytes32 tokenHash = adapterDeposit.tokenHash;
        // Validate ERC20 token
        address token = tokenHashToToken[tokenHash];
        if (token == address(0)) {
            revert InvalidTokenHash();
        }

        // Process the deposit
        (uint256 fee, VaultDepositFE memory depositData) = _processDeposit(adapterDeposit, signature);

        // Approve ERC20
        SafeTransferLib.safeApprove(ERC20(token), dexVault, adapterDeposit.amount);
        // Transfer ERC20 tokens to the DexVault
        IDexVault(dexVault).depositTo{value: fee}(adapterDeposit.receiver, depositData);

        // Emit event
        emit DepositFromCeffu(adapterDeposit, false);
    }

    /**
     * @notice Deposit native token (ETH) to the specified receiver
     * @param adapterDeposit The deposit parameters
     * @param signature The signature for validation
     */
    function depositNative(AdapterDepositLegacy memory adapterDeposit, bytes calldata signature) external onlyOperator {
        // Process the deposit
        (uint256 fee, VaultDepositFE memory depositData) = _processDepositLegacy(adapterDeposit, signature);
        //Transfer native tokens to the DexVault
        uint256 totalValue = adapterDeposit.amount + fee;
        IDexVault(dexVault).depositTo{value: totalValue}(adapterDeposit.receiver, depositData);

        // Emit event
        emit DepositFromCeffu(adapterDeposit, true);
    }

    function depositTo(AdapterDepositLegacy memory adapterDeposit, bytes calldata signature) external onlyOperator {
        bytes32 tokenHash = adapterDeposit.tokenHash;
        // Validate ERC20 token
        address token = tokenHashToToken[tokenHash];
        if (token == address(0)) {
            revert InvalidTokenHash();
        }

        // Process the deposit
        (uint256 fee, VaultDepositFE memory depositData) = _processDepositLegacy(adapterDeposit, signature);

        // Approve ERC20
        SafeTransferLib.safeApprove(ERC20(token), dexVault, adapterDeposit.amount);
        // Transfer ERC20 tokens to the DexVault
        IDexVault(dexVault).depositTo{value: fee}(adapterDeposit.receiver, depositData);

        // Emit event
        emit DepositFromCeffu(adapterDeposit, false);
    }

    function _processDepositLegacy(AdapterDepositLegacy memory adapterDeposit, bytes calldata signature)
        internal
        returns (uint256, VaultDepositFE memory)
    {
        // Validate recordId first to save gas in case of reverts
        if (isRecordHandled[adapterDeposit.recordId]) {
            revert RecordAlreadyHandled(adapterDeposit.recordId);
        }

        // Validate amount
        if (adapterDeposit.amount == 0) {
            revert InvalidAmount();
        }
        // Validate role type
        RoleType roleType = adapterDeposit.roleType;
        if (roleType != RoleType.LP && roleType != RoleType.SP) {
            revert InvalidRoleType();
        }

        // Validate broker
        bytes32 brokerHash = adapterDeposit.brokerHash;
        if (!isAllowedBroker[brokerHash]) revert BrokerNotAllowed();

        // Verify signature
        Signature.verifyAdapterDepositLegacy(adapterDeposit, block.chainid, signature, engine);

        // Calculate ID based on role type
        address receiver = adapterDeposit.receiver;
        bytes32 id = roleType == RoleType.LP
            ? VaultUtils.getAccountId(receiver, brokerHash)
            : VaultUtils.getStrategyProviderId(protocolVault, receiver, brokerHash);

        // Create deposit data structure
        VaultDepositFE memory depositData = VaultDepositFE({
            accountId: id,
            brokerHash: brokerHash,
            tokenHash: adapterDeposit.tokenHash,
            tokenAmount: adapterDeposit.amount
        });

        // Effect before interaction
        isRecordHandled[adapterDeposit.recordId] = true;

        // Calculate fee
        uint256 fee =
            IDexVault(dexVault).depositFeeEnabled() ? IDexVault(dexVault).getDepositFee(receiver, depositData) : 0;
        return (fee, depositData);
    }
    //--------------------------------------INTERNAL--------------------------------------------
    /**
     * @notice Process deposit logic common to both native and ERC20 deposits
     * @param adapterDeposit The deposit parameters
     * @param signature The signature for validation
     */

    function _processDeposit(AdapterDeposit memory adapterDeposit, bytes calldata signature)
        internal
        returns (uint256, VaultDepositFE memory)
    {
        // Validate recordId first to save gas in case of reverts
        if (isRecordHandled[adapterDeposit.recordId]) {
            revert RecordAlreadyHandled(adapterDeposit.recordId);
        }

        // Validate amount
        if (adapterDeposit.amount == 0) {
            revert InvalidAmount();
        }
        // Validate role type
        RoleType roleType = adapterDeposit.roleType;
        if (roleType != RoleType.LP && roleType != RoleType.SP) {
            revert InvalidRoleType();
        }

        // Validate broker
        bytes32 brokerHash = adapterDeposit.brokerHash;
        if (!isAllowedBroker[brokerHash]) revert BrokerNotAllowed();

        // Verify signature
        Signature.verifyAdapterDeposit(adapterDeposit, block.chainid, signature, engine);

        // Calculate ID based on role type
        address receiver = adapterDeposit.receiver;
        bytes32 id = roleType == RoleType.LP
            ? VaultUtils.getAccountId(receiver, brokerHash)
            : VaultUtils.getStrategyProviderId(adapterDeposit.vault, receiver, brokerHash);

        // Create deposit data structure
        VaultDepositFE memory depositData = VaultDepositFE({
            accountId: id,
            brokerHash: brokerHash,
            tokenHash: adapterDeposit.tokenHash,
            tokenAmount: adapterDeposit.amount
        });

        // Effect before interaction
        isRecordHandled[adapterDeposit.recordId] = true;

        // Calculate fee
        uint256 fee =
            IDexVault(dexVault).depositFeeEnabled() ? IDexVault(dexVault).getDepositFee(receiver, depositData) : 0;
        return (fee, depositData);
    }

    //--------------------------------------CONFIG--------------------------------------------
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) {
            revert ZeroAddress();
        }
        operator = _operator;
        emit OperatorSet(_operator);
    }

    function setDexVault(address _dexVault) external onlyOwner {
        if (_dexVault == address(0)) {
            revert ZeroAddress();
        }
        dexVault = _dexVault;
        emit DexVaultSet(_dexVault);
    }

    function setEngine(address _engine) external onlyOwner {
        if (_engine == address(0)) {
            revert ZeroAddress();
        }
        engine = _engine;
        emit EngineSet(_engine);
    }

    function setAllowedBroker(bytes32 brokerHash, bool isAllowed) external onlyOwner {
        isAllowedBroker[brokerHash] = isAllowed;
        emit BrokerAllowedSet(brokerHash, isAllowed);
    }

    function setAllowedTokenHashToToken(bytes32 tokenHash, address token) external onlyOwner {
        tokenHashToToken[tokenHash] = token;
        emit TokenHashToTokenSet(tokenHash, token);
    }

    function setProtocolVault(address _protocolVault) external onlyOwner {
        if (_protocolVault == address(0)) {
            revert ZeroAddress();
        }
        protocolVault = _protocolVault;
        emit ProtocolVaultSet(_protocolVault);
    }
}
