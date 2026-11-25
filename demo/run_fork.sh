#!/usr/bin/env bash
# Local demo on a fork of Aevum testnet (real tUSD8, no funds needed, nothing leaves your machine).
# Uses anvil's PUBLIC test keys, so this only ever runs on the local fork (chain 440050).
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
RPC=http://127.0.0.1:8555
TUSD8=0x456569838f1d43009A91ebA4263147Afd7233483
MM=0x4d4b7031D35B74215bebe33F6AF6e682Ea99d0b1
OWNER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil #0 (public)
AGENT_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d   # anvil #1 (public)
OWNER=$(cast wallet address --private-key $OWNER_KEY); AGENT=$(cast wallet address --private-key $AGENT_KEY)
SHOP=0x70997970C51812dc3A010C7d01b50e0d17dc79C8; ATTACKER=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
anvil --fork-url https://rpc-test.qday.info --hardfork shanghai --chain-id 440050 --port 8555 >/tmp/anvil.log 2>&1 &
AP=$!; trap 'kill $AP' EXIT; sleep 6
cast rpc anvil_impersonateAccount $MM --rpc-url $RPC >/dev/null; cast rpc anvil_setBalance $MM 0x56BC75E2D63100000 --rpc-url $RPC >/dev/null
cast send $TUSD8 "configureMinter(address,uint256)" $MM 1000000000000000 --from $MM --unlocked --rpc-url $RPC >/dev/null
cast send $TUSD8 "mint(address,uint256)" $OWNER 100000000 --from $MM --unlocked --rpc-url $RPC >/dev/null
GUARD=$(cd contracts && forge script script/DeployGuard.s.sol --rpc-url $RPC --broadcast --private-key $OWNER_KEY 2>&1 | awk '/AgentPayGuard/{print $2}' | tail -1)
echo "AgentPayGuard on fork: $GUARD"
cast send $TUSD8 "approve(address,uint256)" $GUARD 100000000 --private-key $OWNER_KEY --rpc-url $RPC >/dev/null
EXP=$(( $(date +%s) + 86400 ))
cast send $GUARD "setMandate(address,uint128,uint128,uint64)" $AGENT 50000000 15000000 $EXP --private-key $OWNER_KEY --rpc-url $RPC >/dev/null
cast send $GUARD "setMerchant(address,address,bool)" $AGENT $SHOP true --private-key $OWNER_KEY --rpc-url $RPC >/dev/null
echo "mandate: budget 50, per-payment cap 15, only SHOP allowed"
mkdir -p /tmp/inv; sed "s/MERCHANT_ADDR/$SHOP/" demo/invoices/good.txt > /tmp/inv/good.txt
sed "s/MERCHANT_ADDR/$SHOP/; s/ATTACKER_ADDR/$ATTACKER/" demo/invoices/poisoned.txt > /tmp/inv/poisoned.txt
echo "$AGENT_KEY" > /tmp/agentkey; export RPC GUARD OWNER AGENT_KEY_FILE=/tmp/agentkey
echo "--- 1) honest invoice"; python3 agent/pay_agent.py /tmp/inv/good.txt --gullible
echo "--- 2) poisoned invoice, worst-case agent obeys the injected note"; python3 agent/pay_agent.py /tmp/inv/poisoned.txt --gullible
echo "shop balance:     $(cast call $TUSD8 'balanceOf(address)(uint256)' $SHOP --rpc-url $RPC)"
echo "attacker balance: $(cast call $TUSD8 'balanceOf(address)(uint256)' $ATTACKER --rpc-url $RPC)"
echo "--- 3) owner revokes, then the honest invoice fails too"
cast send $GUARD "revoke(address)" $AGENT --private-key $OWNER_KEY --rpc-url $RPC >/dev/null
sed "s/MERCHANT_ADDR/$SHOP/; s/12/13/; s/1042/1044/" demo/invoices/good.txt > /tmp/inv/good2.txt
python3 agent/pay_agent.py /tmp/inv/good2.txt --gullible
rm -f /tmp/agentkey
