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
import {ClaimInfo} from "../lib/types/LedgerStruct.sol";

interface IProtocolVault {
    event OperationExecuted(PayloadType payloadType, OperationData operationData);
    event UserClaimed(RoleType, bytes32 id, uint256 amount, bytes32[] requests);
    event DepositFromStrategy(uint256 periodId, bytes32 vaultId, address sender, uint256 amount);
    event UnClaimedUpdated(uint256 periodId, bytes32 vaultId, ClaimInfo[] claimInfos);
    event DepositToStrategy(uint256 periodId, bytes32 vaultId, address receiver, uint256 amount, uint64 dexNonce);
    event VaultStateChanged(VaultState state);
    event AllowedBrokerSet(bytes32 brokerHash, bool isAllowed);
    event AllowedTokenSet(address token, bool isAllowed);
    event AdminSet(address admin);
    event AllowedStrategySet(address strategy, bool isAllowed);

    error InvalidDepositAmount(uint256 amount);
    error InvalidRoleType();
    error NotEnoughUnclaimedAssets(uint256 amount);
    error InvalidCrossChainManager();
    error InvalidStrategy();
    error InvalidPayloadType(PayloadType payloadType);
    error TokenNotAllowed(address token);
    error BrokerNotAllowed(bytes32 brokerHash);
    error InvalidOwnerOrAdmin();
    error VaultClosed();
    error InvalidDepositType(PayloadType payloadType);
    error InvalidWithdrawType(PayloadType payloadType);
    error NotAllowedStrategyProvider(bytes32 strategyProviderId);
    error InvalidClaimToken(address token);
    error ZeroAmount();
    
    function deposit(DepositParams memory depositParams) external payable;
    function withdraw(WithdrawParams memory withdrawParams) external payable;
    function claim(ClaimParams memory claimParams) external;
    function depositToStrategy(uint256 periodId, address receiver, uint256 amount) external;
    function updateUnClaimed(uint256 periodId, ClaimInfo[] memory userClaimInfos) external;
}
