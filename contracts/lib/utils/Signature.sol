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
    StrategyFundState,
    DexRequestData,
    DexRequest
} from "../types/LedgerStruct.sol";
import {AdapterDeposit} from "../types/VaultStruct.sol";

library Signature {
    /// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
    bytes32 internal constant TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    /// @dev `keccak256("DexRequest(uint8 payloadType,uint256 nonce,address receiver,uint256 amount,bytes32 vaultId,string token,string dexBrokerId)")`.
    bytes32 internal constant REQUEST_HASH = 0x590ef38f093814e411b876bc59d8020504481133ef17b2b49abbdedc31d57084;

    error InvalidSigner();
    error InvalidUser();

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

    function verifyAdapterDeposit(
        AdapterDeposit memory adapterDeposit,
        uint256 chainId,
        bytes calldata signature,
        address signer
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(adapterDeposit, chainId));
        verifySignature(signer, messageHash, signature);
    }

    function verifyEVMSig(DexRequestData memory data, uint8 v, bytes32 r, bytes32 s, uint256 chainId, address signer)
        internal
        view
    {
        bytes32 eip712DomainHash =
            keccak256(abi.encode(TYPE_HASH, keccak256(bytes("Orderly")), keccak256(bytes("1")), chainId, address(this)));
        bytes32 hashStruct = keccak256(
            abi.encode(
                REQUEST_HASH,
                data.payloadType,
                data.dexRequestId,
                signer,
                data.amount,
                data.vaultId,
                keccak256(abi.encodePacked(data.token)),
                keccak256(abi.encodePacked(data.dexBrokerId))
            )
        );

        if (signer != ECDSA.recover(MessageHashUtils.toTypedDataHash(eip712DomainHash, hashStruct), v, r, s)) {
            revert InvalidUser();
        }
    }

    function verifyDexRequest(DexRequest[] calldata dexRequests, bytes calldata signature, address signer)
        internal
        pure
    {
        bytes32 messageHash = keccak256(abi.encode(dexRequests));
        verifySignature(signer, messageHash, signature);
    }

    function verifySignature(address signer, bytes32 messageHash, bytes memory signature) internal pure {
        if (signer != ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature)) {
            revert InvalidSigner();
        }
    }
}
