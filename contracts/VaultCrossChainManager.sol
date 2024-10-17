// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

import {DepositData} from "./lib/Struct.sol";
import {console} from "forge-std/console.sol";

contract VaultCrossChainManager is OApp {
    error InvalidPayloadType();

    using OptionsBuilder for bytes;

    uint32 public LEDGER_EID;
    address public ledger;

    constructor(
        address endpoint,
        address delegate
    ) OApp(endpoint, delegate) Ownable(msg.sender) {
        LEDGER_EID = ILayerZeroEndpointV2(endpoint).eid();
    }

    function testCounter() external {
        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(50000, 0);

        MessagingFee memory messageFee = _quote(LEDGER_EID, "", options, false);

        _lzSend(
            LEDGER_EID,
            "",
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
    function _lzReceive(
        Origin calldata _origin,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal virtual override {}
}
