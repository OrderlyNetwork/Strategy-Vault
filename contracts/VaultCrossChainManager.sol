// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
// oz imports

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// lz imports
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

// dev imports
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IStrategyVaultLedger} from "./interfaces/IStrategyVaultLedger.sol";
import {VaultType, OperationData} from "./lib/types/VaultStruct.sol";
import {StrategyVaultCCMessage, PayloadType, LzOptions} from "./lib/types/CrossChainStruct.sol";
import {console} from "forge-std/console.sol";

/**
 * todo:
 *  - lz gas estimate OptionsBuilder 2. set block
 * - lz send require vault equal quote fee
 *
 */
contract VaultCrossChainManager is OApp, IVaultCrossChainManager {
    error InvalidPayloadType();

    using OptionsBuilder for bytes;

    uint32 public eid;
    uint32 public dstEid;
    address public ledger;
    address public vault;

    mapping(uint32 => uint32) public chainIdToEid;
    mapping(PayloadType => LzOptions) public msgOptions;

    constructor(address endpoint, address delegate) OApp(endpoint, delegate) Ownable(msg.sender) {
        eid = ILayerZeroEndpointV2(endpoint).eid();
    }

    function vaultSendToLedger(StrategyVaultCCMessage memory message) external payable {
        bytes memory lzMessage = abi.encode(message);

        bytes memory options = _getOptions(message.payloadType);
        MessagingFee memory messageFee = _quote(dstEid, lzMessage, options, false);
        _lzSend(
            dstEid,
            lzMessage,
            options,
            messageFee,
            payable(msg.sender)
        );
    }

    function ledgerSendToVault(StrategyVaultCCMessage memory message) external {
        bytes memory lzMessage = abi.encode(message);

        bytes memory options = _getOptions(message.payloadType);
        MessagingFee memory messageFee = _quote(dstEid, lzMessage, options, false);

        _lzSend(
            chainIdToEid[message.dstChainId],
            lzMessage,
            options,
            messageFee, // Refund address in case of failed source message.
            payable(msg.sender)
        );
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32, /*_guid*/
        bytes calldata _message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) internal virtual override {
        //Decode the payload by payloadType
        StrategyVaultCCMessage memory strategyVaultCCmessage = abi.decode(_message, (StrategyVaultCCMessage));
        PayloadType payloadType = strategyVaultCCmessage.payloadType;
        bytes memory payload = strategyVaultCCmessage.payload;

        if (
            payloadType == PayloadType.SP_WITHDRAW || payloadType == PayloadType.LP_DEPOSIT
                || payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.LP_WITHDRAW
        ) {
            //Decode the payload
            OperationData memory operationData = abi.decode(payload, (OperationData));

            //Call strategyVaultLedger to handle the operation
            IStrategyVaultLedger(ledger).handleOpFromVault(
                payloadType, strategyVaultCCmessage.srcChainId, operationData
            );
        } else if (payloadType == PayloadType.UPDATE_USER_CLAIM) {
            //Decode the payload
            //UserClaimedInfo memory userClaimedInfo = abi.decode(payload, (UserClaimedInfo));
            //Call strategyVaultLedger to handle the operation
            // IStrategyVaultLedger(ledger).handleUserClaimed(strategyVaultCCmessage.srcChainId, userClaimedInfo);
        }
        else {
            revert InvalidPayloadType();
        }
    }

    //--------------------------------------CONFIG--------------------------------------------

    function setDstEid(uint32 _dstEid) external onlyOwner {
        dstEid = _dstEid;
    }

    function setLedger(address _ledger) external onlyOwner {
        ledger = _ledger;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setEid(uint32 chainId, uint32 eid) external onlyOwner {
        chainIdToEid[chainId] = eid;
    }

    function setOptions(PayloadType payloadType, uint128 _gas, uint128 _value) external onlyOwner {
        msgOptions[payloadType] = LzOptions(_gas, _value);
    }

    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function quote(uint32 _dstEid, bytes memory _message, PayloadType payloadType, bool _payInLzToken)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        bytes memory options = _getOptions(payloadType);

        MessagingFee memory fee = _quote(_dstEid, _message, options, _payInLzToken);
        return (fee.nativeFee, fee.lzTokenFee);
    }
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function _getOptions(PayloadType payloadType) internal view returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            msgOptions[payloadType].gas, msgOptions[payloadType].value
        );
    }
}
