// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Address.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {IVaultCrossChainManager} from "./interfaces/IVaultCrossChainManager.sol";
import {IProtocolVault} from "./interfaces/IProtocolVault.sol";
import {VaultDepositFE, IDexVault} from "./interfaces/IDexVault.sol";
import {
    VaultType,
    VaultState,
    RoleType,
    ClaimParams,
    DepositParams,
    WithdrawParams,
    OperationData,
    UserClaimedInfo
} from "./lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "./lib/types/CrossChainStruct.sol";
import {ClaimInfo} from "./lib/types/LedgerStruct.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

/// @title ProtocolVault for user to deposit and withdraw assets
contract ProtocolVault is Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable, IProtocolVault {
    using Address for address payable;

    /// @dev keccak256(abi.encodePacked(broker string))
    bytes32 constant ORDERLY_BROKER = 0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b;
    /// @dev keccak256(abi.encodePacked("USDC"))
    bytes32 constant USDC_HASH = 0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa;
    uint256 constant LEDGER_CHAIN_ID = 291;

    VaultState public vaultState;
    address public dexVault;
    address public crossChainManager;

    /// @dev ledger eid for lz
    uint32 public ledgerEid;
    /// @dev Incremental nonce for user deposit and withdraw operation,used for requestId on ledger
    uint256 public chainNonce;
    /// @dev Minimum deposit amount for LP
    uint256 public minDepositForLp;
    /// @dev Minimum deposit amount for SP
    uint256 public minDepositForSp;

    /// @dev Admin address => isAllowed
    mapping(address => bool) public isAllowedAdmin;
    /// @dev allowed strategy provider
    mapping(bytes32 => bool) public isAllowedStrategyProvider;
    /// @dev User Id => TokenHash => UserClaimedInfo
    mapping(bytes32 => mapping(bytes32 => UserClaimedInfo)) public userClaimedById;
    /// @dev Token => isAllowed
    mapping(address => bool) public isAllowedToken;
    /// @dev Broker Id => isAllowed
    mapping(bytes32 => bool) public isAllowedBroker;
    /// @dev allowed strategy
    mapping(address => bool) public isAllowedStrategy;
    /// @dev Token hash  => Token address
    mapping(bytes32 => address) public tokenHashToAddress;
    /// @dev whitelist for LP Deposit
    bool public lpWhitelistEnabled;
    uint256 public lpWhitelistEndTime;
    mapping(address => bool) public lpWhitelist;

    //receive native token
    receive() external payable {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Require only cross chain manager can call
    modifier onlyVaultCrossChainManager() {
        if (msg.sender != crossChainManager) {
            revert InvalidCrossChainManager();
        }
        _;
    }

    /// @notice Require only dex vault can call
    modifier allowedStrategy() {
        if (!isAllowedStrategy[msg.sender]) {
            revert InvalidStrategy();
        }
        _;
    }

    /// @notice Require only admin can call
    modifier onlyOwnerOrAdmin() {
        if (!isAllowedAdmin[msg.sender] && msg.sender != owner()) {
            revert InvalidOwnerOrAdmin();
        }
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(
        address _dexVault,
        address owner,
        address token,
        uint256 _minDepositForLp,
        uint256 _minDepositForSp
    ) external initializer {
        __Ownable2Step_init();
        __Ownable_init(owner);

        __UUPSUpgradeable_init();

        __Pausable_init();

        dexVault = _dexVault;

        isAllowedBroker[ORDERLY_BROKER] = true;
        isAllowedToken[token] = true;
        isAllowedStrategy[_dexVault] = true;
        tokenHashToAddress[USDC_HASH] = token;
        ledgerEid = 30213;

        minDepositForLp = _minDepositForLp;
        minDepositForSp = _minDepositForSp;
    }
    /*=========================================================================================
    *                                       EXTERNAL
    *=========================================================================================*/

    //--------------------------------------FROM USER-----------------------------------------
    /**
     * @notice Allows a user to deposit funds into the vault. This contract now refunds surplus native
     *         tokens directly to msg.sender. Contracts unable to receive native tokens may encounter
     *         issues during deposit.
     * @dev This function can only be called when the contract is not paused.
     * @param depositParams The parameters required for the deposit, encapsulated in a struct.
     */
    function deposit(DepositParams memory depositParams) external payable whenNotPaused {
        bytes32 brokerHash = depositParams.brokerHash;
        address token = depositParams.token;
        uint256 amount = depositParams.amount;
        PayloadType payloadType = depositParams.payloadType;

        _validateDeposit(payloadType, token, depositParams.receiver, amount, brokerHash);
        //construct cross chain message
        OperationData memory data = _getOperationData(payloadType, depositParams.receiver, amount, token, brokerHash);
        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: block.chainid,
            dstChainId: LEDGER_CHAIN_ID,
            payload: abi.encode(data)
        });

        chainNonce++;

        //transfer token to this contract
        SafeTransferLib.safeTransferFrom(ERC20(token), msg.sender, address(this), amount);

        //cross-chain
        IVaultCrossChainManager(crossChainManager).sendMessageWithValueAndRefund{value: msg.value}(message, msg.sender);

        emit OperationExecuted(payloadType, data);
    }

    /**
     * @notice Allows a user to request withdraw funds from the vault. This contract now refunds surplus
     *         native tokens directly to msg.sender. Contracts unable to receive native tokens may encounter
     *         issues during withdraw.
     * @dev This function can only be called when the contract is not paused.
     * @param withdrawParams The parameters required for the withdraw, encapsulated in a struct.
     */
    function withdraw(WithdrawParams memory withdrawParams) external payable whenNotPaused {
        bytes32 brokerHash = withdrawParams.brokerHash;
        address token = withdrawParams.token;
        uint256 amount = withdrawParams.amount;
        PayloadType payloadType = withdrawParams.payloadType;

        _validateWithdraw(payloadType, token, msg.sender, amount, brokerHash);

        //construct OperationData
        OperationData memory data = _getOperationData(payloadType, msg.sender, amount, token, brokerHash);

        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: block.chainid,
            dstChainId: LEDGER_CHAIN_ID,
            payload: abi.encode(data)
        });

        chainNonce++;

        //cross-chain message
        IVaultCrossChainManager(crossChainManager).sendMessageWithValueAndRefund{value: msg.value}(message, msg.sender);

        emit OperationExecuted(payloadType, data);
    }

    function claim(ClaimParams memory claimParams) external whenNotPaused {
        bytes32 id;
        bytes32 brokerHash = claimParams.brokerHash;

        if (claimParams.roleType == RoleType.LP) {
            id = _getAccountId(msg.sender, brokerHash);
        } else if (claimParams.roleType == RoleType.SP) {
            id = _getStrategyProviderId(msg.sender, brokerHash);
        } else {
            revert InvalidRoleType();
        }

        //check
        if (claimParams.token != tokenHashToAddress[USDC_HASH]) {
            revert InvalidClaimToken(claimParams.token);
        }
        uint256 amount = userClaimedById[id][USDC_HASH].unClaimedAssets;
        if (amount == 0) {
            revert NotEnoughUnclaimedAssets(amount);
        }

        //effect
        userClaimedById[id][USDC_HASH].unClaimedAssets = 0;
        bytes32[] memory requestIds = userClaimedById[id][USDC_HASH].requestIds;
        delete userClaimedById[id][USDC_HASH].requestIds;

        //transfer to user
        SafeTransferLib.safeTransfer(ERC20(claimParams.token), msg.sender, amount);

        emit UserClaimed(claimParams.roleType, id, amount, requestIds);
    }

    //--------------------------------------FROM Strategy-----------------------------------------
    function depositFromStrategy(uint256 periodId, address token, uint256 amount) external allowedStrategy {
        bytes32 vaultId = _getVaultId(ORDERLY_BROKER);

        //transfer token to this contract
        SafeTransferLib.safeTransferFrom(ERC20(token), msg.sender, address(this), amount);

        emit DepositFromStrategy(periodId, vaultId, msg.sender, amount);
    }

    //--------------------------------------FROM LEDGER-----------------------------------------
    function depositToStrategy(uint256 periodId, address receiver, uint256 amount)
        external
        onlyVaultCrossChainManager
    {
        bytes32 vaultId = _getVaultId(ORDERLY_BROKER);
        VaultDepositFE memory depositData = VaultDepositFE({
            accountId: vaultId,
            brokerHash: ORDERLY_BROKER,
            tokenHash: USDC_HASH,
            tokenAmount: uint128(amount)
        });

        //call dex
        address token = tokenHashToAddress[USDC_HASH];
        SafeTransferLib.safeApprove(ERC20(token), dexVault, amount);

        uint256 fee =
            IDexVault(dexVault).depositFeeEnabled() ? IDexVault(dexVault).getDepositFee(address(this), depositData) : 0;
        IDexVault(dexVault).depositTo{value: fee}(address(this), depositData);

        uint64 dexNonce = IDexVault(dexVault).depositId();
        emit DepositToStrategy(periodId, vaultId, receiver, amount, dexNonce);
    }

    function updateUnClaimed(uint256 periodId, ClaimInfo[] memory userClaimInfos)
        external
        onlyVaultCrossChainManager
    {
        for (uint256 i = 0; i < userClaimInfos.length; i++) {
            bytes32 userId = userClaimInfos[i].accountId == bytes32(0)
                ? userClaimInfos[i].strategyProviderId
                : userClaimInfos[i].accountId;
            userClaimedById[userId][USDC_HASH].unClaimedAssets += userClaimInfos[i].assets;
            userClaimedById[userId][USDC_HASH].requestIds.push(userClaimInfos[i].requestId);
        }

        bytes32 vaultId = _getVaultId(ORDERLY_BROKER);
        emit UnClaimedUpdated(periodId, vaultId, userClaimInfos);
    }

    /// @notice withdraw native token
    /// @param to the receiver address
    /// @param amount the amount to withdraw
    function withdrawNativeToken(address payable to, uint256 amount) external onlyOwner {
        to.sendValue(amount);
    }

    //--------------------------------------CONFIG--------------------------------------------
    function setOrderlyDexVault(address _dexVault) external onlyOwner {
        dexVault = _dexVault;
    }

    function setCrossChainManager(address _crossChainManager) external onlyOwner {
        crossChainManager = _crossChainManager;
    }

    function setMinDepositForLP(uint256 amount) external onlyOwner {
        minDepositForLp = amount;
    }

    function setMinDepositForSP(uint256 amount) external onlyOwner {
        minDepositForSp = amount;
    }

    function setAdmin(address admin, bool isAllowed) external onlyOwner {
        isAllowedAdmin[admin] = isAllowed;

        emit AdminSet(admin);
    }

    function setLedgerEid(uint32 eid) external onlyOwner {
        ledgerEid = eid;
    }

    function setAllowedToken(address token, bool isAllowed) external onlyOwner {
        isAllowedToken[token] = isAllowed;

        emit AllowedTokenSet(token, isAllowed);
    }

    function setAllowedBroker(bytes32 brokerHash, bool isAllowed) external onlyOwner {
        isAllowedBroker[brokerHash] = isAllowed;

        emit AllowedBrokerSet(brokerHash, isAllowed);
    }

    function setAllowedStrategy(address strategy, bool isAllowed) external onlyOwner {
        isAllowedStrategy[strategy] = isAllowed;

        emit AllowedStrategySet(strategy, isAllowed);
    }

    function setTokenHashToAddress(address token, bytes32 hash) external onlyOwner {
        tokenHashToAddress[hash] = token;
    }

    function emergencyPause() public whenNotPaused onlyOwnerOrAdmin {
        _pause();
    }

    function emergencyUnpause() public whenPaused onlyOwner {
        _unpause();
    }

    function setVaultState(VaultState _vaultState) public onlyOwner {
        vaultState = _vaultState;

        emit VaultStateChanged(_vaultState);
    }

    function setAllowedStrategyProvider(bytes32 spId, bool knob) external onlyOwner {
        isAllowedStrategyProvider[spId] = knob;
    }

    function setLpWhitelistConfig(bool _enabled, uint256 _endTime) external onlyOwner {
        require(_endTime > block.timestamp || !_enabled, "Invalid end time");
        lpWhitelistEnabled = _enabled;
        lpWhitelistEndTime = _endTime;
    }

    function updateLpWhitelist(address[] calldata _users, bool _isWhitelisted) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            lpWhitelist[_users[i]] = _isWhitelisted;
        }
    }
    /*=========================================================================================
    *                                       VIEW
    *=========================================================================================*/

    function getUserClaimedInfo(bytes32 userId) public view returns (UserClaimedInfo memory) {
        return userClaimedById[userId][USDC_HASH];
    }

    function quoteOperation(PayloadType payloadType, address receiver, uint256 amount) public view returns (uint256) {
        OperationData memory data = _getOperationData(payloadType, receiver, amount, address(0), ORDERLY_BROKER);
        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: payloadType,
            srcChainId: block.chainid,
            dstChainId: LEDGER_CHAIN_ID,
            payload: abi.encode(data)
        });
        bytes memory lzMessage = abi.encode(message);

        (uint256 nativeFee,) =
            IVaultCrossChainManager(crossChainManager).quote(ledgerEid, lzMessage, payloadType, false);
        return nativeFee;
    }
    /*========================================================`=================================
    *                                       INTERNAL
    *=========================================================================================*/

    function _validateDeposit(
        PayloadType payloadType,
        address token,
        address receiver,
        uint256 amount,
        bytes32 brokerHash
    ) internal view {
        _validateBasic(payloadType, token, brokerHash, receiver, amount);

        if (payloadType != PayloadType.LP_DEPOSIT && payloadType != PayloadType.SP_DEPOSIT) {
            revert InvalidDepositType(payloadType);
        }

        if (payloadType == PayloadType.LP_DEPOSIT) {
            if (lpWhitelistEnabled && block.timestamp <= lpWhitelistEndTime) {
                require(lpWhitelist[receiver], "Not in whitelist");
            }
            require(amount >= minDepositForLp, "Invalid deposit amount");
        } else if (payloadType == PayloadType.SP_DEPOSIT) {
            require(amount >= minDepositForSp, "Invalid deposit amount");
        }
    }

    function _validateWithdraw(
        PayloadType payloadType,
        address token,
        address receiver,
        uint256 amount,
        bytes32 brokerHash
    ) internal view {
        _validateBasic(payloadType, token, brokerHash, receiver, amount);

        if (payloadType != PayloadType.LP_WITHDRAW && payloadType != PayloadType.SP_WITHDRAW) {
            revert InvalidWithdrawType(payloadType);
        }
    }

    function _validateBasic(
        PayloadType payloadType,
        address token,
        bytes32 brokerHash,
        address receiver,
        uint256 amount
    ) internal view {
        bytes32 strategyProviderId = _getStrategyProviderId(receiver, brokerHash);
        if (
            (payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.SP_WITHDRAW)
                && !isAllowedStrategyProvider[strategyProviderId]
        ) {
            revert NotAllowedStrategyProvider(strategyProviderId);
        }
        if (amount == 0) revert ZeroAmount();
        if (vaultState == VaultState.CLOSED) revert VaultClosed();
        if (!isAllowedToken[token]) revert TokenNotAllowed(token);
        if (!isAllowedBroker[brokerHash]) revert BrokerNotAllowed(brokerHash);
    }

    function _getOperationData(PayloadType payloadType, address receiver, uint256 amount, address, bytes32 brokerHash)
        internal
        view
        returns (OperationData memory)
    {
        bytes32 accountId;
        bytes32 strategyProviderId;

        if (payloadType == PayloadType.LP_DEPOSIT || payloadType == PayloadType.LP_WITHDRAW) {
            accountId = _getAccountId(receiver, brokerHash);
        } else if (payloadType == PayloadType.SP_DEPOSIT || payloadType == PayloadType.SP_WITHDRAW) {
            strategyProviderId = _getStrategyProviderId(receiver, brokerHash);
        } else {
            revert InvalidPayloadType(payloadType);
        }

        //construct OperationData cross chain message
        OperationData memory operationData = OperationData({
            vaultType: VaultType.PROTOCOL,
            sender: msg.sender,
            receiver: receiver,
            chainNonce: chainNonce,
            amount: amount,
            vaultId: _getVaultId(brokerHash),
            accountId: accountId,
            strategyProviderId: strategyProviderId,
            tokenHash: USDC_HASH,
            brokerHash: brokerHash
        });

        return operationData;
    }

    function _getAccountId(address account, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, brokerHash));
    }

    function _getStrategyProviderId(address strategyProvider, bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encode(address(this), strategyProvider, brokerHash));
    }

    function _getVaultId(bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encode(address(this), brokerHash));
    }
}
