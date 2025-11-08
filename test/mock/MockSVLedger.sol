// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../../contracts/Ledger/ProtocolVaultLedger.sol";
import {USDC_HASH, VAULT_STORAGE_LOCATION} from "../../contracts/lib/types/Constants.sol";

contract MockSVLedger is ProtocolVaultLedger {
    function initializeStrategyFund(
        bytes32 vaultId,
        uint256 _mainShares,
        bytes32[] memory spIds,
        uint256[] memory mainSharesInFund,
        uint256[] memory spSharesInFund,
        uint256[] memory fundAssets,
        uint256 hwm
    ) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            StrategyFundToken storage token = _getStrategyFundToken(vaultId, spIds[i], USDC_HASH);
            token.pendingState.pendingMainShares = mainSharesInFund[i];
            token.pendingState.pendingStrategyProviderShares = spSharesInFund[i];
            token.pendingState.pendingTotalAssets = fundAssets[i];
            token.pendingState.pendingTotalShares = mainSharesInFund[i] + spSharesInFund[i];

            token.mainShares = mainSharesInFund[i];
            token.strategyProviderShares = spSharesInFund[i];
            token.totalAssets = fundAssets[i];
            token.totalShares = mainSharesInFund[i] + spSharesInFund[i];
            token.hwm = hwm;
        }
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        feeRateOfFund[spIds[0]] = 10;
        feeRateOfFund[spIds[1]] = 20;
        vaultStorage.mainShares = _mainShares;
        vaultStorage.pendingMainShares = _mainShares;
    }

    function getFundHWM(bytes32 vaultId, bytes32[] calldata strategyProviderIds)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory hwms = new uint256[](2);
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            hwms[i] = _calculateHWM(vaultId, strategyProviderIds[i]);
        }
        return hwms;
    }

    function setAccountState(
        bytes32 vaultId,
        bytes32 accountId,
        uint256 unAllocatedAssets,
        uint256 frozenShares,
        uint256 pendingShares
    ) external {
        AccountToken storage token = _getAccountToken(vaultId, accountId, USDC_HASH);
        token.unAllocatedAssets = unAllocatedAssets;
        token.frozenShares = frozenShares;
        token.pendingShares = pendingShares;
    }

    function setSPUnallocatedAssets(bytes32 vaultId, bytes32[] memory spIds, uint256 assets) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            _getStrategyFundToken(vaultId, spIds[i], USDC_HASH).unAllocatedAssets = assets;
        }
    }

    function setSPUnallocatedShares(bytes32 vaultId, bytes32[] memory spIds, uint256 shares) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            _getStrategyFundToken(vaultId, spIds[i], USDC_HASH).frozenShares = shares;
        }
    }

    function setAccountUnAllocatedAssets(bytes32 vaultId, bytes32[] memory accountIds, uint256 assets) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            _getAccountToken(vaultId, accountIds[i], USDC_HASH).unAllocatedAssets = assets;
        }
    }

    function setAccountPendingShares(bytes32 vaultId, bytes32[] memory accountIds, uint256 shares) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            _getAccountToken(vaultId, accountIds[i], USDC_HASH).pendingShares = shares;
        }
    }

    function setSpPendingShares(bytes32 vaultId, bytes32[] memory spIds, uint256 shares) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            _getStrategyFundToken(vaultId, spIds[i], USDC_HASH).pendingState.pendingStrategyProviderShares = shares;
        }
    }

    function setLpClaimInfo(bytes32 vaultId, bytes32 requestId, bytes32 accountId, uint256 assets) external {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        vaultStorage.userClaimInfo[requestId].requestId = requestId;
        vaultStorage.userClaimInfo[requestId].accountId = accountId;
        vaultStorage.userClaimInfo[requestId].assets = assets;
    }

    function setSpClaimInfo(bytes32 vaultId, bytes32 requestId, bytes32 spId, uint256 assets) external {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        vaultStorage.userClaimInfo[requestId].requestId = requestId;
        vaultStorage.userClaimInfo[requestId].strategyProviderId = spId;
        vaultStorage.userClaimInfo[requestId].assets = assets;
    }

    function setAccountFrozenShares(bytes32 vaultId, bytes32[] memory accountIds, uint256 amount) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            _getAccountToken(vaultId, accountIds[i], USDC_HASH).frozenShares = amount;
        }
    }

    function getAccountFrozenShares(bytes32 vaultId, bytes32 accountId) external view returns (uint256) {
        return _getAccountToken(vaultId, accountId, USDC_HASH).frozenShares;
    }

    function setSPFrozenShares(bytes32 vaultId, bytes32[] memory strategyProviderIds, uint256 amount) external {
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            _getStrategyFundToken(vaultId, strategyProviderIds[i], USDC_HASH).frozenShares = amount;
        }
    }

    function getSPFrozenShares(bytes32 vaultId, bytes32 strategyProviderId) external view returns (uint256) {
        return _getStrategyFundToken(vaultId, strategyProviderId, USDC_HASH).frozenShares;
    }

    /// @notice Get main shares for testing
    /// @param vaultId vault id
    /// @return Main shares amount
    function getVaultMainShares(bytes32 vaultId) external view returns (uint256) {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        return vaultStorage.mainShares;
    }

    /// @notice Get pending main shares for testing
    /// @param vaultId vault id
    /// @return Pending main shares amount
    function getVaultPendingMainShares(bytes32 vaultId) external view returns (uint256) {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        return vaultStorage.pendingMainShares;
    }

    function getVaultMainAssetsAfterFee(bytes32 vaultId) external view returns (uint256) {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        return vaultStorage.mainAssetsAfterFee;
    }

    /// @notice Check if dex request is handled by vault
    /// @param vaultId vault id
    /// @param requestId request id
    /// @return true if handled
    function isDexRequestHandledByVault(bytes32 vaultId, uint256 requestId) external view returns (bool) {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        return vaultStorage.isDexRequestHandled[requestId];
    }
}
