# Aevum testnet deployment (chain 44005)

## Current: v3 `0x8362aD645e5239eCb11084b9444727C80C7F2b0d`
https://explorer-test.qday.info/address/0x8362aD645e5239eCb11084b9444727C80C7F2b0d
Adds merchant-signed invoices (EIP-712) and the demo with two agents. Includes everything from v2 (approval queue, 24h limit).

Agent 1 (Invoice bot) `0x8C0f9364e8D3ac76b9E9C288b35514bad4f7CC17`: budget 1.0, cap 0.6, signed invoices only.
Agent 2 (Research bot) `0x52f807fFF2c6e36c5EeD506Ca0b8732690cFA274`: budget 0.3, cap 0.1.
Merchant (signs invoices) `0x6a7DF9c8b052Eb890C5B7e39357EA924CaAC07d4`.

| Step | Result | Tx |
|---|---|---|
| approve | ok | `0x367e945570170467919ae790d0caabf704d901af4cbc7d9e519408835629ec75` |
| setMandate agent 1 | ok | `0xcfd2fadfbdf4927942a0f34b9635b69f68894db8440944a14995662036a6292c` |
| setRequireSignedInvoice | ok | `0x1fc36c1cdb81a2c4b30612ffec1b7da5df668699bae5ec5213afadf61503b0e0` |
| setMandate agent 2 | ok | `0xdec51e6858792e282dcd32280e9a3d8b848b9bb50baa178f3de6a03f2df7fd6e` |
| Agent 1 pays signed invoice 0.4 | PAID | `0xddfa342e5ca9f9d8a4181950b9d95f511b0387426fd0b60a302728507a0dbe19` |
| Agent 1 asks 0.6 on a 0.4 signature | REVERTED BadInvoiceSignature | `0x904d5131f8c99589abf5f090db71905276544e91b750a31d47799fad56acd978` |
| Agent 1 plain pay() | REVERTED SignedInvoiceRequired | `0x652d9b831813514975d6e111893a2914f62d026a595569ef579c0a474c3e50b1` |
| Agent 2 pays 0.1 | PAID | `0x95bed2fb9dba842410960944a62ce4a58eff2d88736180084a5b767229682a1f` |
| Agent 2 asks 0.2 | REVERTED OverPerTxCap | `0xcc908e38b0ef41799b9e64f064b6f132d6c7494eaa3dd9a6a8be43d85a6a3843` |

## v2 (superseded): `0x504F305AcdAeF6BecA5d249554B7479261c5544a`
Approval queue + 24h limit demo. Explorer: https://explorer-test.qday.info/address/0x504F305AcdAeF6BecA5d249554B7479261c5544a

Mandate: budget 3 tUSD8, per-payment cap 2, owner approval above 1, 24h limit 2.5, one allowed shop.

| Step | Result | Tx |
|---|---|---|
| approve | ok | `0x214611495b486984f9f809a4c59cdb0a94a74eaf82de812e8f4822b16fab5c99` |
| setMandate | ok | `0xa50c462c749576e7ae5dc6a5dda9b201134dbef3e512773d5e756c1528538e9a` |
| setMerchant | ok | `0xb47a5760c530632217dc778c4b4bacc275d4650d8a3d64eb6cdf699495c45bfe` |
| setApprovalThreshold | ok | `0xc818f2a3599b7f62ad7f8fa411482f3a3630dc910cf277dacd5bd0e67516bcc2` |
| setDailyLimit | ok | `0x515f708b761bf0aee13836bcc1d0a2bb8318009259a5b82021d533fe475608da` |
| Honest invoice 0.8 | PAID | `0xd70628eae44bb3465954c2cf5f0c6410e580f4938b2073bd7af0987723bd800f` |
| Poisoned invoice 2.0 to attacker | REVERTED MerchantNotAllowed | `0xc9803b4c82c9f9cd2f1ca666867f8231ad87a5ba4f2b9b21fbcbcc3ec66abd2b` |
| Honest invoice 1.5 (above threshold) | PENDING, no money moved | `0xa3c02970cffc67cb092358fba5ad44d0a39d1129d37f6b9c704c8cd64e28d1da` |
| Owner approves 1.5 | PAID | `0x66917e68233bb6f796e90e51c118fdbc9e849453ed12c2ac2663befe9520f111` |
| Honest invoice 0.5 | REVERTED OverDailyLimit | `0x9b73ee9feb13a2447bc58eb8a77a35af560ca24224d9f2a12dbe3c22f68099c3` |
| Owner revokes | ok | `0x020a1875b1024454454bdd16baabcfff6ed09897d3350d0a867c23e15cbc47bd` |

Final balances: shop 3.5 tUSD8 (incl. 1.2 from the v1 run), attacker 0.

## v1 (superseded): `0xd594B08D083A0f5661E9e49a8a99a7937f80fBa0`
Same checks without the approval queue and daily limit. Its demo (honest 1.2 paid, poisoned 2.5 reverted, revoke, post-revoke revert) is on the explorer.

Owner `0x811B9707A74e43E6bF22dcCaa9dfFB3286492402`, agent `0x8C0f9364e8D3ac76b9E9C288b35514bad4f7CC17`, shop `0x3BEcCb75b1F6f0066FAf1641d4dE43FEa8f03d1B`, attacker `0xEc78a54eB34f35a610382617929876d3e2Bdd1c4`. Testnet wallets with no value.
