// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IStrategyVault {
    function deposit(uint256 amount) external;

    //https://orderly.network/docs/build-on-evm/user-flows/delegate-signer

    function withdraw(address to, uint256 amount) external;

    function executeStrategy() external;

    function executeToOrderly() external;

    function closeVault() external;

    /*======================================================================
     *                          Config Functions
     *======================================================================*/

    //https://orderly.network/docs/build-on-evm/user-flows/delegate-signer
    function delegateSigner() external;

    function getVault() external;
}
