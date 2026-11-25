# Roadmap and monetization

## Who uses it
Teams that let AI agents pay: procurement and accounts-payable bots, shopping agents, API-credit top-up bots, payroll helpers. Today they either give the agent a full-balance key or build their own limits off chain.

## Path
1. Now (testnet): per-agent mandate, allowlist, 24h limit, approval queue, merchant-signed invoices, revoke. 25 tests.
2. Next: a merchant registry (verified payee names, shared across owners), per-merchant caps, and approvals by a multisig or a second wallet instead of one owner key.
3. Mainnet on QDay (the organizers plan a February mainnet): audit, gas-sponsored agent calls through the kit's relayer, SDK (TypeScript) so an agent framework adds the guard in a few lines.
4. Later: webhooks and email/chat alerts when a payment is pending or blocked, spend reports, stablecoins beyond tUSD8.

## How it could make money (without touching user funds)
- Hosted dashboard and alerts for teams: a monthly plan per owner.
- Merchant verification: merchants pay a small fee to be a verified, signing payee (Confirmation of Payee).
- Optional fee on a managed relayer (gas sponsorship). The contract itself stays free, with no admin and no custody.

## Risks and limits
Testnet only, not audited. A compromised owner key or a malicious allowlisted merchant is outside what the contract can stop. A signed invoice proves the merchant issued it, not that the goods are good.
