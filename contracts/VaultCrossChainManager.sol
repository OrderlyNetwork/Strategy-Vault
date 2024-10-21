// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// oz imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// lz imports
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

// dev imports
import {DepositData, StrategyVaultCCMessage, PayloadType} from "./lib/Struct.sol";
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IStrategyVaultLedger} from "./interfaces/IStrategyVaultLedger.sol";

import {console} from "forge-std/console.sol";

/**
 * todo:
 *  - lz gas estimate
 * - lz send require vault equal quote fee
 *
 */

contract VaultCrossChainManager is OApp {
    error InvalidPayloadType();

    using OptionsBuilder for bytes;

    uint32 public eid;
    uint32 public dstEid;
    address public svLedger;

    constructor(
        address endpoint,
        address delegate
    ) OApp(endpoint, delegate) Ownable(msg.sender) {
        eid = ILayerZeroEndpointV2(endpoint).eid();
    }

    function vaultSendToLedger(
        StrategyVaultCCMessage memory message
    ) external payable {

        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(50000, 0);

        bytes memory lzMessage = encodeLzMsg(
            message.payloadType,
            message.payload
        );

        MessagingFee memory messageFee = _quote(
            dstEid,
            lzMessage,
            options,
            false
        );
        _lzSend(
            dstEid,
            lzMessage,
            options,
            // Fee in native gas and ZRO token.
            messageFee,
            // Refund address in case of failed source message.
            payable(msg.sender)
        );
    }

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

    function _lzReceive(
        Origin calldata _origin,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal virtual override {
        //Decode the payload by payloadType
        (uint8 payloadType, bytes memory payload) = decodeLzMsg(_message);
        if (payloadType == uint8(PayloadType.DEPOSIT)) {
            DepositData memory depositData = abi.decode(payload, (DepositData));
            //call ledger vaultDeposit function
            IStrategyVaultLedger(svLedger).vaultDeposit(depositData);
        } else {
            revert InvalidPayloadType();
        }
    }

    //--------------------------------------CONFIG--------------------------------------------

    function setDstEid(uint32 _dstEid) external onlyOwner {
        dstEid = _dstEid;
    }
    function setSvLedger(address _svLedger) external onlyOwner {
        svLedger = _svLedger;
    }

    //--------------------------------------VIEW--------------------------------------------

    function quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        //        bytes memory options = combineOptions(_eid, _type, _options);
        MessagingFee memory fee = _quote(
            _dstEid,
            _message,
            _options,
            _payInLzToken
        );
        return (fee.nativeFee, fee.lzTokenFee);
    }

    //--------------------------------------INTERNAL--------------------------------------------

    function encodeLzMsg(
        uint8 msgType,
        bytes memory payload
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(msgType), payload);
    }

    function decodeLzMsg(
        bytes calldata message
    ) internal pure returns (uint8 msgType, bytes memory payload) {
        //decode msg type and payload
        uint8 MSG_TYPE_OFFSET = 1;
        msgType = uint8(bytes1(message[:MSG_TYPE_OFFSET]));
        payload = message[MSG_TYPE_OFFSET:];
    }
}
