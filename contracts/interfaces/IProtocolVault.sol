// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultType, RoleType, OperationParams, OperationData, UserClaimedInfo} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";

interface IProtocolVault {
    event OperationExecuted(OperationData operationData);
    event UserClaimed(uint256 amount, uint256[] requests);
    event DepositFromDex(uint256 periodId,uint256 amount);
    //event UnClaimedUpdated(uint256 periodId,UpdateUserClaim[] updateUserClaims);

    error NotAllowedToken();
    error InvalidDepositAmount();
    error InvalidRoleType();
    error NotEnoughUnclaimedAssets();
    error InvalidCrossChainManager();
    error InvalidDexVault();

    function executeOperation(OperationParams memory operationParams) external payable;
    function claim(RoleType roleType, uint256 amount, bytes32 brokerHash, bytes32 tokenHash) external;
}
