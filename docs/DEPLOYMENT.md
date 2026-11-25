# Aevum testnet deployment (chain 44005)

Current contract (v2, with approval queue and 24h limit): `0x504F305AcdAeF6BecA5d249554B7479261c5544a`
https://explorer-test.qday.info/address/0x504F305AcdAeF6BecA5d249554B7479261c5544a

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
