// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    VaultType,
    RoleType,
    OperationData,
    DepositParams,
    WithdrawParams,
    UserClaimedInfo
} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";
import {UpdateUserClaim} from "../lib/types/LedgerStruct.sol";

interface IProtocolVault {
    event OperationExecuted(PayloadType payloadType, OperationData operationData);
    event UserClaimed(uint256 amount, bytes32[] requests);
    event DepositFromStrategy(uint256 periodId, bytes32 vaultId, address sender, uint256 amount);
    event UnClaimedUpdated(uint256 periodId, UpdateUserClaim[] updateUserClaims);
    event DepositToStrategy(uint256 periodId, bytes32 vaultId, address receiver, uint256 amount);

    error NotAllowedToken();
    error InvalidDepositAmount();
    error InvalidRoleType();
    error NotEnoughUnclaimedAssets();
    error InvalidCrossChainManager();
    error InvalidDexVault();
    error InvalidPayloadType();
    error TokenNotAllowed();
    error BrokerNotAllowed();

    function deposit(DepositParams memory depositParams) external payable;
    function withdraw(WithdrawParams memory withdrawParams) external payable;
    function claim(RoleType roleType, uint256 amount, bytes32 brokerHash, address token) external;
    function depositToStrategy(uint256 periodId, address receiver, uint256 amount) external;
}
