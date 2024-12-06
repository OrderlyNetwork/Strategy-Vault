// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVault} from "./interfaces/IProtocolVault.sol";
import {VaultType, RoleType, OperationParams, OperationData, UserClaimedInfo} from "./lib/types/VaultStruct.sol";
import {PayloadType,StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {UpdateUserClaim} from "./lib/types/LedgerStruct.sol";
import {console} from "forge-std/console.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";
//todo 1. 是否要限制只有dex vault才能调用 当transfer fund 2. constant 3. 校验相关的配置要在evm还是ledger
contract ProtocolVault is Ownable2StepUpgradeable, UUPSUpgradeable, IProtocolVault {
    using SafeERC20 for IERC20;

    uint256 public ledgerChainId;

    address public dexVault;
    address public crossChainManager;

    uint256 public chainNonce;
    //uint256 miniumDepositForUser;
    // uint256 miniumDepositForSP;
    // uint256 capUserNumber;
    // uint256 fee;
    // address feeRecipient;
    //VaultState vaultState;

    /// @dev AccountId or SPId => UserClaimedInfo
    mapping(bytes32 => UserClaimedInfo) public userClaimedById;

    mapping(bytes32 => address) public allowedToken;
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

    function initialize(address _crossChainManager) external initializer {
        __Ownable2Step_init();
        __Ownable_init(msg.sender); //owner() initialized to msg.sender

        __UUPSUpgradeable_init();

        crossChainManager = _crossChainManager; 
        ledgerChainId = 291;
    }
    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

    function executeOperation(OperationParams memory operationParams) external payable {
        PayloadType payloadType = operationParams.payloadType;
        bytes32 brokerHash = operationParams.brokerHash;
        bytes32 tokenHash = operationParams.tokenHash;
        address token = allowedToken[tokenHash];

        if (token == address(0)) {
            revert NotAllowedToken();
        }

        bytes32 vaultId;
        bytes32 accountId;
        bytes32 strategyProviderId;

        if (payloadType == PayloadType.LP_DEPOSIT) {
            vaultId = _getVaultId(brokerHash);
            accountId = _getAccountId(msg.sender, brokerHash);
        } else if (payloadType == PayloadType.SP_DEPOSIT) {
            strategyProviderId = _getStrategyProviderId(msg.sender, brokerHash);
        } else if (payloadType == PayloadType.LP_WITHDRAW) {
            strategyProviderId = _getAccountId(msg.sender, brokerHash);
        } else if (payloadType == PayloadType.SP_WITHDRAW) {
            strategyProviderId = _getStrategyProviderId(msg.sender, brokerHash);
        }

        //transfer token to this contract
        uint256 amount = operationParams.amount;
        IERC20(token).safeTransferFrom(msg.sender, msg.sender, amount);
        //construct OperationData cross chain message
        OperationData memory operationData = OperationData({
            vaultType: VaultType.PROTOCOL,
            sender: msg.sender,
            receiver: operationParams.receiver,
            chainNonce: chainNonce,
            amount: amount,
            vaultId: vaultId,
            accountId: accountId,
            strategyProviderId: strategyProviderId,
            tokenHash: operationParams.tokenHash,
            brokerHash: brokerHash
        });

        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: uint32(block.chainid),
            dstChainId: uint32(ledgerChainId),
            payload: abi.encode(operationData)
        });
        //cross-chain message
        //IVaultCrossChainManager(crossChainManager).vaultSendToLedger{value: msg.value}(message);

        emit OperationExecuted(operationData);
    }

    function claim(RoleType roleType, uint256 amount, bytes32 brokerHash, bytes32 tokenHash) external {
        bytes32 id;
        address token = allowedToken[tokenHash];

        if (roleType == RoleType.LP) {
            id = _getAccountId(msg.sender, brokerHash);
            _valitateClaim(id, amount);
        } else if (roleType == RoleType.SP) {
            id = _getStrategyProviderId(msg.sender, brokerHash);
            _valitateClaim(id, amount);
        } else {
            revert InvalidRoleType();
        }

        //transfer to user
        IERC20(token).safeTransfer(msg.sender, amount);

        //effect
        userClaimedById[id].unClaimedAssets -= amount;

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
    function _validateDeposit(uint256 amount) internal view {
        // check if tokenHash and brokerHash are allowed
        // if (!isAllowedToken[data.token]) revert TokenNotAllowed();
        // if (!isAllowedBroker[data.brokerHash]) revert BrokerNotAllowed();
        // // check if accountId = keccak256(abi.encodePacked(brokerHash, receiver))
        // if (!Utils.validateAccountId(data.accountId, data.brokerHash, receiver))
        //     revert AccountIdInvalid();
        // check if tokenAmount > 0
        if (amount == 0) revert InvalidDepositAmount();
    }

    function _valitateClaim(bytes32 id, uint256 amount) internal view {
        if (amount > userClaimedById[id].unClaimedAssets) {
            revert NotEnoughUnclaimedAssets();
        }
    }

    function _getAccountId(address account, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, brokerHash));
    }

    function _getStrategyProviderId(address strategyProvider, bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), strategyProvider, brokerHash));
    }

    function _getVaultId(bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(brokerHash, address(this)));
    }
}
