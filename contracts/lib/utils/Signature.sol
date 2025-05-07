// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
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
    UpdateUserClaim,
    AllocateFundRes,
    StrategyFundState
} from "../types/LedgerStruct.sol";

library Signature {
    error InvalidSigner();

    function verifyUpdateFundAssets(
        uint256 periodId,
        bytes32 vaultId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, vaultId, strategyFundAssets));
        verifySignature(signer, messageHash, signature);
    }

    function verifyUpdateLPAndStrategyFund(
        uint256 periodId,
        bytes32 vaultId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, vaultId, updateUserLedgerParams));
        verifySignature(signer, messageHash, signature);
    }

    function verifyAllocateToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, vaultId, strategyProviderIds, "allocateToFunds"));
        verifySignature(signer, messageHash, signature);
    }

    function verifySettleMainAndStrategyFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash =
            keccak256(abi.encode(periodId, vaultId, strategyProviderIds, "settleMainAndStrategyFunds"));
        verifySignature(signer, messageHash, signature);
    }

    function verifySettleAccount(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata accountIds,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, vaultId, accountIds));
        verifySignature(signer, messageHash, signature);
    }

    function verifyUpdatePeriodId(uint256 periodId, bytes32 vaultId, bytes memory signature, address signer)
        internal
        pure
    {
        bytes32 messageHash = keccak256(abi.encode(periodId, vaultId));
        verifySignature(signer, messageHash, signature);
    }

    function verifyAssetsDistribution(
        uint256 periodId,
        bytes32 vaultId,
        AssetsDistribution[] memory assetsDistributions,
        bytes calldata signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(periodId, vaultId, assetsDistributions));
        verifySignature(signer, messageHash, signature);
    }

    function verifyUpdateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] memory requestIds,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(chainId, periodId, vaultId, requestIds));
        verifySignature(signer, messageHash, signature);
    }

    function verifyRemoveInvalidFrozenShares(
        bytes32 vaultId,
        UpdateLedgerParams[] calldata params,
        bytes calldata signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(vaultId, params));
        verifySignature(signer, messageHash, signature);
    }

    function verifySignature(address signer, bytes32 messageHash, bytes memory signature) internal pure {
        if (signer != ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature)) {
            revert InvalidSigner();
        }
    }
}
