// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {DepositData, VaultType, PayloadType, StrategyVaultCCMessage} from "./lib/Struct.sol";

import {console} from "forge-std/console.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

/**
 * // todo
 *  - if different token, using another contract
 *  -
 */
contract ProtocolVault is Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public ledgerChainId;

    address public orderlyDexVault;
    address public crossChainManager;

    bytes32 public brokerHash;

    // uint256 miniumDepositForUser;
    // uint256 miniumDepositForSP;
    // uint256 capUserNumber;
    // uint256 fee;
    // address feeRecipient;
    //VaultState vaultState;
    mapping(bytes32 => bool) public isAllowedToken;
    mapping(bytes32 => bool) public isAllowedBroker;

    // mapping(address => uint256) userToDepositAmount;
    // mapping(address => StrategyParams) strategies;
    // mapping(address => bool) isActiveSigner;

    error InvalidDepositAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(address _crossChainManager) external initializer {
        __Ownable2Step_init();
        __Ownable_init(msg.sender); //owner() initialized to msg.sender

        __UUPSUpgradeable_init();

        crossChainManager = _crossChainManager;
        ledgerChainId = 291;
    }

    function deposit(address token, address to, uint256 amount) external payable {
        bytes32 vaultId = keccak256(abi.encodePacked(brokerHash, address(this)));
        bytes32 accountId = keccak256(abi.encodePacked(to, brokerHash));

        //_validateDeposit(depositData);

        // transfer token to this contract
        IERC20(token).safeTransferFrom(msg.sender, to, amount);

        //construct DepositData cross chain message
        DepositData memory depositData = DepositData({
            vaultType: VaultType.PROTOCOL,
            amount: amount,
            depositNonce: 0,
            token: token,
            receiver: to,
            strategyProvider: address(0),
            vault: address(this),
            vaultId: vaultId,
            accountId: accountId,
            strategyProviderId: keccak256(abi.encodePacked(address(this))),
            brokerHash: brokerHash
        });

        StrategyVaultCCMessage memory message =
            StrategyVaultCCMessage({payloadType: uint8(PayloadType.DEPOSIT), payload: abi.encode(depositData)});

        //cross-chain message
        IVaultCrossChainManager(crossChainManager).vaultSendToLedger{value: msg.value}(message);
    }

    /**
     * ledger Call ********
     */
    // function depositToOrderlyDex() external {
    //     //call dex vault

    //     // VaultTypes.VaultDepositFE memory depositDataFe = VaultTypes
    //     //     .VaultDepositFE({
    //     //         accountId: //SP id
    //     //         brokerHash:
    //     //         tokenHash:
    //     //         tokenAmount:
    //     //     });
    //     IDexVault(orderlyDexVault).deposit();
    // }

    /*======================================================================
     *   Config Functions
     *======================================================================*/

    /*======================================================================
     *   View Functions
     *======================================================================*/

    //--------------------------------------CONFIG--------------------------------------------
    function setLedgerChainId(uint256 _ledgerChainId) external onlyOwner {
        ledgerChainId = _ledgerChainId;
    }

    function setOrderlyDexVault(address _orderlyDexVault) external onlyOwner {
        orderlyDexVault = _orderlyDexVault;
    }

    function setCrossChainManager(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;
    }

    //--------------------------------------INTERNAL--------------------------------------------
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
}
