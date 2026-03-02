# Exclusive Receive Address

## Overview

To provide a "CEX-like" onboarding experience for a decentralized environment. Users should be able to fund their Orderly Perp Account simply by sending tokens to a unique address.

- Eliminates the need for users to prepare Native Gas, connect wallets, or manually call Approve and Deposit
- Fully supports direct withdrawals from any Centralized Exchange (Binance, OKX, etc.) or on-ramp service (Moonpay, Onramper, etc)

## Scope

### v1 (Current)

- **Deposit Target**: Perp Account only
- **Supported Chain**: Arbitrum
- **Supported Token**: USDC
- **Key Features**:
  - Unique, deterministic receive address per user (based on EOA + Broker ID)
  - Gasless deposit (gas fees deducted from deposit amount)
  - Automated monitoring and execution via Indexer → CeFi → Operator
  - Minimum deposit threshold to cover gas and deployment costs


### Future Expansion

- **Deposit Targets**: Strategy Vaults, Omni Vault, multi-vault support
- **Chains**: All Orderly supported networks (Sol, Base, Optimism, etc.)
- **Tokens**: Multi-token support with DEX aggregator integration (swap any token → USDC)

## Core Flow

1. **Generate Address**: User opens the deposit modal, selects "Send to Address". The system displays the receiver address and deposit info (see Frontend section).
2. **Transfer**: User sends USDC to the displayed address from any wallet or CEX on Arbitrum.
3. **Detection**: Indexer detects USDC transfer to receiver address → notifies CeFi → CeFi creates pending deposit record. Each transfer creates a separate pending record.
4. **Execution**: CeFi notifies Operator → Operator sends transaction to Smart Contract (deploy if needed + deposit atomically). If amount exceeds `user_max_qty`, Operator deposits in batches.
5. **Completion**: Indexer detects deposit success event → notifies CeFi → CeFi updates status to "Completed". User sees updated balance.

## Requirements

### Address Generation

- **Formula**: Deterministic via CREATE2, salt = `f(user_eoa, target_meta)`
  - Perp: `f(user_eoa, broker_id, vault_address, ...)`
  - Conceptual,  actual implementation will follow the technical design
- One unique receiver address per `(user_eoa, target_meta)` combination
- Precomputed on-demand, no on-chain deployment needed to know the address

---

### Frontend

  - **General Information**:
    - The following data is fetched from `GET /v1/client/asset/receiver_address`:
      - Precomputed receiver address (copyable + QR code)
      - Minimum deposit amount
      - Estimated fee
    - Maximum deposit amount: Displayed based on user's per-collateral cap (`user_max_qty` from `GET /v1/public/token`). Note: Users can still deposit more than this cap, but the excess will not be counted as collateral.
    - Destination chain and supported token: For v1, this is fixed to **USDC on Arbitrum**.
    - Estimated completion time: Hardcode to **5 minutes**.
    - Warning message: "Only send **USDC on Arbitrum** to this address. Sending other tokens or using other chains will result in **permanent loss of funds**. No recovery is possible."

  - **Transaction Status Summary**:
    - The deposit modal displays a status summary to inform users of their in-progress and recent deposits. Example messages:
      - "You have N detected transfer(s)" — transfers detected at receiver address, not yet in vault (from `GET /v1/client/asset/receiver_events`)
      - "You have N pending transaction(s)" — deposits being processed by vault (from `/v1/asset/history?side=DEPOSIT`, status: `pending`); links to Deposit History
      - "You have N successful transaction(s)" — deposits completed (from `/v1/asset/history?side=DEPOSIT`, status: `completed`); links to Deposit History
    - Multiple transactions can exist in each state simultaneously; counts reflect all active entries.
    - All three status lines can be displayed at the same time.
    - Completed transactions are only shown if `updated_time` is within the last **15 minutes**. Older completed entries are hidden.

- **Deposit History**:
  - Full deposit history uses the existing `/v1/asset/history` API with `?side=DEPOSIT`

---

### API Requirements

#### GET /v1/client/asset/receiver_address

- **Type**: Private endpoint (requires `orderly-*` headers)
- **Request Parameters**:
  - `chain_id`: Target chain ID
- **Response**: Supported receiver address object
  ```json
  {
    "receiver_address": "0x...",
    "token_address": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    "estimated_fee": 2.5,
    "minimum_deposit": 5.0
  }
  ```

  - `receiver_address`: Precomputed address for this chain/token combination
  - `token_address`: Supported token contract address on the chain
  - `estimated_fee`: Dynamic, based on current gas prices (USDC). Estimate only — actual fee at execution time may differ.
  - `minimum_deposit`: Platform's guaranteed threshold (USDC)


#### GET /v1/client/asset/receiver_events

- **Type**: Private endpoint (requires `orderly-*` headers)
- **Description**: Query detected transfer events at the receiver address that have **not yet been deposited to vault**. Used to display real-time status on the deposit modal. Events with amounts less than the minimum deposit are ignored.
- **Response**: Array of detected events
  ```json
  [
    {
      "token": "USDC",
      "amount": 29.619521,
      "created_time": 1767848705855,
      "updated_time": 1767848724143
    }
  ]
  ```

  - `token`: Token symbol
  - `amount`: Detected deposit amount
  - `created_time`: Record creation timestamp
  - `updated_time`: Record update timestamp


---

### Backend

#### Indexer

- Monitors USDC contract `Transfer` events on Arbitrum to precomputed receiver addresses
- Monitors receiver contract deposit success events

#### CeFi

- Transfer detected → Create deposit history (`Pending`), notify Operator
- Deposit success event → Update status to `Completed`, record actual fee
- Provides APIs (see API Requirements)

#### Operator

- Triggers atomic deploy + deposit via Factory contract
- **Retry**: Automatic retry until success. Idempotent — contract reverts if balance insufficient, preventing double-deposit.

---

### Smart Contract

- Compute deterministic receiver address per `(user_eoa, target_meta)` without deploying (see Address Generation)
- Support atomic operation: deploy receiver (if not yet deployed) + execute deposit in a single transaction
- Execute deposit: deduct fee from specified deposit amount, transfer fee to Operator, deposit remainder to vault
- **Important**: Must remove the existing `global cap` limit currently enforced in production to prevent large deposits from failing.
- Operator controls the deposit logic: every single transfer is treated as an independent event. The injected `depositAmount` must be `>= minimum deposit amount`. If a previous deposit was stuck (because it was `< min deposit`), those funds are treated as dust and strictly ignored during subsequent deposits.
- Only callable by authorized Operator
- Emit event on successful deposit for Indexer to detect
- **Deposit Target (v1)**: [Vault Contract on Arbitrum](https://arbiscan.io/address/0x816f722424B49Cf1275cc86DA9840Fbd5a6167e9#writeProxyContract), function `depositTo(address receiver, uint256 amount)`

---

## Edge Cases & Error Handling

| Scenario                                  | Behavior                                                                       |
|-------------------------------------------|--------------------------------------------------------------------------------|
| **Below-minimum deposit**                 | Funds stuck in receiver contract as dust. Ignored.                             |
| **Wrong token or wrong chain**            | Permanent loss. No recovery. UI warns prominently.                             |
| **Multiple concurrent transfers**         | Each transfer = separate pending record, processed individually (1:1 mapping). |
| **Operator failure**                      | Auto-retry until success.                                                      |

**Platform Guarantee**: Any deposit >= minimum threshold is guaranteed to succeed. The threshold is set conservatively to ensure fee coverage under all gas conditions.

---

## Configurable Parameters

| Parameter           | Description                                                                                        | Enforcement                                                |
|---------------------|----------------------------------------------------------------------------------------------------|------------------------------------------------------------|
| **Minimum Deposit** | Platform's guaranteed success threshold, configurable per chain/token. v1: **5 USDC** on Arbitrum. | Display only — cannot enforce on-chain                     |

---

## Tech Support

- Tech support team to define SOP for handling stuck/failed deposits and request tooling from engineering
- **Minimum capabilities needed**:
  - View deposits stuck in `Pending` state.
  - Alert system for anomalous states (e.g., stuck in `Pending` for > 15 minutes)
  - Observe automatic retry status (all retries are handled automatically by the Operation service)

## Mockup

![deposit-send-to-address.png](assets/deposit-send-to-address-flow-demo.png)

## Reference

![ref-lighter-deposit-modal.png](assets/ref-lighter-deposit-modal.png)
