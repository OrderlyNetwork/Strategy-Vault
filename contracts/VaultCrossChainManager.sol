// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
// lz imports

import "@openzeppelin/contracts/utils/Address.sol";
import {OptionsBuilder} from "./lib/layerzero-v2/oapp/libs/OptionsBuilder.sol";
import {OAppUpgradeable, MessagingFee, Origin} from "./lib/layerzero-v2/oapp/OAppUpgradeable.sol";

// dev imports
import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVaultLedger} from "./interfaces/IProtocolVaultLedger.sol";
import {IProtocolVault} from "./interfaces/IProtocolVault.sol";

import {VaultType, OperationData} from "./lib/types/VaultStruct.sol";
import {AssetsDistribution, ClaimInfo} from "./lib/types/LedgerStruct.sol";
import {StrategyVaultCCMessage, PayloadType, LzOptions} from "./lib/types/CrossChainStruct.sol";
import {DecimalConverter} from "./lib/utils/DecimalConverter.sol";

contract VaultCrossChainManager is OAppUpgradeable, IVaultCrossChainManager {
    using Address for address payable;

    bytes32 constant USDC_HASH = 0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa;

    error InvalidCaller(address caller);
    error InvalidPayloadType();

    using OptionsBuilder for bytes;
    using DecimalConverter for uint256;

    uint256 public ledgerDecimal;

    address public ledger;
    address public vault;

    mapping(uint256 => uint32) public chainIdToEid;
    mapping(PayloadType => LzOptions) public msgOptions;
    /// @dev tokenhash to chainId to decimal
    mapping(bytes32 => mapping(uint256 => uint256)) public tokenDecimals;
    mapping(bytes32 => mapping(uint256 => bool)) public isSpecialDecimal;

    receive() external payable {}

    /**
     * @dev Disable the initializer on the implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    /// @notice Require only protocol vault can call
    modifier onlyVault() {
        if (msg.sender != vault) {
            revert InvalidCaller(msg.sender);
        }
        _;
    }

    /// @notice Require only ledger can call
    modifier onlyLedger() {
        if (msg.sender != ledger) {
            revert InvalidCaller(msg.sender);
        }
        _;
    }

    function initialize(address endpoint, address delegate) external virtual initializer {
        __initializeOApp(endpoint, delegate);

        ledgerDecimal = 6;
    }

    function sendMessageWithValueAndRefund(StrategyVaultCCMessage memory message, address refundAddress)
        external
        payable
        onlyVault
    {
        bytes memory lzMessage = abi.encode(message);
        bytes memory options = _getOptions(message.payloadType);
        uint32 dstEid = chainIdToEid[message.dstChainId];

        MessagingFee memory messageFee = MessagingFee({nativeFee: msg.value, lzTokenFee: 0});
        _lzSend(dstEid, lzMessage, options, messageFee, payable(refundAddress));
    }

    function sendMessage(StrategyVaultCCMessage memory message) external onlyLedger {
        bytes memory lzMessage = abi.encode(message);
        bytes memory options = _getOptions(message.payloadType);

        uint32 dstEid = chainIdToEid[message.dstChainId];
        MessagingFee memory messageFee = _quote(dstEid, lzMessage, options, false);

        _lzSend(dstEid, lzMessage, options, messageFee, payable(address(this)));
    }

    /// @notice withdraw native token
    /// @param to the receiver address
    /// @param amount the amount to withdraw
    function withdrawNativeToken(address payable to, uint256 amount) external onlyOwner {
        to.sendValue(amount);
    }

    function _lzReceive(
        Origin calldata,
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

            //Convert the amount
            uint256 srcChainId = strategyVaultCCmessage.srcChainId;
            if (isSpecialDecimal[operationData.tokenHash][srcChainId]) {
                operationData.amount = _convertAmount(
                    operationData.amount, tokenDecimals[operationData.tokenHash][srcChainId], ledgerDecimal
                );
            }
            //Call strategyVaultLedger
            IProtocolVaultLedger(ledger).handleOpFromVault(payloadType, srcChainId, operationData);
        } else if (payloadType == PayloadType.ASSETS_DISTRIBUTION) {
            //Decode the payload
            (uint256 periodId, AssetsDistribution memory assetsDistribution) =
                abi.decode(payload, (uint256, AssetsDistribution));

            //Convert the amount
            uint256 dstChainId = strategyVaultCCmessage.dstChainId;
            if (isSpecialDecimal[USDC_HASH][dstChainId]) {
                assetsDistribution.assets =
                    _convertAmount(assetsDistribution.assets, ledgerDecimal, tokenDecimals[USDC_HASH][dstChainId]);
            }
            //Call Protocol Vault
            IProtocolVault(vault).depositToStrategy(periodId, vault, assetsDistribution.assets);
        } else if (payloadType == PayloadType.UPDATE_USER_CLAIM) {
            //Decode the payload
            (uint256 periodId, uint256 ccFee, ClaimInfo[] memory userClaims) =
                abi.decode(payload, (uint256, uint256, ClaimInfo[]));

            //Convert the amount
            uint256 dstChainId = strategyVaultCCmessage.dstChainId;
            if (isSpecialDecimal[USDC_HASH][dstChainId]) {
                for (uint256 i = 0; i < userClaims.length; i++) {
                    userClaims[i].assets =
                        _convertAmount(userClaims[i].assets, ledgerDecimal, tokenDecimals[USDC_HASH][dstChainId]);
                }
            }
            //Call Protocol Vault
            IProtocolVault(vault).updateUnClaimed(periodId, ccFee, userClaims);
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

    function setSpecialTokenDecimal(bytes32 tokenHash, uint256 chainId, uint256 decimal) external onlyOwner {
        tokenDecimals[tokenHash][chainId] = decimal;

        isSpecialDecimal[tokenHash][chainId] = true;
    }

    function setLedgerDecimal(uint256 decimal) external onlyOwner {
        ledgerDecimal = decimal;
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

    function quoteClaim(uint256 chainId, StrategyVaultCCMessage memory message)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        uint32 dstEid = chainIdToEid[chainId];
        bytes memory options = _getOptions(PayloadType.UPDATE_USER_CLAIM);

        bytes memory lzMessage = abi.encode(message);

        MessagingFee memory fee = _quote(dstEid, lzMessage, options, false);

        return (fee.nativeFee, fee.lzTokenFee);
    }
    /*=========================================================================================
    *                                       INTERNAL
    *=========================================================================================*/

    function _getOptions(PayloadType payloadType) internal view returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            msgOptions[payloadType].gas, msgOptions[payloadType].value
        );
    }

    function _convertAmount(uint256 amount, uint256 srcDecimal, uint256 dstDecimal) internal pure returns (uint256) {
        return amount.convertDecimal(srcDecimal, dstDecimal);
    }
}
