// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccountToken, StrategyFundToken, ClaimInfo} from "../lib/types/LedgerStruct.sol";
import {USDC_HASH, VAULT_STORAGE_LOCATION, PROTOCOL_VAULT_ID, ORDERLY_BROKER} from "../lib/types/Constants.sol";

/// @title Ledger Storage
/// @notice This contract contains all storage variables for ProtocolVaultLedger
/// @dev This contract should be inherited by both main contract and extensions contract
abstract contract LedgerBase {
    using Math for uint256;

    uint256 public pendingMainShares;
    uint256 public pendingLpDepositAssets;
    uint256 public pendingLpWithdrawAssets;

    uint256 public mainShares;
    uint256 public mainAssetsAfterFee;
    // @dev the latest period id that contract handle
    uint256 public latestPeriodId;

    /// @dev address of cross chain manager
    address public crossChainManager;
    /// @dev address of interact with ledger
    address public operator;
    /// @dev address of upload data to contract
    address public engine;

    /// @dev Token Hash to token decimal
    mapping(bytes32 => uint256) tokenDecimal;
    /// @dev fee rate of each strategy fund by sp id
    mapping(bytes32 => uint256) public feeRateOfFund;
    /// @dev strategy fund token information by strategy provider id and token hash
    mapping(bytes32 spId => mapping(bytes32 tokenHash => StrategyFundToken)) public strategyFundTokenInfo;
    /// @dev account token information by account id and token hash
    mapping(bytes32 accountId => mapping(bytes32 tokenHash => AccountToken)) public accountTokenInfo;
    /// @dev requestId to User Claim information
    mapping(bytes32 requestId => ClaimInfo) public userClaimInfo;
    /// @dev Determines whether the operation corresponding to the requestId is executed
    mapping(bytes32 requestId => bool) public isOpHandled;
    /// @dev Determines whether the user claim is handled
    mapping(bytes32 requestId => bool) public isUserClaimHandled;
    /// @dev Determines whether the assets has been uploaded in a period. Only can be called once in a period.
    mapping(uint256 periodId => bool) public isUpdateStrategyFundAssets;
    /// @dev Determines whether the assets has been allocated in a period.
    mapping(bytes32 periodId => bool) public isAllocatedToFunds;
    /// @dev Determines whether the assets has been distributed in a period. Only can be called once in a period.
    mapping(uint256 periodId => bool) public isAssetDistributed;
    /// @dev Determines whether the dex request has been handled
    mapping(uint256 periodId => bool) public isDexRequestHandled;
    /// @dev vault id to sv broker hash
    mapping(bytes32 vaultId => bytes32 brokerHash) public vaultBroker;

    address public protocolVault;
    mapping(bytes32 vaultId => address vault) public idToVault;

    /// @custom:storage-location erc7201:orderly.vault.state
    struct VaultStateStorage {
        uint256 pendingMainShares;
        uint256 pendingLpDepositAssets;
        uint256 pendingLpWithdrawAssets;
        uint256 mainShares;
        uint256 mainAssetsAfterFee;
        uint256 latestPeriodId;
        address crossChainManager; //unused, to keep slot same
        address operator; //unused, to keep slot same
        address engine; //unused, to keep slot same
        mapping(bytes32 => uint256) tokenDecimal; //unused, to keep slot same
        mapping(bytes32 => uint256) feeRateOfFund; //unused, to keep slot same
        mapping(bytes32 spId => mapping(bytes32 tokenHash => StrategyFundToken)) strategyFundTokenInfo;
        mapping(bytes32 accountId => mapping(bytes32 tokenHash => AccountToken)) accountTokenInfo;
        mapping(bytes32 requestId => ClaimInfo) userClaimInfo;
        mapping(bytes32 requestId => bool) isOpHandled;
        mapping(bytes32 requestId => bool) isUserClaimHandled;
        mapping(uint256 periodId => bool) isUpdateStrategyFundAssets;
        mapping(uint256 periodId => bool) isAllocatedToFunds;
        mapping(uint256 periodId => bool) isAssetDistributed;
        mapping(uint256 periodId => bool) isDexRequestHandled;
    }

    /// @notice Get vault state
    function _getVaultStorage(bytes32 vaultId) internal view returns (VaultStateStorage storage $) {
        bytes32 location = vaultId == keccak256(abi.encode(protocolVault, ORDERLY_BROKER))
            ? bytes32(0)
            : keccak256(abi.encode(VAULT_STORAGE_LOCATION, vaultId));
        assembly {
            $.slot := location
        }
    }
    /// @notice Get strategy fund token by vault

    function _getStrategyFundToken(bytes32 vaultId, bytes32 spId, bytes32 tokenHash)
        internal
        view
        returns (StrategyFundToken storage)
    {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        return vaultStorage.strategyFundTokenInfo[spId][tokenHash];
    }

    /// @notice Get account token by vault
    function _getAccountToken(bytes32 vaultId, bytes32 accountId, bytes32 tokenHash)
        internal
        view
        returns (AccountToken storage)
    {
        VaultStateStorage storage vaultStorage = _getVaultStorage(vaultId);
        return vaultStorage.accountTokenInfo[accountId][tokenHash];
    }
}
