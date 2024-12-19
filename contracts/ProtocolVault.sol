// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVault} from "./interfaces/IProtocolVault.sol";
import {
    VaultType,
    RoleType,
    ClaimParams,
    DepositParams,
    WithdrawParams,
    OperationData,
    UserClaimedInfo
} from "./lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {UpdateUserClaim} from "./lib/types/LedgerStruct.sol";
import {console} from "forge-std/console.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract ProtocolVault is Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable, IProtocolVault {
    bytes32 constant ORDERLY_BROKER = 0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b;
    uint256 constant LEDGER_CHAIN_ID = 291;

    uint32 public ledgerEid;
    address public dexVault;
    address public crossChainManager;

    uint256 public chainNonce;
    uint256 minDepositForLp;
    uint256 minDepositForSp;

    /// @dev User Id => UserClaimedInfo
    mapping(bytes32 => UserClaimedInfo) public userClaimedById;
    /// @dev Token => isAllowed
    mapping(address => bool) public isAllowedToken;
    /// @dev Broker Id => isAllowed
    mapping(bytes32 => bool) public isAllowedBroker;

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
    modifier onlyDexVault() {
        if (msg.sender != dexVault) {
            revert InvalidDexVault();
        }
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(
        address _dexVault,
        address _crossChainManager,
        address owner,
        address token,
        uint256 _minDepositForLp,
        uint256 _minDepositForSp
    ) external initializer {
        __Ownable2Step_init();
        __Ownable_init(owner);

        __UUPSUpgradeable_init();

        __Pausable_init();

        crossChainManager = _crossChainManager;
        dexVault = _dexVault;

        isAllowedBroker[ORDERLY_BROKER] = true;
        isAllowedToken[token] = true;

        ledgerEid = 30213;

        minDepositForLp = _minDepositForLp;
        minDepositForSp = _minDepositForSp;
    }
    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

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
        uint256 amount = claimParams.amount;
        _valitateClaim(id, amount);

        //effect
        userClaimedById[id].unClaimedAssets -= amount;

        //transfer to user
        SafeTransferLib.safeTransfer(ERC20(claimParams.token), msg.sender, amount);

        emit UserClaimed(amount, userClaimedById[id].requestIds);
    }

    //--------------------------------------FROM DEX-----------------------------------------

    function depositFromStrategy(uint256 periodId, address sender, uint256 amount) external onlyDexVault {
        bytes32 vaultId = _getVaultId(ORDERLY_BROKER);
        emit DepositFromStrategy(periodId, vaultId, sender, amount);
    }
    //--------------------------------------FROM Ledger-----------------------------------------

    function depositToStrategy(uint256 periodId, address receiver, uint256 amount)
        external
        onlyVaultCrossChainManager
    {
        //console.log("welcome to depositToStrategy");

        bytes32 vaultId = _getVaultId(ORDERLY_BROKER);
        //console.log("welcome to depositToStrategy");
        // VaultTypes.VaultDepositFE memory depositDataFe = VaultTypes
        //     .VaultDepositFE({
        //         accountId: //SP id
        //         brokerHash:
        //         tokenHash:
        //         tokenAmount:
        //     });
        //cal dex
        //     IDexVault(orderlyDexVault).deposit();

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

    function setLedgerEid(uint32 eid) external onlyOwner {
        ledgerEid = eid;
    }

    function emergencyPause() public whenNotPaused onlyOwner {
        _pause();
    }

    function emergencyUnpause() public whenPaused onlyOwner {
        _unpause();
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
            IVaultCrossChainManager(crossChainManager).quote(ledgerEid, lzMessage, PayloadType.LP_DEPOSIT, false);
        return nativeFee;
    }
    /*=========================================================================================
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
        if (msg.value < quoteOperation()) revert NotEnoughFee();
        if (!isAllowedToken[token]) revert TokenNotAllowed();
        if (!isAllowedBroker[brokerHash]) revert BrokerNotAllowed();
    }

    function _valitateClaim(bytes32 id, uint256 amount) internal view {
        if (amount > userClaimedById[id].unClaimedAssets) {
            revert NotEnoughUnclaimedAssets();
        }
    }

    function _getOperationData(
        PayloadType payloadType,
        address receiver,
        uint256 amount,
        address token,
        bytes32 brokerHash
    ) internal view returns (OperationData memory) {
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
        bytes32 vaultId = _getVaultId(brokerHash);
        bytes32 tokenHash = keccak256(abi.encodePacked(token));

        OperationData memory operationData = OperationData({
            vaultType: VaultType.PROTOCOL,
            sender: msg.sender,
            receiver: receiver,
            chainNonce: chainNonce,
            amount: amount,
            vaultId: vaultId,
            accountId: accountId,
            strategyProviderId: strategyProviderId,
            tokenHash: tokenHash,
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
