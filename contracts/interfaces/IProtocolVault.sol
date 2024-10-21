// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IStrategyVault {
    function deposit() external;

    /*======================================================================
     *                          Config Functions
     *======================================================================*/

    //https://orderly.network/docs/build-on-evm/user-flows/delegate-signer
    function delegateSigner() external;

    function getVault() external;
}
