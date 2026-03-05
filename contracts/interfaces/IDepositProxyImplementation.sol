// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DepositParams} from "../lib/types/VaultStruct.sol";
import {VaultDepositFE} from "./IDexVault.sol";

/// @title IDepositProxyImplementation
/// @notice Interface for DepositProxyImplementation contract
interface IDepositProxyImplementation {
    error OnlyFactory();
    error TransferFailed();

    /// @notice Deposit to a vault contract
    /// @param vault Target vault address
    /// @param params Deposit parameters
    function depositToVault(address vault, DepositParams memory params) external payable;

    /// @notice Deposit to DexVault
    /// @param dexVault DexVault address
    /// @param receiver Receiver address
    /// @param token Token address
    /// @param data Vault deposit data
    function depositToDex(address dexVault, address receiver, address token, VaultDepositFE memory data)
        external
        payable;

    /// @notice Withdraw tokens from proxy (emergency only)
    /// @param token Token address
    /// @param to Recipient address
    /// @param amount Withdrawal amount
    function withdraw(address token, address to, uint256 amount) external;
}
