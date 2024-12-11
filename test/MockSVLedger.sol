// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../contracts/StrategyVaultLedger.sol";

contract MockSVLedger is StrategyVaultLedger {
    function initializeStrategyFund(
        uint256 _mainShares,
        bytes32[] memory spIds,
        uint256[] memory mainSharesInFund,
        uint256[] memory spSharesInFund,
        uint256[] memory fundAssets,
        uint256 hwm
    ) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundById[spIds[i]].strategyProviderId = spIds[i];
            strategyFundById[spIds[i]].pendingState.pendingMainShares = mainSharesInFund[i];
            strategyFundById[spIds[i]].pendingState.pendingStrategyProviderShares = spSharesInFund[i];
            strategyFundById[spIds[i]].pendingState.pendingTotalAssets = fundAssets[i];
            strategyFundById[spIds[i]].pendingState.pendingTotalShares = mainSharesInFund[i] + spSharesInFund[i];

            strategyFundById[spIds[i]].mainShares = mainSharesInFund[i];
            strategyFundById[spIds[i]].strategyProviderShares = spSharesInFund[i];
            strategyFundById[spIds[i]].totalAssets = fundAssets[i];
            strategyFundById[spIds[i]].totalShares = mainSharesInFund[i] + spSharesInFund[i];
            strategyFundById[spIds[i]].hwm = hwm;
        }
        mainShares = _mainShares;
        pendingMainShares = _mainShares;

        feeRateOfFund[0] = 10;
        feeRateOfFund[1] = 20;
    }

    function getFundHWM(bytes32[] calldata strategyProviderIds) external view returns (uint256[] memory) {
        uint256[] memory hwms = new uint256[](2);
        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            hwms[i] = _calculateHWM(strategyProviderIds[i]);
        }
        return hwms;
    }

    function setAccountShares(bytes32 accountId, uint256 amount) external {
        accountById[accountId].shares = amount;
    }

    function setFundSshares(bytes32 strategyProviderIds, uint256 amount) external {
        strategyFundById[strategyProviderIds].totalShares = amount;
    }

    function setAccountState(bytes32 accountId, uint256 unAllocatedAssets, uint256 frozenShares, uint256 pendingShares)
        external
    {
        accountById[accountId].unAllocatedAssets = unAllocatedAssets;
        accountById[accountId].frozenShares = frozenShares;
        accountById[accountId].pendingShares = pendingShares;
    }

    function setSPUnallocatedAssets(bytes32[] memory spIds, uint256 assets) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundById[spIds[i]].unAllocatedAssets = assets;
        }
    }

    function setAccountFrozenShares(bytes32[] memory accountIds, uint256 shares) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            accountById[accountIds[i]].frozenShares = shares;
        }
    }

    function setSPUnallocatedShares(bytes32[] memory spIds, uint256 shares) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundById[spIds[i]].frozenShares = shares;
        }
    }

    function setAccountPendingShares(bytes32[] memory accountIds, uint256 shares) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            accountById[accountIds[i]].pendingShares = shares;
        }
    }

    function _calculateHWM(bytes32[] calldata strategyProviderIds) internal view returns (uint256[] memory) {
        StrategyFund memory strategyFund;
        uint256[] memory hwms = new uint256[](strategyProviderIds.length);

        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            strategyFund = strategyFundById[strategyProviderIds[i]];
            uint256 hwm = strategyFund.hwm;
            uint256 totalShares = strategyFund.totalShares;

            if (strategyFund.pendingState.pendingPerformanceFee > 0) {
                hwm = strategyFund.fundAssetsAfterFee * 10 ** priceDecimal / totalShares;
            } else {
                uint256 pendingTotalShares = strategyFund.pendingState.pendingTotalShares;
                //New issued shares greater than 0
                if (pendingTotalShares > totalShares) {
                    //uint256 newSharePriceAfterFee = strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i];
                    //console.log("newSharePriceAfterFee",newSharePriceAfterFee);
                    uint256 newTotalIssuedShares = pendingTotalShares - totalShares;
                    //calculate new hwm
                    hwm = (
                        (
                            strategyFund.hwm * totalShares / 10 ** priceDecimal
                                + newTotalIssuedShares * strategyFund.fundAssetsAfterFee / totalShares
                        )
                    ) * 10 ** priceDecimal / pendingTotalShares;
                }
            }
            hwms[i] = hwm;
        }
        return hwms;
    }
}
