// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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
    AllocateFundRes,
    StrategyFundState,
    ClaimInfo,
    DexRequest
} from "../lib/types/LedgerStruct.sol";
import {OperationData} from "../lib/types/VaultStruct.sol";
import {PayloadType} from "../lib/types/CrossChainStruct.sol";
import {IProtocolVaultLedger} from "../interfaces/IProtocolVaultLedger.sol";
import {ILedgerCoreImpl} from "../interfaces/ILedgerCoreImpl.sol";
import {ILedgerExtension} from "../interfaces/ILedgerExtension.sol";
import {LedgerBase} from "./LedgerBase.sol";
import {LedgerUtils} from "../lib/utils/LedgerUtils.sol";
import {USDC_DECIMAL, LEDGER_STORAGE_LOCATION, USDC_HASH} from "../lib/types/Constants.sol";
import {VaultUtils} from "../lib/utils/VaultUtils.sol";

/// @title protocol vault ledger
/// @notice This contract is used to record all information of protocol vault

contract ProtocolVaultLedger is Ownable2StepUpgradeable, UUPSUpgradeable, LedgerBase, IProtocolVaultLedger {
    using Math for uint256;

    /// @custom:storage-location erc7201:ProtocolVaultLedger.impl
    struct ImplStorage {
        address core;
        address extension;
    }

    function _getLedgerImplStorage() private pure returns (ImplStorage storage $) {
        assembly {
            $.slot := LEDGER_STORAGE_LOCATION
        }
    }

    /// @notice Require only crossChainManager can call
    modifier onlyVaultCrossChainManager() {
        if (msg.sender != crossChainManager) {
            revert InvalidVaultCrossChainManager();
        }
        _;
    }

    /// @notice Only operator can call
    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert InvalidOperator();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        __Ownable_init(owner);

        __UUPSUpgradeable_init();
    }

    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

    //--------------------------------------FROM VAULT-----------------------------------------
    /// @notice Handles operations from vault
    /// @param payloadType The type of operation
    /// @param chainId The source chain ID
    /// @param operationData The operation data
    function handleOpFromVault(PayloadType payloadType, uint256 chainId, OperationData calldata operationData)
        external
        onlyVaultCrossChainManager
    {
        _delegateCall(
            abi.encodeWithSelector(ILedgerExtension.handleOpFromVault.selector, payloadType, chainId, operationData),
            _getLedgerImplStorage().extension
        );
    }

    /// @notice Operator upload NAV of each strategy fund and compute performance fee at the beginning of the period
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyFundAssets strategy fund assets info
    /// @param signature signature of BE
    function updateStrategyFundAssets(
        uint256 periodId,
        bytes32 vaultId,
        UpdateStrategyFundAssetsParams[] calldata strategyFundAssets,
        bytes calldata signature
    ) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(
                ILedgerCoreImpl.updateStrategyFundAssets.selector, periodId, vaultId, strategyFundAssets, signature
            ),
            _getLedgerImplStorage().core
        );
    }

    /// @notice Operator update LP and strategy fund info
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param updateUserLedgerParams update user ledger info
    /// @param signature signature of BE
    function updateLPAndStrategyFund(
        uint256 periodId,
        bytes32 vaultId,
        UpdateLedgerParams[] calldata updateUserLedgerParams,
        bytes calldata signature
    ) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(
                ILedgerCoreImpl.updateLPAndStrategyFund.selector, periodId, vaultId, updateUserLedgerParams, signature
            ),
            _getLedgerImplStorage().core
        );
    }

    /// @notice Operator allocate all lp deposit and withdraw to strategy funds after handle all lp operation
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyProviderIds each strategy provider id
    /// @param signature signature of BE
    function allocateToFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(
                ILedgerCoreImpl.allocateToFunds.selector, periodId, vaultId, strategyProviderIds, signature
            ),
            _getLedgerImplStorage().core
        );
    }

    /// @notice Operator settle main and strategy fund info after check all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param strategyProviderIds each strategy provider id
    /// @param signature signature of BE
    function settleMainAndStrategyFunds(
        uint256 periodId,
        bytes32 vaultId,
        bytes32[] calldata strategyProviderIds,
        bytes calldata signature
    ) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(
                ILedgerCoreImpl.settleMainAndStrategyFunds.selector, periodId, vaultId, strategyProviderIds, signature
            ),
            _getLedgerImplStorage().core
        );
    }

    /// @notice Operator settle all LP infos after check all operations
    /// @param periodId period id
    /// @param vaultId vault id
    /// @param accountIds each account id
    /// @param signature signature of BE
    function settleAccounts(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds, bytes calldata signature)
        external
        onlyOperator
    {
        _delegateCall(
            abi.encodeWithSelector(ILedgerCoreImpl.settleAccounts.selector, periodId, vaultId, accountIds, signature),
            _getLedgerImplStorage().core
        );
    }

    /// @notice Operator update period id after last period finish
    /// @param periodId latest periodId
    /// @param vaultId vault id
    /// @param signature signature of BE
    function updatePeriodId(uint256 periodId, bytes32 vaultId, bytes calldata signature) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(ILedgerCoreImpl.updatePeriodId.selector, periodId, vaultId, signature),
            _getLedgerImplStorage().core
        );
    }

    /// @notice Handle DEX requests (delegated to extensions contract)
    /// @param dexRequests Array of DEX requests
    /// @param signature Signature for verification

    function handleDexRequests(DexRequest[] calldata dexRequests, bytes calldata signature) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(ILedgerExtension.handleDexRequests.selector, dexRequests, signature),
            _getLedgerImplStorage().extension
        );
    }

    /// @notice Distribute assets to strategy (delegated to core implementation contract)
    /// @param periodId Period ID
    /// @param vaultId Vault ID
    /// @param assetsDistributions Asset distribution info
    /// @param signature Signature for verification
    function distributeAssets(
        uint256 periodId,
        bytes32 vaultId,
        AssetsDistribution[] memory assetsDistributions,
        bytes calldata signature
    ) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(
                ILedgerCoreImpl.distributeAssets.selector, periodId, vaultId, assetsDistributions, signature
            ),
            _getLedgerImplStorage().core
        );
    }

    /// @notice Update unclaimed assets (delegated to core implementation contract)
    /// @param chainId Chain ID
    /// @param periodId Period ID
    /// @param vaultId Vault ID
    /// @param requestIds Request ID array
    /// @param signature Signature for verification
    function updateUnclaimed(
        uint256 chainId,
        uint256 periodId,
        uint256 ccFee,
        bytes32 vaultId,
        bytes32[] memory requestIds,
        bytes calldata signature
    ) external onlyOperator {
        _delegateCall(
            abi.encodeWithSelector(
                ILedgerCoreImpl.updateUnclaimed.selector, chainId, periodId, ccFee, vaultId, requestIds, signature
            ),
            _getLedgerImplStorage().core
        );
    }
    /// @notice Remove invalid frozen shares (delegated to extensions contract)
    /// @param vaultId The vault ID
    /// @param params The parameters containing the invalid frozen shares to remove
    /// @param signature The signature to verify

    function removeInvalidFrozenShares(bytes32 vaultId, UpdateLedgerParams[] calldata params, bytes calldata signature)
        external
        onlyOperator
    {
        _delegateCall(
            abi.encodeWithSelector(ILedgerExtension.removeInvalidFrozenShares.selector, vaultId, params, signature),
            _getLedgerImplStorage().extension
        );
    }

    //--------------------------------------CONFIG--------------------------------------------

    /// @notice Set fee rate for strategy providers
    /// @param strategyProviderIds Array of strategy provider IDs
    /// @param feeRates Array of fee rates
    function setFeeRate(bytes32[] calldata strategyProviderIds, uint256[] calldata feeRates) external onlyOwner {
        if (strategyProviderIds.length != feeRates.length) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            feeRateOfFund[strategyProviderIds[i]] = feeRates[i];
        }
        //emit event
        emit FeeRateSet(strategyProviderIds, feeRates);
    }

    /// @notice Set cross chain manager address
    /// @param _crossChainManager Address of cross chain manager
    function setCrossChainManager(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;

        //emit event
        emit CrossChainManagerSet(_crossChainManager);
    }

    /// @notice Set allowed strategy provider
    /// @param vaultId Vault ID
    /// @param vault Vault address
    /// @param strategyProvider Strategy provider address
    /// @param brokerHash Broker hash
    /// @param strategyProviderId Strategy provider ID
    /// @param knob Boolean flag
    function setAllowedStrategyProvider(
        bytes32 vaultId,
        address vault,
        address strategyProvider,
        bytes32 brokerHash,
        bytes32 strategyProviderId,
        bool knob
    ) external onlyOwner {
        if (!VaultUtils.validateSPId(vault, strategyProvider, brokerHash, strategyProviderId)) {
            revert InvalidStrategyProviderId();
        }

        emit AllowedStrategyProviderSet(vaultId, vault, strategyProvider, brokerHash, strategyProviderId, knob);
    }

    /// @notice Set operator manager address
    /// @param _operator Operator address
    function setOperatorManager(address _operator) public onlyOwner {
        operator = _operator;

        //emit event
        emit OperatorManagerSet(_operator);
    }

    /// @notice Set engine address
    /// @param _engine Engine address
    function setEngine(address _engine) public onlyOwner {
        engine = _engine;

        //emit event
        emit EngineSet(_engine);
    }

    /// @notice Set token decimal
    /// @param tokenHash Token hash
    /// @param decimal Token decimal
    function setDecimal(bytes32 tokenHash, uint256 decimal) external onlyOwner {
        tokenDecimal[tokenHash] = decimal;

        //emit event
        emit DecimalSet(tokenHash, decimal);
    }

    /// @notice Set vault broker
    /// @param _vaultId Vault ID
    /// @param _brokerId Broker ID
    function setVaultBroker(bytes32 _vaultId, bytes32 _brokerId) external onlyOwner {
        vaultBroker[_vaultId] = _brokerId;

        //emit event
        emit VaultBrokerSet(_vaultId, _brokerId);
    }

    function setCore(address _core) external onlyOwner {
        _getLedgerImplStorage().core = _core;

        emit CoreSet(_core);
    }

    function setExtension(address _extension) external onlyOwner {
        _getLedgerImplStorage().extension = _extension;

        emit ExtensionSet(_extension);
    }

    function setProtocolVault(address _vault) external onlyOwner {
        protocolVault = _vault;

        emit ProtocolVaultSet(_vault);
    }

    function setVault(bytes32 vaultId, address _vault) external onlyOwner {
        idToVault[vaultId] = _vault;

        emit VaultSet(vaultId, _vault);
    }

    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    /// @notice Check main and strategy fund states
    /// @param periodId Period ID
    /// @param strategyProviderIds Array of strategy provider IDs
    /// @return pendingMainShares The pending main shares
    /// @return pendingStrategyFundStates Array of strategy fund states
    function checkMainAndStrategyFund(uint256 periodId, bytes32 vaultId, bytes32[] calldata strategyProviderIds)
        external
        view
        returns (uint256, StrategyFundState[] memory)
    {
        _check(periodId, vaultId);
        StrategyFundState[] memory pendingStrategyFundStates = new StrategyFundState[](strategyProviderIds.length);

        for (uint256 i = 0; i < strategyProviderIds.length; i++) {
            PendingState storage pendingState =
            _getStrategyFundToken(vaultId, strategyProviderIds[i], USDC_HASH).pendingState;

            uint256 hwm = _calculateHWM(vaultId, strategyProviderIds[i]);
            pendingStrategyFundStates[i] = StrategyFundState({
                strategyProviderId: strategyProviderIds[i],
                totalShares: pendingState.pendingTotalShares,
                totalAssets: pendingState.pendingTotalAssets,
                mainShares: pendingState.pendingMainShares,
                strategyProviderShares: pendingState.pendingStrategyProviderShares,
                hwm: hwm
            });
        }

        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        return (vaultStorage.pendingMainShares, pendingStrategyFundStates);
    }

    /// @notice Check LP account states
    /// @param periodId Period ID
    /// @param accountIds Array of account IDs
    /// @return Array of account states
    function checkLP(uint256 periodId, bytes32 vaultId, bytes32[] calldata accountIds)
        external
        view
        returns (AccountState[] memory)
    {
        _check(periodId, vaultId);
        AccountState[] memory pendingAccountStates = new AccountState[](accountIds.length);
        for (uint256 i = 0; i < accountIds.length; i++) {
            AccountToken storage accountToken = _getAccountToken(vaultId, accountIds[i], USDC_HASH);
            pendingAccountStates[i] = AccountState({accountId: accountIds[i], shares: accountToken.pendingShares});
        }
        return pendingAccountStates;
    }

    /// @notice Convert assets to shares
    /// @param amount Amount of assets
    /// @param _totalAssets Total assets
    /// @param _totalShares Total shares
    /// @return Number of shares
    function convertToShares(uint256 amount, uint256 _totalAssets, uint256 _totalShares)
        external
        pure
        returns (uint256)
    {
        return LedgerUtils._convertToShares(amount, _totalAssets, _totalShares, Math.Rounding.Floor);
    }

    /// @notice Convert shares to assets
    /// @param shares Number of shares
    /// @param _totalAssets Total assets
    /// @param _totalShares Total shares
    /// @return Amount of assets
    function convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _totalShares)
        external
        pure
        returns (uint256)
    {
        return LedgerUtils._convertToAssets(shares, _totalAssets, _totalShares, Math.Rounding.Floor);
    }

    /// @notice Get strategy fund token information
    /// @param spId Strategy provider ID
    /// @return Strategy fund token
    function getStrategyFund(bytes32 vaultId, bytes32 spId) external view virtual returns (StrategyFundToken memory) {
        return _getStrategyFundToken(vaultId, spId, USDC_HASH);
    }

    /// @notice Get account token info by vault and account
    /// @param vaultId vault id
    /// @param accountId account id
    /// @return AccountToken account token information
    function getAccountToken(bytes32 vaultId, bytes32 accountId) external view virtual returns (AccountToken memory) {
        return _getAccountToken(vaultId, accountId, USDC_HASH);
    }

    function getImpl() external view returns (address core, address extension) {
        ImplStorage storage implStorage = _getLedgerImplStorage();
        return (implStorage.core, implStorage.extension);
    }

    function getLPAssets(bytes32 vaultId, address account) external view virtual returns (uint256) {
        bytes32 broker = vaultBroker[vaultId];
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        bytes32 accountId = VaultUtils.getAccountId(account, broker);
        AccountToken storage accountToken = _getAccountToken(vaultId, accountId, USDC_HASH);
        return LedgerUtils._convertToAssets(
            accountToken.shares, vaultState.mainAssetsAfterFee, vaultState.mainShares, Math.Rounding.Floor
        );
    }

    function getSPAssets(bytes32 vaultId, bytes32 spId) external view virtual returns (uint256) {
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(vaultId, spId, USDC_HASH);
        return LedgerUtils._convertToAssets(
            strategyFundToken.strategyProviderShares,
            strategyFundToken.fundAssetsAfterFee,
            strategyFundToken.totalShares,
            Math.Rounding.Floor
        );
    }

    function convertLPAssetsToShares(bytes32 vaultId, uint256 amount) external view virtual returns (uint256) {
        VaultStateStorage storage vaultState = _getVaultStorage(vaultId);
        return
            LedgerUtils._convertToShares(
                amount, vaultState.mainAssetsAfterFee, vaultState.mainShares, Math.Rounding.Floor
            );
    }

    function convertSPSharesToAssets(bytes32 vaultId, bytes32 spId, uint256 amount)
        external
        view
        virtual
        returns (uint256)
    {
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(vaultId, spId, USDC_HASH);
        return LedgerUtils._convertToAssets(
            amount, strategyFundToken.fundAssetsAfterFee, strategyFundToken.totalShares, Math.Rounding.Floor
        );
    }

    /*=========================================================================================
    *                                       INTERNAL
    *=========================================================================================*/

    /// @notice Delegate call to implementation contracts with enhanced error forwarding
    /// @param data Encoded function call data
    /// @param impl Implementation contract address
    function _delegateCall(bytes memory data, address impl) internal {
        if (impl == address(0)) {
            revert LedgerExtensionsNotSet();
        }
        (bool success, bytes memory result) = impl.delegatecall(data);
        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(32, result), mload(result))
                }
            } else {
                revert DelegatecallFailed();
            }
        }
    }

    function _check(uint256 periodId, bytes32 vaultId) internal view {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        if (periodId != vaultStorage.latestPeriodId) {
            revert InvalidPeriodId();
        }
    }

    /// @notice Calculate high water mark for strategy fund
    /// @param strategyProviderId Strategy provider ID
    /// @return High water mark value
    function _calculateHWM(bytes32 vaultId, bytes32 strategyProviderId) internal view returns (uint256) {
        StrategyFundToken storage strategyFundToken = _getStrategyFundToken(vaultId, strategyProviderId, USDC_HASH);

        uint256 hwm = strategyFundToken.hwm;
        uint256 totalShares = strategyFundToken.totalShares;
        uint256 decimal = USDC_DECIMAL;
        if (totalShares == 0) {
            return 10 ** decimal;
        }

        uint256 sharePriceAfterFee = strategyFundToken.fundAssetsAfterFee * 10 ** decimal / totalShares;
        uint256 pendingTotalShares = strategyFundToken.pendingState.pendingTotalShares;
        uint256 newIssueShares = (pendingTotalShares > totalShares) ? pendingTotalShares - totalShares : 0;

        uint256 numerator = (totalShares * Math.max(hwm, sharePriceAfterFee)) + (newIssueShares * sharePriceAfterFee);
        uint256 denominator = totalShares + newIssueShares;

        return numerator / denominator;
    }
}
