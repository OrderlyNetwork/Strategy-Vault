// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DepositData} from "./lib/Struct.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract UserVault is Ownable2StepUpgradeable, UUPSUpgradeable {
    event VaultCreated(bytes32 indexed vaultId, address indexed owner);

    struct UserVaultInfo {
        address owner;
        uint256 assets;
        bool isActive;
    }

    mapping(bytes32 => UserVaultInfo) userVaultbyId;

    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    function createUserVault(
        uint256 initialAssets,
        bytes32 brokerHash
    ) external {
        //calcalute vault id
        bytes32 vaultId = keccak256(
            abi.encodePacked(address(this), msg.sender, brokerHash)
        );
        //check only one actice user vault
        //initialize vault
        userVaultbyId[vaultId] = UserVaultInfo({
            owner: msg.sender,
            assets: initialAssets,
            isActive: true
        });

        emit VaultCreated(vaultId, msg.sender);
    }

    /******User Call *********/
    function deposit(uint256 amount, address to, address vaultOwner) external {
        //calculate or validate id
        bytes32 vaultId = keccak256(
            abi.encodePacked(address(this), vaultOwner, brokerHash)
        );

        bytes32 accountId = keccak256(abi.encodePacked(to, brokerHash));
        _validateDeposit(depositData);

        // transfer token to this contract

        // send cross-chain message
        StrategyVaultMessage memory SVMessage = StrategyVaultMessage();
        IVaultCrossChainManager(crossChainManagerAddress).deposit(SVMessage);
    }

    function deposit(
        address token,
        address to,
        address strategyProvider,
        uint256 amount,
        bytes32 brokerHash
    ) external {
        //calculate index
        bytes32 vaultId = keccak256(
            abi.encodePacked(address(this), strategyProvider, brokerHash)
        );
        bytes32 accountId = keccak256(abi.encodePacked(to, brokerHash));

        //_validateDeposit(depositData);

        // transfer token to this contract
        ERC20(token).safeTransfer(to, amount);

        //construct DepositData cross chain message
        DepositData memory depositData = DepositData({
            vaultType: VaultType.USER,
            amount: amount,
            depositNonce: 0,
            token: token,
            receiver: to,
            strategyProvider: address(0),
            vault: address(this),
            vaultId: vaultId,
            accountId: accountId,
            strategyProviderId: vaultId,
            brokerHash: brokerHash
        });
        StrategyVaultCCMessage
            memory strategyVaultCCMessage = StrategyVaultCCMessage({
                dstChainId: LEDGER_ID,
                payloadType: PayloadType.DEPOSIT,
                payload: abi.encode(depositData)
            });

        //cross-chain message
        IVaultCrossChainManager(crossChainManagerAddress).vaultSendToLedger(
            strategyVaultCCMessage
        );
    }

    /******ledger Call *********/
    function depositToOrderlyDex() external {
        //call dex vault

        // VaultTypes.VaultDepositFE memory depositDataFe = VaultTypes
        //     .VaultDepositFE({
        //         accountId: //SP's
        //         brokerHash:
        //         tokenHash:
        //         tokenAmount:
        //     });
        IDexVault(orderlyDexVault).deposit();
    }
}
