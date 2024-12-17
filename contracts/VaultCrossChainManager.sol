// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
// oz imports

// import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

// lz imports
import {OptionsBuilder} from "./lib/layerzero-v2/oapp/libs/OptionsBuilder.sol";
import {OAppUpgradeable, MessagingFee, Origin} from "./lib/layerzero-v2/oapp/OAppUpgradeable.sol";

// dev imports
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IStrategyVaultLedger} from "./interfaces/IStrategyVaultLedger.sol";
import {IProtocolVault} from "./interfaces/IProtocolVault.sol";

import {VaultType, OperationData} from "./lib/types/VaultStruct.sol";
import {AssetsDistribution, UpdateUserClaim} from "./lib/types/LedgerStruct.sol";
import {StrategyVaultCCMessage, PayloadType, LzOptions} from "./lib/types/CrossChainStruct.sol";
import {console} from "forge-std/console.sol";

/**
 * todo:
 *  - lz gas estimate OptionsBuilder 2. set block
 * - lz send require vault equal quote fee
 *
 */
contract VaultCrossChainManager is OAppUpgradeable, IVaultCrossChainManager {
    error InvalidPayloadType();

    using OptionsBuilder for bytes;

    address public ledger;
    address public vault;

    mapping(uint32 => uint32) public chainIdToEid;
    mapping(PayloadType => LzOptions) public msgOptions;

    receive() external payable {}

    /**
     * @dev Disable the initializer on the implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    function initialize(address endpoint, address delegate) external virtual initializer {
        __initializeOApp(endpoint, delegate);

        chainIdToEid[291] = 30213;
    }

    function sendMessage(StrategyVaultCCMessage memory message) external payable {
        bytes memory lzMessage = abi.encode(message);
        bytes memory options = _getOptions(message.payloadType);

        uint32 dstEid = chainIdToEid[message.dstChainId];
        MessagingFee memory messageFee = _quote(dstEid, lzMessage, options, false);

        _lzSend(dstEid, lzMessage, options, messageFee, payable(address(this)));
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

            //Call strategyVaultLedger
            IStrategyVaultLedger(ledger).handleOpFromVault(
                payloadType, strategyVaultCCmessage.srcChainId, operationData
            );
        } else if (payloadType == PayloadType.ASSETS_DISTRIBUTION) {
            //Decode the payload
            (uint256 periodId, AssetsDistribution memory assetsDistribution) =
                abi.decode(payload, (uint256, AssetsDistribution));

            //Call Protocol Vault
            IProtocolVault(vault).depositToStrategy(periodId, vault, assetsDistribution.assets);
        } else if (payloadType == PayloadType.UPDATE_USER_CLAIM) {
            //Decode the payload
            (uint256 periodId, UpdateUserClaim[] memory updateUserClaims) =
                abi.decode(payload, (uint256, UpdateUserClaim[]));

            //Call Protocol Vault
            IProtocolVault(vault).updateUnClaimed(periodId, updateUserClaims);
        } else {
            revert InvalidPayloadType();
        }
    }

    //--------------------------------------CONFIG--------------------------------------------
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
