# Architecture

## Problem
An AI agent that pays invoices reads untrusted text. A poisoned invoice can redirect a payment. If the only guard is a prompt, a fooled model moves real money.

## Design
The limit lives in the contract, not in the model.

```
Owner wallet --(approve tUSD8 once)--> AgentPayGuard <--pay()-- Agent wallet
     |  setMandate / setMerchant / revoke        |
     |                                           +--transferFrom(owner -> merchant)
     +-- keeps custody of the funds
```

Contract state:
- `mandates[owner][agent]`: budget, spent, perTxCap, expiry, revoked.
- `merchantAllowed[owner][agent][merchant]`.
- `orderPaid[owner][orderId]`.

`pay(owner, merchant, amount, orderId)` is called by the agent. It reverts unless the mandate exists, is not revoked, not expired, the merchant is allowed, amount is within the per-payment cap and the remaining budget, and the order id is unused. Then it moves tUSD8 straight from owner to merchant. Nothing is held by the contract. There is no admin, upgrade path or fee.

## Core workflows
1. Setup: owner approves the guard, sets a mandate, allows merchants.
2. Normal payment: the agent reads an invoice, calls `pay`. Allowed, paid, event `Paid`.
3. Attack: a poisoned invoice makes the agent pay an unlisted address. `MerchantNotAllowed`.
4. Abuse by amount or replay: `OverPerTxCap`, `OverBudget`, `OrderAlreadyPaid`.
5. Kill switch: owner calls `revoke(agent)`. Later calls fail with `Revoked`.

## Technologies
Solidity 0.8.24 (Shanghai EVM), OpenZeppelin v5.1.0, Foundry (13 tests incl. fuzz), Python 3 agent using Foundry `cast`, static dashboard (HTML, JSON-RPC), Aevum testnet (chain 44005), tUSD8 (ERC-20, 6 decimals). Based on Aevum Starter Kit (MIT, PQA Labs).

## Threat model
Protects against: a fooled or malicious agent, prompt injection, replayed invoices, runaway spend. Does not protect against: a compromised owner key, or an allowlisted merchant that is itself malicious.
