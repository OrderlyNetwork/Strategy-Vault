// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {DepositData} from "../lib/Struct.sol";

contract VaultCrossChainManager is UUPSUpgradeable {
    error InvalidPayloadType();

    uint256 public LEDGER_EID;
    address public ledger;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function initialize() external initializer {
        __UUPSUpgradeable_init();

        LEDGER_EID = 30213;
    }

    function testCounter() external {
        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(50000, 0);

        MessagingFee memory messageFee = _quote(
            LEDGER_EID,
            strategyVaultCCMessage.payload,
            options,
            false
        );

        _lzSend(
            LEDGER_EID,
            strategyVaultCCMessage.payload,
            options,
            // Fee in native gas and ZRO token.
            messageFee,
            // Refund address in case of failed source message.
            payable(msg.sender)
        );
    }

    // function vaultSendToLedger(
    //     StrategyVaultCCMessage memory strategyVaultCCMessage
    // ) external {
    //     bytes memory options = OptionsBuilder
    //         .newOptions()
    //         .addExecutorLzReceiveOption(50000, 0);

    //     MessagingFee memory messageFee = _quote(
    //         LEDGER_EID,
    //         strategyVaultCCMessage.payload,
    //         options,
    //         false
    //     );

    //     _lzSend(
    //         LEDGER_EID,
    //         strategyVaultCCMessage.payload,
    //         options,
    //         // Fee in native gas and ZRO token.
    //         messageFee,
    //         // Refund address in case of failed source message.
    //         payable(msg.sender)
    //     );
    // }

    // function ledgerSendToVault(
    //     StrategyVaultCCMessage memory strategyVaultCCMessage
    // ) internal {
    //     // Encodes the message before invoking _lzSend.
    //     // Replace with whatever data you want to send!
    //     bytes memory payload = svMessage.payload;
    //     _lzSend(
    //         LEDGER_ID,
    //         payload,
    //         options,
    //         // Fee in native gas and ZRO token.
    //         MessagingFee(msg.value, 0),
    //         // Refund address in case of failed source message.
    //         payable(msg.sender)
    //     );
    // }

    // //
    // function _lzReceive(
    //     Origin calldata _origin, // struct containing info about the message sender
    //     bytes32 _guid, // global packet identifier
    //     bytes calldata payload, // encoded message payload being received
    //     address _executor, // the Executor address.
    //     bytes calldata _extraData // arbitrary data appended by the Executor
    // ) internal override {
    //     // Decode the payload
    //     if (payload.payloadType == PayloadType.DEPOSIT) {
    //         DepositData memory depositData = abi.decode(payload, (DepositData));
    //         // call ledger vaultDeposit function
    //         ledger.vaultDeposit(depositData);
    //     } else {
    //         revert InvalidPayloadType();
    //     }
    // }
}
