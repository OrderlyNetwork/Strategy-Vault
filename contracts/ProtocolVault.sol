// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVault} from "./interfaces/IProtocolVault.sol";
import {VaultDepositFE, IDexVault} from "./interfaces/IDexVault.sol";

import {
    VaultType,
    VaultState,
    RoleType,
    ClaimParams,
    DepositParams,
    WithdrawParams,
    OperationData,
    UserClaimedInfo
} from "./lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {UpdateUserClaim} from "./lib/types/LedgerStruct.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract ProtocolVault is Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable, IProtocolVault {
    bytes32 constant ORDERLY_BROKER = 0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b;
    bytes32 constant USDC_HASH = 0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa;
    uint256 constant LEDGER_CHAIN_ID = 291;
    uint32 constant LEDGER_EID = 30213;

    VaultState public vaultState;
    address public dexVault;
    address public crossChainManager;

    /// @dev Incremental nonce for user deposit and withdraw operation,used for requestId on ledger
    uint256 public chainNonce;
    /// @dev Minimum deposit amount for LP
    uint256 minDepositForLp;
    /// @dev Minimum deposit amount for SP
    uint256 minDepositForSp;

    /// @dev Admin address => isAllowed
    mapping(address => bool) public isAllowedAdmin;
    /// @dev User Id => UserClaimedInfo
    mapping(bytes32 => UserClaimedInfo) public userClaimedById;
    /// @dev Token => isAllowed
    mapping(address => bool) public isAllowedToken;
    /// @dev Broker Id => isAllowed
    mapping(bytes32 => bool) public isAllowedBroker;
    /// @dev allowed strategy
    mapping(address => bool) public isAllowedStrategy;
    /// @dev Token => Token hash : keccak256(abi.encodePacked(token_string))
    mapping(address => bytes32) public tokenToHash;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Require only cross chain manager can call
    modifier onlyVaultCrossChainManager() {
        if (msg.sender != crossChainManager) {
            revert InvalidCrossChainManager();
        }
        _;
    }

    /// @notice Require only dex vault can call
    modifier allowedStrategy() {
        if (!isAllowedStrategy[msg.sender]) {
            revert InvalidStrategy();
        }
        _;
    }

    /// @notice Require only admin can call
    modifier onlyOwnerOrAdmin() {
        if (!isAllowedAdmin[msg.sender] && msg.sender != owner()) {
            revert InvalidAdmin();
        }
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(
        address _dexVault,
        address owner,
        address token,
        uint256 _minDepositForLp,
        uint256 _minDepositForSp
    ) external initializer {
        __Ownable2Step_init();
        __Ownable_init(owner);

        __UUPSUpgradeable_init();

        __Pausable_init();

        dexVault = _dexVault;

        isAllowedBroker[ORDERLY_BROKER] = true;
        isAllowedToken[token] = true;
        isAllowedStrategy[_dexVault] = true;

        minDepositForLp = _minDepositForLp;
        minDepositForSp = _minDepositForSp;
    }
    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

    //--------------------------------------FROM USER-----------------------------------------
    function deposit(DepositParams memory depositParams) external payable whenNotPaused {
        bytes32 brokerHash = depositParams.brokerHash;
        address token = depositParams.token;
        uint256 amount = depositParams.amount;
        PayloadType payloadType = depositParams.payloadType;

        _validateDeposit(payloadType, token, amount, brokerHash);
        //construct cross chain message
        OperationData memory data = _getOperationData(payloadType, depositParams.receiver, amount, token, brokerHash);
        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: block.chainid,
            dstChainId: LEDGER_CHAIN_ID,
            payload: abi.encode(data)
        });

        chainNonce++;

        //transfer token to this contract
        SafeTransferLib.safeTransferFrom(ERC20(token), msg.sender, address(this), amount);

        //cross-chain
        IVaultCrossChainManager(crossChainManager).sendMessage{value: msg.value}(message);

        emit OperationExecuted(payloadType, data);
    }

    function withdraw(WithdrawParams memory withdrawParams) external payable whenNotPaused {
        bytes32 brokerHash = withdrawParams.brokerHash;
        address token = withdrawParams.token;
        uint256 amount = withdrawParams.amount;
        PayloadType payloadType = withdrawParams.payloadType;

        _validateBasic(token, brokerHash);

        //construct OperationData
        OperationData memory data = _getOperationData(payloadType, msg.sender, amount, token, brokerHash);

        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: block.chainid,
            dstChainId: LEDGER_CHAIN_ID,
            payload: abi.encode(data)
        });

        chainNonce++;

        //cross-chain message
        IVaultCrossChainManager(crossChainManager).sendMessage{value: msg.value}(message);

        emit OperationExecuted(payloadType, data);
    }

    function claim(ClaimParams memory claimParams) external whenNotPaused {
        bytes32 id;
        bytes32 brokerHash = claimParams.brokerHash;

        if (claimParams.roleType == RoleType.LP) {
            id = _getAccountId(msg.sender, brokerHash);
        } else if (claimParams.roleType == RoleType.SP) {
            id = _getStrategyProviderId(msg.sender, brokerHash);
        } else {
            revert InvalidRoleType();
        }

        //check
        uint256 amount = userClaimedById[id].unClaimedAssets;
        if (amount == 0) {
            revert NotEnoughUnclaimedAssets();
        }

        //effect
        userClaimedById[id].unClaimedAssets = 0;
        delete userClaimedById[id].requestIds;

        //transfer to user
        SafeTransferLib.safeTransfer(ERC20(claimParams.token), msg.sender, amount);

        emit UserClaimed(amount, userClaimedById[id].requestIds);
    }

    //--------------------------------------FROM DEX-----------------------------------------
    function depositFromStrategy(uint256 periodId, address sender, uint256 amount) external allowedStrategy {
        bytes32 vaultId = _getVaultId(ORDERLY_BROKER);
        emit DepositFromStrategy(periodId, vaultId, sender, amount);
    }

    //--------------------------------------FROM LEDGER-----------------------------------------
    function depositToStrategy(uint256 periodId, address receiver, uint256 amount)
        external
        onlyVaultCrossChainManager
    {
        bytes32 vaultId = _getVaultId(ORDERLY_BROKER);

        VaultDepositFE memory depositDataFe = VaultDepositFE({
            accountId: vaultId,
            brokerHash: ORDERLY_BROKER,
            tokenHash: USDC_HASH,
            tokenAmount: uint128(amount)
        });

        //cal dex
        uint256 fee = IDexVault(dexVault).getDepositFee(address(this), depositDataFe);
        IDexVault(dexVault).depositTo{value: fee}(address(this), depositDataFe);

        emit DepositToStrategy(periodId, vaultId, receiver, amount);
    }

    function updateUnClaimed(uint256 periodId, UpdateUserClaim[] memory updateUserClaims)
        external
        onlyVaultCrossChainManager
    {
        for (uint256 i = 0; i < updateUserClaims.length; i++) {
            bytes32 userId = updateUserClaims[i].userId;
            userClaimedById[userId].unClaimedAssets += updateUserClaims[i].amount;
            userClaimedById[userId].requestIds.push(updateUserClaims[i].requestId);
        }

        emit UnClaimedUpdated(periodId, updateUserClaims);
    }

    //--------------------------------------CONFIG--------------------------------------------
    function setOrderlyDexVault(address _dexVault) external onlyOwner {
        dexVault = _dexVault;
    }

    function setCrossChainManager(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;
    }

    function setMinDepositForLP(uint256 amount) external onlyOwner {
        minDepositForLp = amount;
    }

    function setMinDepositForSP(uint256 amount) external onlyOwner {
        minDepositForSp = amount;
    }

    function setAdmin(address admin, bool isAllowed) external onlyOwner {
        isAllowedAdmin[admin] = isAllowed;
    }

    function emergencyPause() public whenNotPaused onlyOwnerOrAdmin {
        _pause();
    }

    function emergencyUnpause() public whenPaused onlyOwner {
        _unpause();
    }

    function setVaultState(VaultState _vaultState) public onlyOwner {
        vaultState = _vaultState;

        emit VaultStateChanged(_vaultState);
    }
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function getUserClaimedInfo(bytes32 userId) public view returns (UserClaimedInfo memory) {
        return userClaimedById[userId];
    }

    function quoteOperation() public view returns (uint256) {
        OperationData memory data = _getOperationData(PayloadType.LP_DEPOSIT, address(0), 0, address(0), ORDERLY_BROKER);
        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: PayloadType.LP_DEPOSIT,
            srcChainId: block.chainid,
            dstChainId: LEDGER_CHAIN_ID,
            payload: abi.encode(data)
        });
        bytes memory lzMessage = abi.encode(message);

        (uint256 nativeFee,) =
            IVaultCrossChainManager(crossChainManager).quote(LEDGER_EID, lzMessage, PayloadType.LP_DEPOSIT, false);
        return nativeFee;
    }
    /*========================================================`=================================
    *                                       INTERNAL
    *=========================================================================================*/

    function _validateDeposit(PayloadType payloadType, address token, uint256 amount, bytes32 brokerHash)
        internal
        view
    {
        _validateBasic(token, brokerHash);

        if (
            amount == 0 || (payloadType == PayloadType.LP_DEPOSIT && amount < minDepositForLp)
                || (payloadType == PayloadType.SP_DEPOSIT && amount < minDepositForSp)
        ) revert InvalidDepositAmount();
    }

    function _validateBasic(address token, bytes32 brokerHash) internal view {
        if (vaultState == VaultState.CLOSED) revert VaultClosed();
        if (!isAllowedToken[token]) revert TokenNotAllowed();
        if (!isAllowedBroker[brokerHash]) revert BrokerNotAllowed();
    }

    function _getOperationData(PayloadType payloadType, address receiver, uint256 amount, address, bytes32 brokerHash)
        internal
        view
        returns (OperationData memory)
    {
        bytes32 accountId;
        bytes32 strategyProviderId;

        if (payloadType == PayloadType.LP_DEPOSIT || payloadType == PayloadType.LP_WITHDRAW) {
            accountId = _getAccountId(receiver, brokerHash);
        } else if (payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.SP_WITHDRAW) {
            strategyProviderId = _getStrategyProviderId(receiver, brokerHash);
        } else {
            revert InvalidPayloadType();
        }

        //construct OperationData cross chain message
        OperationData memory operationData = OperationData({
            vaultType: VaultType.PROTOCOL,
            sender: msg.sender,
            receiver: receiver,
            chainNonce: chainNonce,
            amount: amount,
            vaultId: _getVaultId(brokerHash),
            accountId: accountId,
            strategyProviderId: strategyProviderId,
            tokenHash: USDC_HASH,
            brokerHash: brokerHash
        });

        return operationData;
    }

    function _getAccountId(address account, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, brokerHash));
    }

    function _getStrategyProviderId(address strategyProvider, bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encode(address(this), strategyProvider, brokerHash));
    }

    function _getVaultId(bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encode(address(this), brokerHash));
    }
}
