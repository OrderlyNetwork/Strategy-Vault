// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import {ExecutorFeeLib} from "../../messagelib/ExecutorFeeLib.sol";

contract ExecutorFeeLibMock is ExecutorFeeLib {
    constructor() ExecutorFeeLib(1e18) {}

    function _isV1Eid(uint32 /*_eid*/ ) internal pure override returns (bool) {
        return false;
    }
}
