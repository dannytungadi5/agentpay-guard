# Aevum testnet deployment (chain 44005)

Explorer: https://explorer-test.qday.info

| Item | Address / tx |
|---|---|
| AgentPayGuard | `0xd594B08D083A0f5661E9e49a8a99a7937f80fBa0` |
| tUSD8 | `0x456569838f1d43009A91ebA4263147Afd7233483` |
| Owner | `0x811B9707A74e43E6bF22dcCaa9dfFB3286492402` |
| Agent | `0x8C0f9364e8D3ac76b9E9C288b35514bad4f7CC17` |
| Shop (allowed) | `0x3BEcCb75b1F6f0066FAf1641d4dE43FEa8f03d1B` |
| Attacker (not allowed) | `0xEc78a54eB34f35a610382617929876d3e2Bdd1c4` |

Mandate: budget 3 tUSD8, cap 1.5 per payment, one allowed shop.

| Step | Result | Tx |
|---|---|---|
| Owner approves guard | ok | `0x79b3cd9f862c5123b7dfac476977d0cd0894e7c23354f4473dd946435c8f80d0` |
| setMandate | ok | `0x6f01a002ef0449ac4144e3b13fa4c3587bd7d0f5b1a1664ef6a104fa4a0744ea` |
| setMerchant (shop) | ok | `0xd9a6c603917089314ca55bffb173cd673410c65b1b9119badc62c25e475781d0` |
| Honest invoice, 1.2 to shop | PAID | `0x59e33e4271468d2c1fef2a8b515e7291044ec3ae248ccdc30cd61c06ad462667` |
| Poisoned invoice, 2.5 to attacker | REVERTED (MerchantNotAllowed) | `0x0e167b9082822d0e289e2b0203f3ad6b5dc37153d0b2e14a5d495c2ff37783d7` |
| Owner revokes | ok | `0x7b420fe0c0ab8067ec87009158b2a9d3d0c8a769828ccf9357e85a5fe59a5bc2` |
| Honest invoice after revoke | REVERTED (Revoked) | `0xafb8f849bc3be23d2838eb345528791aeb8623190cb7da98ac7ca2166e1f35b2` |

Final balances: shop 1.2 tUSD8, attacker 0.
These are testnet wallets with no value.
