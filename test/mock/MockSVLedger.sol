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
            strategyFundTokenInfo[spIds[i]][USDC_HASH].pendingState.pendingTotalShares = mainSharesInFund[i] + spSharesInFund[i];

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

    function setAccountShares(bytes32 accountId, uint256 amount) external {
        accountTokenInfo[accountId][USDC_HASH].shares = amount;
    }

    function setFundSshares(bytes32 strategyProviderIds, uint256 amount) external {
        strategyFundTokenInfo[strategyProviderIds][USDC_HASH].totalShares = amount;
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

    function setAccountFrozenShares(bytes32[] memory accountIds, uint256 shares) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            accountTokenInfo[accountIds[i]][USDC_HASH].frozenShares = shares;
        }
    }

    function setSPUnallocatedShares(bytes32[] memory spIds, uint256 shares) external {
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundTokenInfo[spIds[i]][USDC_HASH].frozenShares = shares;
        }
    }

    function setAccountPendingShares(bytes32[] memory accountIds, uint256 shares) external {
        for (uint256 i = 0; i < accountIds.length; i++) {
            accountTokenInfo[accountIds[i]][USDC_HASH].pendingShares = shares;
        }
    }

    function _calculateHWM(bytes32[] calldata strategyProviderIds) internal view returns (uint256[] memory) {
        StrategyFundToken memory strategyFundToken;
        uint256[] memory hwms = new uint256[](strategyProviderIds.length);

        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            strategyFundToken = strategyFundTokenInfo[strategyProviderIds[i]][USDC_HASH];
            uint256 hwm = strategyFundToken.hwm;
            uint256 totalShares = strategyFundToken.totalShares;

            if (strategyFundToken.performanceFee > 0) {
                hwm = strategyFundToken.fundAssetsAfterFee * 10 ** priceDecimal / totalShares;
            } else {
                uint256 pendingTotalShares = strategyFundToken.pendingState.pendingTotalShares;
                //New issued shares greater than 0
                if (pendingTotalShares > totalShares) {
                    //uint256 newSharePriceAfterFee = strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i];
                    //console.log("newSharePriceAfterFee",newSharePriceAfterFee);
                    uint256 newTotalIssuedShares = pendingTotalShares - totalShares;
                    //calculate new hwm
                    hwm = (
                        (
                            strategyFundToken.hwm * totalShares / 10 ** priceDecimal
                                + newTotalIssuedShares * strategyFundToken.fundAssetsAfterFee / totalShares
                        )
                    ) * 10 ** priceDecimal / pendingTotalShares;
                }
            }
            hwms[i] = hwm;
        }
        return hwms;
    }
}
