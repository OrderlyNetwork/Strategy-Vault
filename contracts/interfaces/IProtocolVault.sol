// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    VaultType,
    RoleType,
    VaultState,
    ClaimParams,
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
    event VaultStateChanged(VaultState state);
    event AllowedBrokerSet(bytes32 brokerHash, bool isAllowed);
    event AllowedTokenSet(address token, bool isAllowed);
    event AdminSet(address admin);
    event AllowedStrategySet(address strategy, bool isAllowed);

    error NotAllowedToken();
    error InvalidDepositAmount(uint256 amount);
    error ZeroAmount();
    error InvalidRoleType();
    error NotEnoughUnclaimedAssets(uint256 amount);
    error InvalidCrossChainManager();
    error InvalidStrategy();
    error InvalidPayloadType(PayloadType payloadType);
    error TokenNotAllowed(address token);
    error BrokerNotAllowed(bytes32 brokerHash);
    error NotEnoughFee();
    error InvalidOwnerOrAdmin();
    error VaultClosed();

    function deposit(DepositParams memory depositParams) external payable;
    function withdraw(WithdrawParams memory withdrawParams) external payable;
    function claim(ClaimParams memory claimParams) external;
    function depositToStrategy(uint256 periodId, address receiver, uint256 amount) external;
    function updateUnClaimed(uint256 periodId, UpdateUserClaim[] memory updateUserClaims) external;
}
