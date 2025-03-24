// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    AccountToken,
    StrategyFundToken,
    UpdateStrategyFundAssetsParams,
    UpdateStrategyFundAssetsRes,
    PendingState,
    Operation,
    OperationType,
    OperationRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    ClaimInfo,
    AllocateFundRes,
    StrategyFundState
} from "../lib/types/LedgerStruct.sol";

import {VaultType, OperationData} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";

interface IProtocolVaultLedger {
    error InvalidPeriodId(); //0x13ac34b9
    error InvalidOperator();
    error InvalidVaultCrossChainManager();
    error NotEnoughLPDeposit(uint256 amount);
    error NotEnoughSPDeposit();
    error InvalidOpType(OperationType opType);
    error NotEnoughFrozenShare(uint256 amount);
    error InvalidInput();
    error AlreadyCalled();
    error NotAllowedTime();
    
    event OperationHandled(PayloadType payloadType, uint256 chainId, OperationData operationData);
    event StrategyFundAssetsUpdate(
        uint256 periodId,
        bytes32 vaultId,
        uint256 mainAssetsAfterFee,
        UpdateStrategyFundAssetsRes[] updateStrategyFundAssetsRes
    );
    event LPAndStrategyFundUpdated(uint256 periodId, bytes32 vaultId, OperationRes[] operationRes);
    event FundAllocated(
        uint256 periodId, bytes32 vaultId, bytes32[] strategyProviderIds, AllocateFundRes[] allocateFundRes
    );
    event MainAndStrategyFundsSettled(
        uint256 periodId, bytes32 vaultId, uint256 mainShares, StrategyFundState[] strategyFundStates
    );
    event AccountSettled(uint256 periodId, bytes32 vaultId, AccountState[] accountStates);
    event PeriodIdUpdated(uint256 latestPeriodId, bytes32 vaultId);
    event CrossChainManagerAddressSet(address crossChainManagerAddress);
    event AllowedStrategyProviderSet(
        bytes32 vaultId, address vault, address sp, bytes32 brokerHash, bytes32 spId, bool knob
    );
    event OperatorManagerSet(address operatorAddress);
    event AssetsDistributed(uint256 periodId, bytes32 vaultId);
    event UnclaimedAssetsUpdated(uint256 periodId, bytes32 vaultId, ClaimInfo[] claimInfos);
    event NotEnoughWithdrawShare(uint256 chainNonce);
    event InvalidPayloadType();

    //--------------------------------------FROM VAULT-----------------------------------------

    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData memory operationData) external;

    //--------------------------------------FROM BE--------------------------------------------
    function updateStrategyFundAssets(
        uint256 periodId,
        bytes32 vaultId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes calldata signature
    ) external;
    function updateLPAndStrategyFund(
        uint256 periodId,
        bytes32 vaultId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes calldata signature
    ) external;
    function allocateToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature
    ) external;
    function settleMainAndStrategyFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature
    ) external;
    function settleAccounts(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds, bytes memory signature)
        external;
    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes memory signature) external;

    function distributeAssets(
        uint256 periodId,
        bytes32 vaultId,
        AssetsDistribution[] memory assetsDistributions,
        bytes calldata signature
    ) external;
    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata requestIds,
        bytes memory signature
    ) external;
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function checkMainAndStrategyFund(uint256 periodId, bytes32 vaultId, bytes32[] calldata strategyProviderIds)
        external
        view
        returns (uint256, StrategyFundState[] memory);

    function checkLP(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds)
        external
        view
        returns (AccountState[] memory);
}
