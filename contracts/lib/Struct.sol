// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
enum VaultType {
    PROTOCOL,
    USER
}

enum VaultState {
    OPEN,
    SHUTDOWN,
    CLOSED
}

enum PayloadType {
    DEPOSIT,
    WITHDRAW,
    TRANSFER_TO_ORDERLY,
    TRANSFER_FROM_ORDERLY_TO_STRATEGY_VAULT
}

struct Account {
    address userAddress;
    uint256 balance;
    uint256 unAllocatedBalance;
    uint256 shareAmount;
    
}

struct StrategyVaultCCMessage {
    /// @dev the source chain id, the sender can omit this field
    uint256 dstChainId;
    /// @dev payloadType is the type of the payload
    PayloadType payloadType;
    /// @dev payload is the data to be sent
    bytes payload;
}
struct UploadUserShare {
    bytes32 accountId;
    uint256 depositAmount;
}
/*======================================================================
 *   Deposit
 *======================================================================*/

struct DepositData {
    VaultType vaultType;
    uint256 amount;
    uint64 depositNonce; // deposit nonce
    address token;
    address receiver;
    address strategyProvider; //optional for protocol vault
    address vault;
    bytes32 vaultId;
    bytes32 accountId;
    bytes32 strategyProviderId;
    bytes32 brokerHash;
}

/*======================================================================
 *   Withdraw
 *======================================================================*/

struct WithdrawData {
    VaultType vaultType;
    uint256 withdrawNonce; // withdraw nonce
    uint256 amount;
    uint256 amountUnderStrategyProvider;
    uint256 pendingAmount;
    address vault;
    address sender;
    address receiver;
    address strategy;
    address strategyProvider;
    bytes32 brokerHash;
    bytes signatureOfStrategyProvider;
    bytes signatureOfUser;
}

/*======================================================================
 *   Strategy Execution
 *======================================================================*/
struct StrategyExecution {
    VaultType vaultType;
    uint256 amount;
    address vault;
    address strategy;
    address strategyProvider;
    bytes32 brokerID;
    bytes32 vaultId;
    bytes32 tokenHash;
    bytes signature;
}

/*======================================================================
 *   Strategy Vault Ledger
 *======================================================================*/
struct StrategyVault {
    VaultType vaultType;
    uint256 balance;
    uint256 sharePrice;
    address[] strategyProviders;
}

struct StrategyProvider {
    uint256 balance;
    uint256 unAllocatedBalance;
    bytes32[] strategies;
    mapping(address => uint256) strategyBalance;
}
