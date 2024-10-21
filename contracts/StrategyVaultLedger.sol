// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Account, DepositData, StrategyVault, StrategyProvider, UserDepositInfo} from "./lib/Struct.sol";

import {console} from "forge-std/console.sol";

/*todo
    - modifier
    - is necessary to verify in vaultDeposit

*/
contract StrategyVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable {
    using Math for uint256;

    uint256 public totalShares;
    address public crossChainManagerAddress;

    mapping(bytes32 => StrategyVault) public strategyVaultById;
    mapping(bytes32 => StrategyProvider) public strategyProviderById;
    mapping(bytes32 => Account) public accountById;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

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

    function vaultDeposit(DepositData memory depositData) external {
        console.log("welcome to vaultDeposit!");
        //update vault and account balance
        strategyVaultById[depositData.vaultId].balance += depositData.amount;
        accountById[depositData.accountId].balance += depositData.amount;
    }

    function allocateUserShare(
        UserDepositInfo[] memory userDepositInfos,
        uint256 totalValue
    ) external {
        //iterate over userShareUpload
        for (uint256 i = 0; i < userDepositInfos.length; i++) {
            bytes32 accountId = userDepositInfos[i].accountId;
            uint256 depositAmount = userDepositInfos[i].depositAmount;
            //validate user balance greater than depositAmount
            if (accountById[accountId].balance < depositAmount) {
                revert InsufficientBalance();
            }

            if (
                accountById[accountId].balance <
                depositAmount + accountById[accountId].allocatedBalance
            ) {
                revert AlreadyAllocatedShare();
            }

            //calculate shareAmount of user
            uint256 userShare = _convertToShares(
                depositAmount,
                totalValue,
                Math.Rounding.Floor
            );

            accountById[accountId].share += userShare;
            totalShares += userShare;
        }
    }

    /**
     * @dev Internal conversion function (from assets amount to shares) with support for rounding direction.
     */
    function _convertToShares(
        uint256 amount,
        uint256 totalValue,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        return
            amount.mulDiv(
                totalShares + 10 ** _decimalsOffset(),
                totalValue + 1,
                rounding
            );
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    // function allocateFundsToStrategyProviders(
    //     address[] calldata strategyProviders,
    //     uint256[] calldata percentages
    // ) external onlyOwner {
    //     require(
    //         _providerIds.length == _percentages.length,
    //         "Arrays length mismatch"
    //     );
    //     require(_totalAmount > 0, "Amount must be greater than 0");

    //     uint256 totalPercentage = 0;
    //     for (uint256 i = 0; i < _percentages.length; i++) {
    //         totalPercentage += _percentages[i];
    //     }
    //     require(totalPercentage == 10000, "Total percentage must be 100%");

    //     uint256 remainingAmount = _totalAmount;
    //     for (uint256 i = 0; i < _providerIds.length; i++) {
    //         uint256 providerId = _providerIds[i];
    //         require(
    //             strategyProviderById[providerId].isActive,
    //             "Provider not active"
    //         );

    //         uint256 amount = i == _providerIds.length - 1
    //             ? remainingAmount
    //             : (_totalAmount * _percentages[i]) / 10000;

    //         StrategyProvider storage provider = strategyProviderById[
    //             providerId
    //         ];
    //         provider.allocatedFunds += amount;
    //         remainingAmount -= amount;

    //         emit FundsAllocated(providerId, amount);
    //     }

    //     // 转移总资金到 vault
    //     asset.safeTransferFrom(msg.sender, address(this), _totalAmount);
    // }

    // function uploadTVLAndAllocalteShare() external {}

    /*======================================================================
     *   Strategy Execution
     *======================================================================*/
    // function transferToOrderlyStrategy(
    //     StrategyExecution memory strategyExecution
    // ) external onlyOperator {
    //     bytes32 memory vaultId;
    //     bytes32 memory strategyProviderId;

    //     if (strategyExecution.vaultType == VaultType.PROTOCOL) {
    //         vaultId = keccak256(abi.encodePacked(brokerHash, vault));
    //         strategyProviderId = keccak256(
    //             abi.encodePacked(vault, strategyProvider, brokerHash)
    //         );
    //     } else if (strategyExecution.vaultType == VaultType.USER) {
    //         vaultId = keccak256(
    //             abi.encodePacked(vault, strategyProvider, brokerHash)
    //         );
    //     } else {
    //         revert InvailidStrategyVault();
    //     }

    //     //1. check

    //     //strategyProvider balance
    //     strategyProvider = strategyProviderById[strategyProviderId];
    //     require(strategyProvider.balance >= amount);
    //     //check sig to ensure to address is dex vault contract

    //     //2. effect
    //     strategyProvider.strategyBalance[strategy] += amount;
    //     strategyVaultrById[vaultId].balance -= amount;

    //     //3. send cross-chain tx
    //     StrategyVaultMessage memory SVMessage = StrategyVaultMessage();

    //     IVaultCrossChainManager(crossChainManagerAddress).ledgerSendToVault(
    //         SVMessage
    //     );
    // }

    // function transferFromOrderlyDexToStrategyVault(
    //     StrategyExecution memory strategyExecution
    // ) external onlyOperator {
    //     bytes32 memory vaultId;
    //     bytes32 memory strategyProviderId;

    //     if (strategyExecution.vaultType == VaultType.PROTOCOL) {
    //         vaultId = keccak256(abi.encodePacked(brokerHash, vault));
    //         strategyProviderId = keccak256(
    //             abi.encodePacked(vault, strategyProvider, brokerHash)
    //         );
    //     } else if (strategyExecution.vaultType == VaultType.USER) {
    //         vaultId = keccak256(
    //             abi.encodePacked(vault, strategyProvider, brokerHash)
    //         );
    //     } else {
    //         revert InvailidStrategyVault();
    //     }
    //     //check
    //     //strategyProvider on orderly stgy balance
    //     //check sig to ensure to address is stgy vault contract

    //     //effect

    //     //send cross-chain tx
    //     StrategyVaultMessage memory SVMessage = StrategyVaultMessage();

    //     IVaultCrossChainManager(crossChainManagerAddress).ledgerSendToVault(
    //         SVMessage
    //     );
    // }

    /*======================================================================
     *   Withdraw Functions
     *======================================================================*/
    // function withdraw() external onlyOperator {
    //     //calculate ID
    //     bytes32 strategyProviderId = keccak256(
    //         abi.encodePacked(vault, strategyProvider, brokerHash)
    //     );
    //     bytes32 vaultId = keccak256(abi.encodePacked(brokerHash, vault));

    //     //1. check
    //     //check balance
    //     //check sig to ensure to address is sender
    // }

    /*======================================================================
     *   Config Functions
     *======================================================================*/
    // function addStrategyProvider(address providerAddress) external {
    //     strategyProviderCount++;
    //     strategyProviderById[strategyProviderCount] = StrategyProvider({
    //         providerAddress: _providerAddress,
    //         allocatedFunds: 0,
    //         isActive: true
    //     });
    //     emit StrategyProviderAdded(strategyProviderCount, _providerAddress);
    // }

    /*======================================================================
     *   View Functions
     *======================================================================*/

    /*======================================================================
     *   Internal Functions
     *======================================================================*/

    // struct UserInfo {
    //     bytes32 accountId;
    //     uint256 amount;
    // }

    // function uploadShare(UserInfo[] memory userInfo, TVL) external {}

    //--------------------------------------CONFIG--------------------------------------------
    function setCrossChainManagerAddress(
        address _crossChainManagerAddress
    ) external onlyOwner {
        crossChainManagerAddress = _crossChainManagerAddress;
    }
}
