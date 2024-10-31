// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {DepositData, VaultType, PayloadType, StrategyVaultCCMessage, UserVaultInfo} from "./lib/Struct.sol";
import {console} from "forge-std/console.sol";

contract UserVault is Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    event VaultCreated(bytes32 indexed vaultId, address indexed owner);

    error VaultAlreadyExisted();
    error InvalidMinInitialDeposit();
    error BrokerNotAllowed();
    error NotActiveVault();

    uint256 public ledgerChainId;
    uint256 public minInitialDeposit;

    address public crossChainManager;

    mapping(bytes32 => UserVaultInfo) userVaultbyId;
    mapping(bytes32 => bool) public isAllowedToken;
    mapping(bytes32 => bool) public isAllowedBroker;

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

    function createUserVault(uint256 initialAmount, bytes32 brokerHash) external {
        bytes32 vaultId = keccak256(abi.encodePacked(address(this), msg.sender, brokerHash));

        //validate only one actice user vault
        if (userVaultbyId[vaultId].isActive) {
            revert VaultAlreadyExisted();
        }
        //validate minium deposit amount
        if (initialAmount < minInitialDeposit) {
            revert InvalidMinInitialDeposit();
        }
        //validate allowed broker
        if (!isAllowedBroker[brokerHash]) {
            revert BrokerNotAllowed();
        }

        //initialize vault
        userVaultbyId[vaultId] = UserVaultInfo({owner: msg.sender, balance: initialAmount, isActive: true});

        emit VaultCreated(vaultId, msg.sender);
    }

    /**
     * User Call ********
     */
    function deposit(address token, address to, address vaultOwner, uint256 amount, bytes32 brokerHash)
        external
        payable
    {
        //calculate or validate id
        bytes32 vaultId = keccak256(abi.encodePacked(address(this), vaultOwner, brokerHash));

        bytes32 accountId = keccak256(abi.encodePacked(to, brokerHash));
        //_validateDeposit(depositData);

        // transfer token to this contract
        IERC20(token).safeTransferFrom(msg.sender, to, amount);

        //construct DepositData cross chain message
        DepositData memory depositData = DepositData({
            vaultType: VaultType.USER,
            amount: amount,
            depositNonce: 0, //todo
            token: token,
            receiver: to,
            strategyProvider: vaultOwner,
            vault: address(this),
            vaultId: vaultId,
            accountId: accountId,
            strategyProviderId: vaultId,
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
    //     //         accountId: //SP's
    //     //         brokerHash:
    //     //         tokenHash:
    //     //         tokenAmount:
    //     //     });
    //     //IDexVault(orderlyDexVault).deposit();
    // }

    //--------------------------------------CONFIG--------------------------------------------
    function setMinInitialDeposit(uint256 _minInitialDeposit) external onlyOwner {
        minInitialDeposit = _minInitialDeposit;
    }

    function setCrossChainManager(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;
    }

    //--------------------------------------INTERNAL--------------------------------------------
    function _validateDeposit(bytes32 vaultId) internal {
        //vault must be active
        if (!userVaultbyId[vaultId].isActive) {
            revert NotActiveVault();
        }
    }
}
