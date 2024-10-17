// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {DepositData, VaultType, PayloadType, StrategyVaultCCMessage} from "./lib/Struct.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract ProtocolVault is Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeTransferLib for ERC20;

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

    // mapping(address => uint256) userToDepositAmount;
    // mapping(address => StrategyParams) strategies;
    // mapping(address => bool) isActiveSigner;
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function initialize(address _crossChainManager) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        crossChainManager = _crossChainManager;
        ledgerChainId = 291;
    }

    function testIncrementCounter() external {
        IVaultCrossChainManager(crossChainManager).testCounter();
    }

    function deposit(address token, address to, uint256 amount) external {
        //calculate idex
        bytes32 vaultId = keccak256(
            abi.encodePacked(brokerHash, address(this))
        );

        bytes32 accountId = keccak256(abi.encodePacked(to, brokerHash));
        //_validateDeposit(depositData);

        // transfer token to this contract
        ERC20(token).safeTransfer(to, amount);

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

        StrategyVaultCCMessage
            memory strategyVaultCCMessage = StrategyVaultCCMessage({
                dstChainId: ledgerChainId,
                payloadType: PayloadType.DEPOSIT,
                payload: abi.encode(depositData)
            });

        //cross-chain message
        IVaultCrossChainManager(crossChainManager).vaultSendToLedger(
            strategyVaultCCMessage
        );
    }

    /******ledger Call *********/
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


    /*======================================================================
     *   Internal Functions
     *======================================================================*/

    /// @notice The function to validate deposit data
    // function _validateDeposit(
    //     VaultTypes.VaultDepositFE calldata data
    // ) internal view {
    //     // check if tokenHash and brokerHash are allowed
    //     if (!allowedTokenSet.contains(data.tokenHash)) revert TokenNotAllowed();
    //     if (!allowedBrokerSet.contains(data.brokerHash))
    //         revert BrokerNotAllowed();
    //     // check if accountId = keccak256(abi.encodePacked(brokerHash, receiver))
    //     if (!Utils.validateAccountId(data.accountId, data.brokerHash, receiver))
    //         revert AccountIdInvalid();
    //     // check if tokenAmount > 0
    //     if (data.tokenAmount == 0) revert ZeroDeposit();
    //     //  check vault type
    // }
}
