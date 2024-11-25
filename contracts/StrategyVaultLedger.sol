// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    Account,
    StrategyFund,
    StrategyFundAssets,
    FundTransferParams,
    BasicInfo,
    StrategyExecution,
    StrategyProviderOperation,
    UpdateLedgerParams,
    PeriodState,
    UserOperation,
    AssetsDistribution,
    UpdateUserClaim,
    SettleType,
    SettleParams
} from "./lib/types/LedgerStruct.sol";

import {VaultType, OperationData} from "./lib/types/VaultStruct.sol";
import {StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {console} from "forge-std/console.sol";

/*todo
    - modifier
    - is necessary to verify in vaultDeposit

*/
contract StrategyVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable {
    using Math for uint256;

    uint256 public priceDecimal = 6;
    uint256 public shareDecimal = 6;
    uint256 public assetsDecimal = 6;

    uint256 public pendingDepositMainshares;
    uint256 public pendingWithdrawMainshares;
    uint256 public pendingMainShares;
    uint256 public pendingMainAssetsAfterFee;
    uint256 public pendingDepositAssets;
    uint256 public pendingWithdrawAssets;

    uint256 public mainAssets;
    uint256 public mainShares;

    uint256 public nonce;
    uint256 public latestPeriodId;

    address public crossChainManagerAddress;

    /// @dev fee rate of each strategy fund
    mapping(uint256 => uint256) public feeRateOfFund;
    /// @dev allowed strategy provider
    mapping(bytes32 => bool) public isAllowedStraegyProvider;
    /// @dev strategy fund information by strategy provider id
    mapping(bytes32 => StrategyFund) public strategyFundById;
    /// @dev account information by account id
    mapping(bytes32 => Account) public accountById;
    /// @dev Determines whether the operation corresponding to the nonce is executed by the contract
    mapping(uint256 => bool) public isOpHandeled;

    /// @notice Require only operator can call
    // modifier onlyOperator() {
    //     // Update: operatorManagerZipAddress is also allowed to call
    //     require(
    //         msg.sender != operatorAddress &&
    //             msg.sender != operatorManagerZipAddress,
    //         OnlyOperatorCanCall()
    //     );
    //     _;
    // }
    // modifier onlyVaultCrossChainManager() {
    //     require(
    //         msg.sender == crossChainManagerAddress,
    //         OnlyVaultCrossChainManagerCanCall()
    //     );
    //     _;
    // }

    error InsufficientBalance();
    error AlreadyAllocatedShare();

    event AccountDeposit(OperationData operationData);
    event AccountWithdraw(OperationData operation, uint256 chainId);
    event SPDeposit(OperationData operationData);
    event SPWithdraw();
    event SettleSuccess(PeriodState periodState);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize() external initializer {
        __Ownable2Step_init();
        __Ownable_init(msg.sender); //owner() initialized to msg.sender

        __UUPSUpgradeable_init();
    }

    // function receiveMessageFromStrategyVault(
    //     StrategyVaultMessage memory message
    // ) external onlyVaultCrossChainManager {
    //     if (message.payloadType == PayloadType.DEPOSIT) {
    //         DepositData depositData = abi.decode(message.payload);
    //         _vaultDeposit();
    //     }
    // }

    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

    //--------------------------------------FROM VAULT-----------------------------------------
    function accountDeposit(OperationData memory operationData, uint256 chainId) external {
        bytes32 accountId = operationData.accountId;

        accountById[accountId].unAllocatedAssets += operationData.amount;
        accountById[accountId].assets += operationData.amount;

        //emit AccountDeposit(operationData, chainId);
    }

    function strategyProviderDeposit(OperationData memory operationData) external {
        bytes32 spId = operationData.strategyProviderId;

        //check sp id is allowed
        if (!isAllowedStraegyProvider[spId]) {
            revert("StrategyProviderNotAllowed");
        }
    }

    function accountWithdraw(OperationData memory operationData, uint256 chainId) external {
        bytes32 accountId = operationData.accountId;
        Account storage account = accountById[accountId];

        if (operationData.amount > account.shares - account.frozenShares) {
            revert();
        }

        accountById[accountId].frozenShares += operationData.amount;

        emit AccountWithdraw(operationData, chainId);
    }

    function strategyProviderWithdraw(OperationData memory operationData, uint256 chainId) external {}

    //--------------------------------------FROM BE--------------------------------------------
    //only for test
    function initializeStrategyFund(
        uint256 _mainShares,
        bytes32[] memory spIds,
        uint256[] memory mainSharesInFund,
        uint256[] memory spSharesInFund,
        uint256[] memory fundAssets
    ) external {
        mainShares = _mainShares;
        for (uint256 i = 0; i < spIds.length; i++) {
            strategyFundById[spIds[i]].strategyProviderId = spIds[i];
            strategyFundById[spIds[i]].mainShares = mainSharesInFund[i];
            strategyFundById[spIds[i]].strategyProviderShares = spSharesInFund[i];
            strategyFundById[spIds[i]].totalAssets = fundAssets[i];
            strategyFundById[spIds[i]].totalShares = mainSharesInFund[i] + spSharesInFund[i];
            strategyFundById[spIds[i]].hwm = fundAssets[i] * 10 ** 6 / (mainSharesInFund[i] + spSharesInFund[i]);
        }
        
        feeRateOfFund[0] = 10;
        feeRateOfFund[1] = 20;
    }

    function updateStrategyFundAssets(uint256 periodId, StrategyFundAssets[] calldata strategyFundAssets) external {
        if (periodId != latestPeriodId) {
            revert("Invalid periodId");
        }
        uint256 mainAssetsAfterFee;

        for (uint256 i = 0; i < strategyFundAssets.length; i++) {
            bytes32 strategyProviderId = strategyFundAssets[i].strategyProviderId;
            uint256 fundAssets = strategyFundAssets[i].totalAssets;

            StrategyFund storage strategyFund = strategyFundById[strategyProviderId];

            //Performance Fee
            uint256 performanceFee = (
                fundAssets * 10 ** priceDecimal / strategyFund.totalShares - strategyFund.hwm
            ) * strategyFund.totalShares * feeRateOfFund[i] / 100 / 10 ** priceDecimal;
            uint256 fundAssetsAferFee = fundAssets - performanceFee;

            uint256 feeShares = _convertToShares(
                performanceFee,
                strategyFund.fundAssetsAfterFee,
                strategyFund.totalShares,
                Math.Rounding.Floor
            );
            //Update pending state
            strategyFund.pendingState.pendingPerformanceFee = performanceFee;
            strategyFund.pendingState.pendingFundAssets = fundAssets;
            strategyFund.fundAssetsAfterFee = fundAssets - performanceFee;
            strategyFund.pendingState.pendingStrategyProviderShares += feeShares;

            mainAssetsAfterFee += strategyFund.mainShares * fundAssetsAferFee / strategyFund.totalShares;
        }

        pendingMainAssetsAfterFee = mainAssetsAfterFee;
    }

    function updateAccountAndStrategyFund(uint256 periodId, UpdateLedgerParams calldata updateUserLedgerParams)
        external
    {
        if (periodId != latestPeriodId) {
            revert("Invalid periodId");
        }

        // //User Operation
        // if (updateUserLedgerParams.userOperations.length != 0) {
        //     for (uint256 i = 0; i < updateUserLedgerParams.userOperations.length; i++) {
        //         UserOperation memory userOperation = updateUserLedgerParams.userOperations[i];

        //         bytes32 accountId = userOperation.accountId;
        //         Account storage account = accountById[accountId];

        //         //check
        //         if (userOperation.depositAssets > 0) {
        //             //deposit
        //             if (userOperation.depositAssets > account.unAllocatedAssets) {
        //                 revert();
        //             }
        //             uint256 depositShares = userOperation.depositAssets * mainShares / pendingMainAssetsAfterFee;
        //             account.pendingShares += depositShares;
        //             pendingMainShares += depositShares;
        //             // account.pendingDepositShares += depositShares;
        //             // pendingDepositMainshares += depositShares;
        //         } else if (userOperation.withdrawShares > 0) {
        //             //withdraw
        //             if (userOperation.withdrawShares > account.unAllocatedShares) {
        //                 revert();
        //             }

        //             account.pendingShares -= userOperation.withdrawShares;
        //             pendingMainShares -= userOperation.withdrawShares;
        //         }
        //     }
        // }

        // //SP Operation
        // for (uint256 i = 0; i < updateUserLedgerParams.strategyProviderOperations.length; i++) {
        //     StrategyProviderOperation memory spOperation = updateUserLedgerParams.strategyProviderOperations[i];

        //     bytes32 spId = spOperation.strategyProviderId;
        //     StrategyFund storage strategyFund = strategyFundById[spId];

        //     if (spOperation.depositAssets > 0) {
        //         //deposit
        //         if (spOperation.depositAssets > strategyFund.unAllocatedAssets) {
        //             revert();
        //         }
        //         uint256 spDepositShares =
        //             spOperation.depositAssets * strategyFund.fundShares / strategyFund.fundAssetsAfterFee;
        //         strategyFund.pendingFundShares += spDepositShares;
        //         strategyFund.pendingStrategyProviderShares += spDepositShares;
        //         strategyFund.pendingFundAssets += spOperation.depositAssets;
        //     }

        //     if (spOperation.withdrawShares > 0) {
        //         //withdraw
        //         if (spOperation.withdrawShares > strategyFund.unAllocatedShares) {
        //             revert();
        //         }
        //         uint256 spWithdrawAmount =
        //             spOperation.withdrawShares * strategyFund.fundAssetsAfterFee / strategyFund.fundShares;
        //         strategyFund.pendingFundShares -= spOperation.withdrawShares;
        //         strategyFund.pendingStrategyProviderShares -= spOperation.withdrawShares;
        //         strategyFund.pendingFundAssets -= spWithdrawAmount;
        //     }
        // }
    }

    function allocatedFunds(bytes32[] calldata strategyProviderIds) external {
        //allocate funds to strategyFund

        //Allocation
        // if (pendingDepositAssets > pendingWithdrawAssets) {
        //     //deposit
        //     for (uint256 i = 0; i < updateUserLedgerParams.strategyProviderInfos.length; i++) {
        //         StrategyProviderOperation memory spOperation = updateUserLedgerParams.strategyProviderInfos[i];
        //         bytes32 spId = spOperation.strategyProviderId;
        //         StrategyFund storage strategyFund = strategyFundById[spId];

        //         uint256 allocatedAssets;
        //         strategyFund.pendingFundAssets += allocatedAssets;
        //         strategyFund.pendingFundShares +=
        //             allocatedAssets * strategyFund.shares / strategyFund.pendingAssetsAfterFee;
        //     }
        //     //withdraw
        //     for (uint256 i = 0; i < updateUserLedgerParams.strategyProviderInfos.length; i++) {}
        // }
    }

    // function updateStrategyFundHwm(bytes32[] calldata strategyProviderIds) external {
    //     for (uint256 i = 0; i < strategyProviderIds.length; i++) {
    //         StrategyFund storage strategyFund = strategyFundById[strategyProviderIds[i]];

    //         if (strategyFund.pendingPerformanceFee > 0) {
    //             strategyFund.hwm = strategyFund.fundAssetsAfterFee * 10 ** priceDecimal / strategyFund.fundShares;
    //         } else {
    //             //New issued shares greater than 0
    //             // if (strategyFundById[spIds[i]].totalShares > strategyFundsTemTotalShares[i]) {
    //             //     //uint256 newSharePriceAfterFee = strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i];
    //             //     //console.log("newSharePriceAfterFee",newSharePriceAfterFee);
    //             //     uint256 newTotalIssuedShares =
    //             //         strategyFundById[spIds[i]].totalShares - strategyFundsTemTotalShares[i];
    //             //     console.log("newTotalIssuedShares", newTotalIssuedShares);
    //             //     // console.log(
    //             //     //     "fenmu:",
    //             //     //     strategyFundById[spIds[i]].hwm / 10 ** priceDecimal * strategyFundsTemTotalShares[i]
    //             //     //         + newTotalIssuedShares * strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i]
    //             //     // );
    //             //     // console.log("fenzi:", strategyFundById[spIds[i]].totalShares);
    //             //     //calculate new hwm
    //             //     strategyFundById[spIds[i]].hwm = (
    //             //         (
    //             //             strategyFundById[spIds[i]].hwm * strategyFundsTemTotalShares[i] / 10 ** priceDecimal
    //             //                 + newTotalIssuedShares * strategyFundsAssetsAfterFee[i] / strategyFundsTemTotalShares[i]
    //             //         )
    //             //     ) * 10 ** 6 / strategyFundById[spIds[i]].totalShares;
    //         }
    //         //else hwm doesn't change
    //         //          （ 785714285 *  3.5  + 15244425 * 285714285 ） / 17744425
    //     }
    // }

    function settle(uint256 periodId, SettleParams memory settleParams) external {}

    function transferToOrderlyDex(uint256 periodId, FundTransferParams calldata fundTransferParams) external {
        uint256 totalTransferredAssets;

        for (uint256 i = 0; i < fundTransferParams.assetsDistributions.length; i++) {
            totalTransferredAssets += fundTransferParams.assetsDistributions[i].assets;
        }
        if (totalTransferredAssets != fundTransferParams.totalAssets) {
            revert("Invalid totalAssets");
        }

        for (uint256 i = 0; i < fundTransferParams.assetsDistributions.length; i++) {
            //contruct StrategyExecution
            // StrategyExecution memory strategyExecution = StrategyExecution({
            //     basicInfo: BasicInfo({
            //         vaultType: VaultType.USER,
            //         periodId: periodId,
            //         vaultId: keccak256(abi.encodePacked(vault, keccak256(abi.encodePacked(broker)))),
            //         tokenHash: tokenHash,
            //         brokerHash: keccak256(abi.encodePacked(broker))
            //     }),
            //     chainId: chainId,
            //     assets: assets
            // });
        }
    }

    function updateAccountUnclaimed(uint256 periodId, UpdateUserClaim[] calldata updateUserClaim) external {}

    //--------------------------------------CONFIG--------------------------------------------
    function setFeeRate(bytes32[] calldata strategyProviderIds) external {}

    function setCrossChainManagerAddress(address _crossChainManagerAddress) external onlyOwner {
        crossChainManagerAddress = _crossChainManagerAddress;
    }

    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/
    function checkState(uint256 periodId, bytes32[] calldata strategyProviderIds, bytes32[] calldata accountIds)
        external
        returns (PeriodState memory periodState)
    {
        /*
            check peridoId
            For each account:
                 shares + pendingDepositShares -  pendingWithdrawShares
            For each strategyFund:

            For mainshares:

        */
    }

    function convertToShares(uint256 amount, uint256 _totalAssets, uint256 _toatlShares)
        external
        view
        returns (uint256)
    {
        return _convertToShares(amount, _totalAssets, _toatlShares, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _toatlShares)
        external
        view
        returns (uint256)
    {
        return _convertToAssets(shares, _totalAssets, _toatlShares, Math.Rounding.Floor);
    }

    function getStrategyFund(bytes32 spId) public view returns (StrategyFund memory) {
        return strategyFundById[spId];
    }
    /*=========================================================================================
    *                                       INTERNAL
    *=========================================================================================*/
    /**
     * @dev Internal conversion function (from assets amount to shares) with support for rounding direction.
     */

    function _convertToShares(uint256 amount, uint256 _totalAssets, uint256 _toatlShares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return (_toatlShares == 0)
            ? amount.mulDiv(10 ** shareDecimal, 10 ** assetsDecimal, rounding)
            : amount.mulDiv(_toatlShares, _totalAssets, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _toatlShares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 assets)
    {
        return (_toatlShares == 0)
            ? shares.mulDiv(10 ** assetsDecimal, 10 ** shareDecimal, rounding)
            : shares.mulDiv(_totalAssets, _toatlShares, rounding);
    }

    function _distributionAssetsToFunds() internal view returns (uint256[] memory) {}
}
