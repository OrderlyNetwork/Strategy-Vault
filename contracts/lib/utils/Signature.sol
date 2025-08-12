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
import {TYPE_HASH, REQUEST_HASH, ED25519} from "../types/Constants.sol";
import "./Bytes32ToAsciiBytes.sol";
import {IEd25519} from "../../interfaces/IEd25519.sol";

library Signature {
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

    function verifySOLSig(DexRequestData memory data, bytes32 r, bytes32 s, uint256 chainId, bytes32 signer)
        internal
        pure
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                data.payloadType,
                data.dexRequestId,
                signer,
                data.amount,
                data.vaultId,
                keccak256(abi.encodePacked(data.token)),
                keccak256(abi.encodePacked(data.dexBrokerId)),
                chainId
            )
        );
        bytes memory m = Bytes32ToAsciiBytes.bytes32ToAsciiBytes(hashStruct);
        // the former is the signature of message from eoa, the latter is the signature of tx from ledger
        if (
            !(
                IEd25519(ED25519).verify(signer, r, s, m)
                    || IEd25519(ED25519).verify(signer, r, s, solanaLedgerSignature(signer, hashStruct))
            )
        ) {
            revert InvalidUser();
        }
    }

    function solanaLedgerSignature(bytes32 pubkey, bytes32 messageRaw) internal pure returns (bytes memory) {
        bytes memory message = Bytes32ToAsciiBytes.bytes32ToAsciiBytes(messageRaw);
        bytes memory m1 = hex"01000203";
        bytes memory m2 =
            hex"0306466fe5211732ffecadba72c39be7bc8ce5bbc5f7126b2c439b3a40000000054a535a992921064d24e87160da387c7c35b5ddbc92bb81e41fa8404105448d0000000000000000000000000000000000000000000000000000000000000000030100090300000000000000000100050200000000020040";
        bytes memory m = abi.encodePacked(m1, abi.encodePacked(pubkey), m2, message);
        return m;
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
