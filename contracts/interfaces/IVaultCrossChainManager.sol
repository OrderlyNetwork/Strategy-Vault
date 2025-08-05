// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StrategyVaultCCMessage} from "../lib/types/CrossChainStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";

interface IVaultCrossChainManager {
    function quote(uint32 _dstEid, bytes memory _message, PayloadType payloadType, bool _payInLzToken)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee);
    function quoteClaim(uint256 chainId, StrategyVaultCCMessage memory message)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee);
    function sendMessageWithValueAndRefund(StrategyVaultCCMessage memory message, address refundAddress)
        external
        payable;
    function sendMessage(StrategyVaultCCMessage memory message) external;
    function vault() external view returns (address);
}
