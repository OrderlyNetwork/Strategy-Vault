// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../../contracts/ProtocolVaultLedger.sol";

contract MockSVLedger is ProtocolVaultLedger {
    function initializeStrategyFund(
        uint256 _mainShares,
        bytes32[] memory spIds,
        uint256[] memory mainSharesInFund,
        uint256[] memory spSharesInFund,
        uint256[] memory fundAssets,
        uint256 hwm
    ) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundTokenInfo[spIds[i]][USDC_HASH].pendingState.pendingMainShares = mainSharesInFund[i];
            strategyFundTokenInfo[spIds[i]][USDC_HASH].pendingState.pendingStrategyProviderShares = spSharesInFund[i];
            strategyFundTokenInfo[spIds[i]][USDC_HASH].pendingState.pendingTotalAssets = fundAssets[i];
            strategyFundTokenInfo[spIds[i]][USDC_HASH].pendingState.pendingTotalShares =
                mainSharesInFund[i] + spSharesInFund[i];

            strategyFundTokenInfo[spIds[i]][USDC_HASH].mainShares = mainSharesInFund[i];
            strategyFundTokenInfo[spIds[i]][USDC_HASH].strategyProviderShares = spSharesInFund[i];
            strategyFundTokenInfo[spIds[i]][USDC_HASH].totalAssets = fundAssets[i];
            strategyFundTokenInfo[spIds[i]][USDC_HASH].totalShares = mainSharesInFund[i] + spSharesInFund[i];
            strategyFundTokenInfo[spIds[i]][USDC_HASH].hwm = hwm;
        }
        feeRateOfFund[spIds[0]] = 10;
        feeRateOfFund[spIds[1]] = 20;
        mainShares = _mainShares;
        pendingMainShares = _mainShares;
    }

    function getFundHWM(bytes32[] calldata strategyProviderIds) external view returns (uint256[] memory) {
        uint256[] memory hwms = new uint256[](2);
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            hwms[i] = _calculateHWM(strategyProviderIds[i]);
        }
        return hwms;
    }

    function setAccountState(bytes32 accountId, uint256 unAllocatedAssets, uint256 frozenShares, uint256 pendingShares)
        external
    {
        accountTokenInfo[accountId][USDC_HASH].unAllocatedAssets = unAllocatedAssets;
        accountTokenInfo[accountId][USDC_HASH].frozenShares = frozenShares;
        accountTokenInfo[accountId][USDC_HASH].pendingShares = pendingShares;
    }

    function setSPUnallocatedAssets(bytes32[] memory spIds, uint256 assets) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundTokenInfo[spIds[i]][USDC_HASH].unAllocatedAssets = assets;
        }
    }

    function setSPUnallocatedShares(bytes32[] memory spIds, uint256 shares) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundTokenInfo[spIds[i]][USDC_HASH].frozenShares = shares;
        }
    }

    function setAccountUnAllocatedAssets(bytes32[] memory accountIds, uint256 assets) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            accountTokenInfo[accountIds[i]][USDC_HASH].unAllocatedAssets = assets;
        }
    }

    function setAccountPendingShares(bytes32[] memory accountIds, uint256 shares) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            accountTokenInfo[accountIds[i]][USDC_HASH].pendingShares = shares;
        }
    }

    function setSpPendingShares(bytes32[] memory spIds, uint256 shares) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundTokenInfo[spIds[i]][USDC_HASH].pendingState.pendingStrategyProviderShares = shares;
        }
    }
    function setLpClaimInfo(bytes32 requestId, bytes32 accountId, uint256 assets) external {
        userClaimInfo[requestId].requestId = requestId;
        userClaimInfo[requestId].accountId = accountId;
        userClaimInfo[requestId].assets = assets;
    }

    function setSpClaimInfo(bytes32 requestId, bytes32 spId, uint256 assets) external {
        userClaimInfo[requestId].requestId = requestId;
        userClaimInfo[requestId].strategyProviderId = spId;
        userClaimInfo[requestId].assets = assets;
    }
}
