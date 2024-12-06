// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {StrategyFund, SPOperation} from "../lib/Struct.sol";
// import {console} from "forge-std/console.sol";

// contract VaultComputation {
//     using Math for uint256;

//     uint256 public priceDecimal = 6;
//     uint256 public shareDecimal = 6;
//     uint256 public assetsDecimal = 6;

//     uint256 public mainAssets;
//     uint256 public mainShares;

//     mapping(bytes32 => StrategyFund) public strategyFundById;
//     mapping(address => uint256) public sharesOfUsers;
//     mapping(uint256 => uint256) public feeRateOfFund;

//     function initialize(
//         uint256 _mainShares,
//         bytes32[] memory spIds,
//         uint256[] memory mainSharesInFund,
//         uint256[] memory spSharesInFund,
//         uint256[] memory fundAssets
//     ) public {
//         mainShares = _mainShares;
//         for (uint256 i = 0; i < spIds.length; i++) {
//             strategyFundById[spIds[i]] = StrategyFund({
//                 totalAssets: fundAssets[i],
//                 totalShares: mainSharesInFund[i] + spSharesInFund[i],
//                 mainShares: mainSharesInFund[i],
//                 strategyProviderShares: spSharesInFund[i],
//                 hwm: fundAssets[i] * 10 ** 6 / (mainSharesInFund[i] + spSharesInFund[i])
//             });
//         }
//         feeRateOfFund[0] = 10;
//         feeRateOfFund[1] = 20;
//     }

//     function initiaDeposit(uint256 amount, bytes32[] memory spIds, uint256[] memory raitos) public {
//         uint256 newSharesIssued = _convertToShares(amount, 0, mainShares, Math.Rounding.Floor);

//         mainAssets += amount;
//         mainShares += newSharesIssued;

//         for (uint256 i = 0; i < spIds.length; i++) {
//             //assume fair allocate
//             uint256 depositToFund = amount * raitos[i] / 100;
//             uint256 shares = _convertToShares(
//                 depositToFund,
//                 strategyFundById[spIds[i]].totalAssets,
//                 strategyFundById[spIds[i]].totalShares,
//                 Math.Rounding.Floor
//             );

//             strategyFundById[spIds[i]].totalAssets += depositToFund;
//             strategyFundById[spIds[i]].totalShares += shares;
//             strategyFundById[spIds[i]].mainShares += shares;
//         }
//     }

//     function deposit(
//         uint256 amount,
//         uint256 _mainAssets,
//         address receiver,
//         bytes32[] memory spIds,
//         uint256[] memory strategyFundsAssetsAfterFee,
//         uint256[] memory strategyFundsAssets
//     ) public {
//         uint256 mainSharesNewIssued = _convertToShares(amount, _mainAssets, mainShares, Math.Rounding.Floor);
//         console.log("Main Share Price:", _mainAssets * 1e6 / mainShares);
//         console.log("Main Shares New Issued", mainSharesNewIssued);

//         uint256[] memory allocatedToFunds = _distributionAssetsToFunds(amount, spIds, strategyFundsAssetsAfterFee);

//         for (uint256 i = 0; i < allocatedToFunds.length; i++) {
//             uint256 newShares = _convertToShares(
//                 allocatedToFunds[i],
//                 strategyFundsAssetsAfterFee[i],
//                 strategyFundById[spIds[i]].totalShares,
//                 Math.Rounding.Floor
//             );
//             console.log("New Deposit to Fund", allocatedToFunds[i]);
//             console.log("New Shares to Fund", newShares);

//             uint256 feeShares;
//             if (strategyFundsAssetsAfterFee[i] < strategyFundsAssets[i]) {
//                 uint256 performanceFee = strategyFundsAssets[i] - strategyFundsAssetsAfterFee[i];
//                 feeShares = _convertToShares(
//                     performanceFee,
//                     strategyFundsAssetsAfterFee[i],
//                     strategyFundById[spIds[i]].totalShares,
//                     Math.Rounding.Floor
//                 );
//                 console.log("feeShares", feeShares);
//             }
//             strategyFundById[spIds[i]].totalShares += newShares + feeShares;
//             strategyFundById[spIds[i]].strategyProviderShares += feeShares;
//             strategyFundById[spIds[i]].mainShares += newShares;
//             strategyFundById[spIds[i]].totalAssets = strategyFundsAssets[i] + allocatedToFunds[i];

//             // console.log("Fund Total Assets", strategyFundById[spIds[i]].totalAssets);
//             // console.log("Fund Total Shares", strategyFundById[spIds[i]].totalShares);
//             // console.log("----------Fund-------------------");
//         }

//         //sharesOfUsers[receiver] += newMainSharesIssued;

//         mainShares += mainSharesNewIssued;
//     }

//     function withdraw(uint256 amount) public {}

//     function strategyProviderDeposit(bytes32 spId, uint256 amount, uint256 _totalAssets) public {
//         StrategyFund storage strategyFund = strategyFundById[spId];

//         uint256 newSharesIssued = _convertToShares(amount, _totalAssets, strategyFund.totalShares, Math.Rounding.Floor);

//         strategyFund.strategyProviderShares += newSharesIssued;
//         strategyFund.totalAssets += amount;
//         strategyFund.totalShares += newSharesIssued;
//     }

//     function transferToOrderlyDex() public {}

//     function updateLedger(
//         uint256 lpDepositAssets,
//         uint256 lpWithdrawShares,
//         SPOperation[] memory spOperations,
//         bytes32[] memory spIds,
//         uint256[] memory strategyFundsAssets
//     ) public {
//         uint256 mainAssetsAfterFee;

//         uint256[] memory performanceFees = new uint256[](spIds.length);
//         uint256[] memory strategyFundsAssetsAfterFee = new uint256[](spIds.length);
//         uint256[] memory strategyFundsTemTotalShares = new uint256[](spIds.length);

//         for (uint256 i = 0; i < spIds.length; i++) {
//             strategyFundsTemTotalShares[i] = strategyFundById[spIds[i]].totalShares;
//             strategyFundById[spIds[i]].totalAssets = strategyFundsAssets[i];
//         }
//         //Performance Fee
//         console.log("SF A total shares:", strategyFundById[spIds[0]].totalShares);
//         console.log("SF B total shares:", strategyFundById[spIds[1]].totalShares);

//         console.log(
//             "Start share  A price:",
//             strategyFundsAssets[0] * 10 ** priceDecimal / strategyFundById[spIds[0]].totalShares
//         );
//         console.log(
//             "Start share  B price:",
//             strategyFundsAssets[1] * 10 ** priceDecimal / strategyFundById[spIds[1]].totalShares
//         );
//         for (uint256 i = 0; i < spIds.length; i++) {
//             StrategyFund storage strategyFund = strategyFundById[spIds[i]];
//             if (strategyFundsAssets[i] * 10 ** priceDecimal / strategyFund.totalShares > strategyFund.hwm) {
//                 //_takePerformanceFee();

//                 performanceFees[i] = (
//                     strategyFundsAssets[i] * 10 ** priceDecimal / strategyFund.totalShares - strategyFund.hwm
//                 ) * strategyFundsTemTotalShares[i] * feeRateOfFund[i] / 100 / 10 ** priceDecimal;
//                 strategyFundsAssetsAfterFee[i] = strategyFundsAssets[i] - performanceFees[i];
//                 uint256 feeShares = _convertToShares(
//                     performanceFees[i],
//                     strategyFundsAssetsAfterFee[i],
//                     strategyFundsTemTotalShares[i],
//                     Math.Rounding.Floor
//                 );
//                 console.log("feeShares", feeShares);

//                 strategyFund.strategyProviderShares += feeShares;
//                 strategyFund.totalShares += feeShares;
//             } else {
//                 strategyFundsAssetsAfterFee[i] = strategyFundsAssets[i];
//             }
//             mainAssetsAfterFee +=
//                 strategyFund.mainShares * strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i];
//         }
//         console.log("strategyFundsAssetsAfterFee A", strategyFundsAssetsAfterFee[0]);
//         console.log("strategyFundsAssetsAfterFee B", strategyFundsAssetsAfterFee[1]);
//         console.log("mainAssetsAfterFee", mainAssetsAfterFee);

//         //Handle User Operation
//         {
//             uint256 lpWithdrawAmount =
//                 _convertToAssets(lpWithdrawShares, mainAssetsAfterFee, mainShares, Math.Rounding.Floor);
//             console.log("withdrawAmount", lpWithdrawAmount);

//             // console.log("lpDepositAssets", lpDepositAssets-lpWithdrawAmount);
//             // uint256 netShares = _convertToShares(
//             //     lpDepositAssets - lpWithdrawAmount, mainAssetsAfterFee, mainShares, Math.Rounding.Floor
//             // );
//             // console.log("netShares", netShares);
//             console.log("MainShares_111:", mainShares);

//             if (lpDepositAssets > lpWithdrawAmount) {
//                 deposit(
//                     lpDepositAssets - lpWithdrawAmount,
//                     mainAssetsAfterFee,
//                     address(0),
//                     spIds,
//                     strategyFundsAssetsAfterFee,
//                     strategyFundsAssets
//                 );
//             } else if (lpDepositAssets < lpWithdrawAmount) {
//                 //withdraw();
//                 uint256[] memory allocatedToFunds =
//                     _distributionAssetsToFunds(lpWithdrawAmount - lpDepositAssets, spIds, strategyFundsAssetsAfterFee);
//                 console.log("MainShares_222:", mainShares);
//                 lpWithdrawShares = _convertToShares(
//                     lpWithdrawAmount - lpDepositAssets, mainAssetsAfterFee, mainShares, Math.Rounding.Floor
//                 );
//                 for (uint256 i = 0; i < allocatedToFunds.length; i++) {
//                     uint256 newShares = _convertToShares(
//                         allocatedToFunds[i],
//                         strategyFundsAssetsAfterFee[i],
//                         strategyFundsTemTotalShares[i],
//                         Math.Rounding.Floor
//                     );

//                     strategyFundById[spIds[i]].totalAssets -= allocatedToFunds[i];
//                     strategyFundById[spIds[i]].totalShares -= newShares;
//                     strategyFundById[spIds[i]].mainShares -= newShares;
//                 }
//                 console.log("lpWithdrawShares", lpWithdrawShares);
//                 mainShares -= lpWithdrawShares;
//                 console.log("mainShares", mainShares);
//             }
//         }
//         //Handle Strategy Provider Operation
//         {
//             uint256 withdrawAmount;

//             for (uint256 i = 0; i < spOperations.length; i++) {
//                 if (spOperations[i].withdrawShares > 0) {
//                     withdrawAmount = _convertToAssets(
//                         spOperations[i].withdrawShares,
//                         strategyFundsAssetsAfterFee[i],
//                         strategyFundsTemTotalShares[i],
//                         Math.Rounding.Floor
//                     );
//                 } else {
//                     withdrawAmount = 0;
//                 }
//                 // console.log("sp depositAmount", spOperations[i].depositAssets);
//                 console.log("sp withdrawAmount", withdrawAmount);

//                 if (spOperations[i].depositAssets > withdrawAmount) {
//                     //spDeposit
//                     console.log("sp net Deposit: %d", spOperations[i].depositAssets - withdrawAmount);
//                     uint256 newIssuedShares = _convertToShares(
//                         spOperations[i].depositAssets - withdrawAmount,
//                         strategyFundsAssetsAfterFee[i],
//                         strategyFundsTemTotalShares[i],
//                         Math.Rounding.Floor
//                     );
//                     console.log("Fund Assets after fees", strategyFundsAssetsAfterFee[i]);
//                     console.log("Fund Total Shares", strategyFundById[spIds[i]].totalShares);
//                     console.log("newIssuedShares", newIssuedShares);

//                     strategyFundById[spIds[i]].totalAssets =
//                         strategyFundById[spIds[i]].totalAssets + spOperations[i].depositAssets - withdrawAmount;
//                     strategyFundById[spIds[i]].totalShares += newIssuedShares;
//                     strategyFundById[spIds[i]].strategyProviderShares += newIssuedShares;
//                 } else {
//                     strategyFundById[spIds[i]].totalAssets =
//                         strategyFundById[spIds[i]].totalAssets + spOperations[i].depositAssets - withdrawAmount;
//                     strategyFundById[spIds[i]].totalShares -= spOperations[i].withdrawShares;
//                     strategyFundById[spIds[i]].strategyProviderShares -= spOperations[i].withdrawShares;
//                 }
//             }
//         }
//         //Update HWM
//         console.log(strategyFundsAssetsAfterFee[0]);
//         console.log(strategyFundsTemTotalShares[0]);
//         for (uint256 i = 0; i < spIds.length; i++) {
//             if (performanceFees[i] > 0) {
//                 strategyFundById[spIds[i]].hwm =
//                     strategyFundsAssetsAfterFee[i] * 10 ** priceDecimal / strategyFundsTemTotalShares[i];
//             } else {
//                 //New issued shares greater than 0
//                 if (strategyFundById[spIds[i]].totalShares > strategyFundsTemTotalShares[i]) {
//                     //uint256 newSharePriceAfterFee = strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i];
//                     //console.log("newSharePriceAfterFee",newSharePriceAfterFee);
//                     uint256 newTotalIssuedShares =
//                         strategyFundById[spIds[i]].totalShares - strategyFundsTemTotalShares[i];
//                     console.log("newTotalIssuedShares", newTotalIssuedShares);
//                     // console.log(
//                     //     "fenmu:",
//                     //     strategyFundById[spIds[i]].hwm / 10 ** priceDecimal * strategyFundsTemTotalShares[i]
//                     //         + newTotalIssuedShares * strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i]
//                     // );
//                     // console.log("fenzi:", strategyFundById[spIds[i]].totalShares);
//                     //calculate new hwm
//                     strategyFundById[spIds[i]].hwm = (
//                         (
//                             strategyFundById[spIds[i]].hwm * strategyFundsTemTotalShares[i] / 10 ** priceDecimal
//                                 + newTotalIssuedShares * strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i]
//                         )
//                     ) * 10 ** 6 / strategyFundById[spIds[i]].totalShares;
//                 }
//                 //else hwm doesn't change
//             } //          （ 785714285 *  3.5  + 15244425 * 285714285 ） / 17744425
//         }
//     }
//     /*======================================================================
//     *  INTERNAL
//     *======================================================================*/

//     function _takePerformanceFee(uint256 newTotalAssets, uint256 preTotalAssets) internal view returns (uint256) {}
//     function _updateHighWaterMark() internal view returns (uint256) {}

//     function _distributionAssetsToFunds(
//         uint256 amount,
//         bytes32[] memory spIds,
//         uint256[] memory strategyFundsAssetsAfterFee
//     ) internal view returns (uint256[] memory) {
//         uint256[] memory depositDistribution = new uint256[](spIds.length);
//         StrategyFund memory strategyFund;
//         uint256 totalStrategyFundAssets;
//         // console.log("strategyFundsAssetsAfterFee A", strategyFundsAssetsAfterFee[0]);
//         // console.log("strategyFundsAssetsAfterFee B", strategyFundsAssetsAfterFee[1]);
//         for (uint256 i = 0; i < spIds.length; i++) {
//             strategyFund = strategyFundById[spIds[i]];
//             totalStrategyFundAssets +=
//                 strategyFund.mainShares * strategyFundsAssetsAfterFee[i] / strategyFund.totalShares;
//         }
//         console.log("net deposit", amount);

//         for (uint256 i = 0; i < spIds.length; i++) {
//             strategyFund = strategyFundById[spIds[i]];
//             uint256 mainAssetsInFund =
//                 strategyFund.mainShares * strategyFundsAssetsAfterFee[i] / strategyFund.totalShares;
//             depositDistribution[i] = amount * mainAssetsInFund / totalStrategyFundAssets;
//         }
//         console.log("depositDistribution A", depositDistribution[0]);
//         console.log("depositDistribution B", depositDistribution[1]);

//         return depositDistribution;
//     }
//     /**
//      * @dev Internal conversion function (from assets amount to shares) with support for rounding direction.
//      */

//     function _convertToShares(uint256 amount, uint256 _totalAssets, uint256 _toatlShares, Math.Rounding rounding)
//         internal
//         view
//         virtual
//         returns (uint256)
//     {
//         return (_toatlShares == 0)
//             ? amount.mulDiv(10 ** shareDecimal, 10 ** assetsDecimal, rounding)
//             : amount.mulDiv(_toatlShares, _totalAssets, rounding);
//     }

//     /**
//      * @dev Internal conversion function (from shares to assets) with support for rounding direction.
//      */
//     function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _toatlShares, Math.Rounding rounding)
//         internal
//         view
//         virtual
//         returns (uint256 assets)
//     {
//         return (_toatlShares == 0)
//             ? shares.mulDiv(10 ** assetsDecimal, 10 ** shareDecimal, rounding)
//             : shares.mulDiv(_totalAssets, _toatlShares, rounding);
//     }

//     /*======================================================================
//     *   VIEW
//     *======================================================================*/
//     function convertToShares(uint256 amount, uint256 _totalAssets, uint256 _toatlShares)
//         external
//         view
//         returns (uint256)
//     {
//         return _convertToShares(amount, _totalAssets, _toatlShares, Math.Rounding.Floor);
//     }

//     function convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _toatlShares)
//         external
//         view
//         returns (uint256)
//     {
//         return _convertToAssets(shares, _totalAssets, _toatlShares, Math.Rounding.Floor);
//     }

//     function getAssetsDistribution(uint256 amount, bytes32[] memory spIds, uint256[] memory strategyFundsAssets)
//         public
//         view
//         returns (uint256[] memory)
//     {
//         return _distributionAssetsToFunds(amount, spIds, strategyFundsAssets);
//     }

//     function getPerformanceFee(bytes32[] memory spIds, uint256[] memory strategyFundsAssets)
//         external
//         view
//         returns (uint256)
//     {
//         uint256 mainAssetsAfterFee;
//         for (uint256 i = 0; i < spIds.length; i++) {
//             StrategyFund memory strategyFund = strategyFundById[spIds[i]];

//             if (strategyFundsAssets[i] * strategyFund.totalShares > strategyFund.totalShares * strategyFund.totalAssets)
//             {
//                 strategyFundsAssets[i] -= _takePerformanceFee(strategyFundsAssets[i], strategyFund.totalAssets);
//             }
//             mainAssetsAfterFee += strategyFund.mainShares * strategyFundsAssets[i] / strategyFund.totalShares;
//         }
//         return mainAssetsAfterFee;
//     }

//     function getStrategyFund(bytes32 spId) public view returns (StrategyFund memory) {
//         return strategyFundById[spId];
//     }
// }
