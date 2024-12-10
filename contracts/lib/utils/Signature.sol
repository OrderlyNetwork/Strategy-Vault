// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {
    Account,
    StrategyFund,
    UpdateStrategyFundAssetsParams,
    StrategyExecutionParams,
    BasicInfo,
    PendingState,
    StrategyExecution,
    Operation,
    OperationType,
    OperationRes,
    UpdateLedgerParams,
    AssetsDistribution,
    AccountState,
    UpdateUserClaim,
    AllocateFundRes,
    SettleType,
    StrategyFundState,
    SettleParams
} from "../types/LedgerStruct.sol";

library Signature {
    error InvalidSigner();

    function verifyUpdateFundAssets(
        uint256 periodId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, strategyFundAssets));
        verifySignature(signer, messageHash, signature);
    }

    function verifyUpdateLPAndStrategyFund(
        uint256 periodId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, updateUserLedgerParams));
        verifySignature(signer, messageHash, signature);
    }

    function verifyAllocatToFunds(
        uint256 periodId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, strategyProviderIds));
        verifySignature(signer, messageHash, signature);
    }

    function verifySettleMainAndStrategyFunds(
        uint256 periodId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, strategyProviderIds));
        verifySignature(signer, messageHash, signature);
    }

    function verifySettleAccount(
        uint256 periodId,
        bytes32[] calldata accountIds,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, accountIds));
        verifySignature(signer, messageHash, signature);
    }

    function verifyUpdatePeriodId(uint256 periodId, bytes memory signature, address signer) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId));
        verifySignature(signer, messageHash, signature);
    }
    function verifySignature(address signer, bytes32 messageHash, bytes memory signature) internal pure {
        if (signer != ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature)) {
            revert InvalidSigner();
        }
    }
}
