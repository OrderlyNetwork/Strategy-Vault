// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    Account,
    StrategyFund,
    UpdateStrategyFundAssetsParams,
    UpdateStrategyFundAssetsRes,
    StrategyExecutionParams,
    BasicInfo,
    StrategyExecution,
    Operation,
    OperationType,
    OperationRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    UpdateUserClaim,
    AllocateFundRes,
    StrategyFundState
} from "../lib/types/LedgerStruct.sol";

import {VaultType, OperationData} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";

interface IStrategyVaultLedger {
    error InvalidPeriodId();
    error InvalidCaller();
    error InsufficientBalance();
    error AlreadyAllocatedShare();
    error NotEnoughWithdrawShare();
    error InvalidPayloadType();
    error NotAllowedStrategyProvider(); //0x4767d1b2
    error NotEnoughLPDeposit();
    error NotEnoughSPDeposit();
    error InvalidOpType();
    error InvalidTotalAssets();

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
        uint256 mainAssets, bytes32 vaultId, uint256 mainShares, StrategyFundState[] strategyFundStates
    );
    event AccountSettled(uint256 periodId, bytes32 vaultId, AccountState[] accountStates);
    event PeriodIdUpdated(uint256 latestPeriodId, bytes32 vaultId);
    event StrategyExecuted(uint256 periodId, bytes32 vaultId, uint256 totalTransferredAssets);
    event CrossChainManagerAddressSet(address crossChainManagerAddress);
    event AllowedStrategyProviderSet(
        bytes32 vaultId, address vault, address sp, bytes32 brokerHash, bytes32 spId, bool knob
    );
    event OperatorManagerSet(address operatorAddress);

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
    function allocatToFunds(
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
    function executeStrategy(
        uint256 periodId,
        bytes32 vaultId,
        StrategyExecutionParams memory strategyExecutionParams,
        bytes calldata signature
    ) external;
    function updateUnclaimed(
        uint256 periodId,
        bytes32 vaultId,
        UpdateUserClaim[] memory updateUserClaims,
        bytes memory signature
    ) external;
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function checkMainAndStrategyFund(uint256 periodId, bytes32 vaultId, bytes32[] calldata strategyProviderIds)
        external
        view
        returns (uint256, StrategyFundState[] memory);

    function checkLP(uint256 periodId, bytes32[] calldata accountIds) external view returns (AccountState[] memory);
}
