// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVault} from "./interfaces/IProtocolVault.sol";
import {
    VaultType,
    RoleType,
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
//todo 1. 是否要限制只有dex vault才能调用 当transfer fund 2. constant 3. 校验相关的配置要在evm还是ledger
contract ProtocolVault is Ownable2StepUpgradeable, UUPSUpgradeable, IProtocolVault {
    using SafeERC20 for IERC20;

    bytes32 constant ORDERLY_BROKER = 0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b;

    uint256 public ledgerChainId;

    address public dexVault;
    address public crossChainManager;

    uint256 public chainNonce;
    uint256 minDepositForLp;
    uint256 minDepositForSp;
    // uint256 capUserNumber;
    // uint256 fee;
    // address feeRecipient;

    /// @dev AccountId or SPId => UserClaimedInfo
    mapping(bytes32 => UserClaimedInfo) public userClaimedById;

    mapping(address => bool) public isAllowedToken;
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
        address _crossChainManager,
        address owner,
        address token,
        uint256 _minDepositForLp,
        uint256 _minDepositForSp
    ) external initializer {
        __Ownable2Step_init();
        __Ownable_init(owner);

        __UUPSUpgradeable_init();

        crossChainManager = _crossChainManager;
        ledgerChainId = 291;

        isAllowedBroker[ORDERLY_BROKER] = true;
        isAllowedToken[token] = true;
        
        minDepositForLp = _minDepositForLp;
        minDepositForSp = _minDepositForSp;
    }
    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

    function deposit(DepositParams memory depositParams) external payable {
        bytes32 brokerHash = depositParams.brokerHash;
        address token = depositParams.token;
        uint256 amount = depositParams.amount;
        PayloadType payloadType = depositParams.payloadType;

        _validateDeposit(payloadType, token, amount, brokerHash);

        //construct OperationData cross chain message
        OperationData memory data = _getOperationData(payloadType, depositParams.receiver, amount, token, brokerHash);
        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: uint32(block.chainid),
            dstChainId: uint32(ledgerChainId),
            payload: abi.encode(data)
        });

        //transfer token to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        //cross-chain message
        IVaultCrossChainManager(crossChainManager).vaultSendToLedger{value: msg.value}(message);

        emit OperationExecuted(payloadType, data);
    }

    function withdraw(WithdrawParams memory withdrawParams) external payable {
        bytes32 brokerHash = withdrawParams.brokerHash;
        address token = withdrawParams.token;
        uint256 amount = withdrawParams.amount;
        PayloadType payloadType = withdrawParams.payloadType;

        _vailidateBasicInfo(token, brokerHash);

        //construct OperationData
        OperationData memory data = _getOperationData(payloadType, msg.sender, amount, token, brokerHash);

        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: uint32(block.chainid),
            dstChainId: uint32(ledgerChainId),
            payload: abi.encode(data)
        });

        //cross-chain message
        IVaultCrossChainManager(crossChainManager).vaultSendToLedger{value: msg.value}(message);

        emit OperationExecuted(payloadType, data);
    }

    function claim(RoleType roleType, uint256 amount, bytes32 brokerHash, address token) external {
        bytes32 id;

        if (roleType == RoleType.LP) {
            id = _getAccountId(msg.sender, brokerHash);
            _valitateClaim(id, amount);
        } else if (roleType == RoleType.SP) {
            id = _getStrategyProviderId(msg.sender, brokerHash);
            _valitateClaim(id, amount);
        } else {
            revert InvalidRoleType();
        }
        //effect
        userClaimedById[id].unClaimedAssets -= amount;

        //transfer to user
        IERC20(token).safeTransfer(msg.sender, amount);
        emit UserClaimed(amount, userClaimedById[id].requests);
    }

    //--------------------------------------FROM DEX-----------------------------------------

    function depositFromDex(uint256 periodId, uint256 amount) external onlyDexVault {
        emit DepositFromDex(periodId, amount);
    }
    //--------------------------------------FROM Ledger-----------------------------------------

    function depositToStrategy() external onlyVaultCrossChainManager {
        //check vault ID
        // bytes32 vaultId = keccak256(abi.encodePacked(strategyExecution.brokerHash, address(this)));

        // VaultTypes.VaultDepositFE memory depositDataFe = VaultTypes
        //     .VaultDepositFE({
        //         accountId: //SP id
        //         brokerHash:
        //         tokenHash:
        //         tokenAmount:
        //     });
        //cal dex
        //     IDexVault(orderlyDexVault).deposit();
    }

    function updateUnClaimed(uint256 periodId, UpdateUserClaim[] memory updateUserClaims)
        external
        onlyVaultCrossChainManager
    {
        emit UnClaimedUpdated(periodId, updateUserClaims);
    }

    //--------------------------------------CONFIG--------------------------------------------
    function setLedgerChainId(uint256 _ledgerChainId) external onlyOwner {
        ledgerChainId = _ledgerChainId;
    }

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

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        //withdraw all token to owner
    }
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/
    // function getEstimateFee() public view returns (uint256) {
    //     bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

    //     (uint256 nativeFee,) = IVaultCrossChainManager(crossChainManager).quote(ledgerEid, buildCCMessage(), options, false);
    //     return nativeFee;
    // }
    /*=========================================================================================
    *                                       INTERNAL
    *=========================================================================================*/
    function _validateDeposit(PayloadType payloadType, address token, uint256 amount, bytes32 brokerHash)
        internal
        view
    {
        _vailidateBasicInfo(token, brokerHash);

        if (
            amount == 0 || (payloadType == PayloadType.LP_DEPOSIT && amount < minDepositForLp)
                || (payloadType == PayloadType.SP_DEPOSIT && amount < minDepositForSp)
        ) revert InvalidDepositAmount();
    }

    function _vailidateBasicInfo(address token, bytes32 brokerHash) internal view {
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
        bytes32 vaultId = _getVaultId(brokerHash);
        bytes32 accountId;
        bytes32 strategyProviderId;

        if (payloadType == PayloadType.LP_DEPOSIT || payloadType == PayloadType.LP_WITHDRAW) {
            accountId = _getAccountId(receiver, brokerHash);
        } else if (payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.SP_WITHDRAW) {
            strategyProviderId = _getStrategyProviderId(receiver, brokerHash);
        } else {
            revert InvalidPayloadType();
        }

        bytes32 tokenHash = keccak256(abi.encodePacked(token));

        //construct OperationData cross chain message
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
        return keccak256(abi.encodePacked(account, brokerHash));
    }

    function _getStrategyProviderId(address strategyProvider, bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), strategyProvider, brokerHash));
    }

    function _getVaultId(bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), brokerHash));
    }
}
