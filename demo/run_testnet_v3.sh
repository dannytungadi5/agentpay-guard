#!/usr/bin/env bash
# Testnet demo of the v3 features: merchant-signed invoices, and two agents with different limits.
# Env: GUARD, KEYDIR (holds owner.pk agent.pk agent2.pk shop2.pk and *.addr). Testnet keys only.
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
RPC=${RPC:-https://rpc-test.qday.info}; T=0x456569838f1d43009A91ebA4263147Afd7233483
OK=$(cat $KEYDIR/owner.pk); OWNER=$(cat $KEYDIR/owner.addr)
A1=$(cat $KEYDIR/agent.addr); K1=$(cat $KEYDIR/agent.pk); A2=$(cat $KEYDIR/agent2.addr); K2=$(cat $KEYDIR/agent2.pk)
SHOP=$(cat $KEYDIR/shop2.addr); SK=$(cat $KEYDIR/shop2.pk); CHAIN=$(cast chain-id --rpc-url $RPC)
tx(){ cast send "$@" --legacy --rpc-url $RPC 2>&1 | grep -E "^status|^transactionHash" | tr -s ' ' | tr '\n' ' '; echo; }
own(){ tx "$@" --private-key $OK; }
oid(){ cast keccak "$1"; }
sign(){ # amount orderId deadline -> signature by the merchant
  cast wallet sign --private-key $SK --data "{\"types\":{\"EIP712Domain\":[{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"version\",\"type\":\"string\"},{\"name\":\"chainId\",\"type\":\"uint256\"},{\"name\":\"verifyingContract\",\"type\":\"address\"}],\"Invoice\":[{\"name\":\"merchant\",\"type\":\"address\"},{\"name\":\"payer\",\"type\":\"address\"},{\"name\":\"amount\",\"type\":\"uint256\"},{\"name\":\"orderId\",\"type\":\"bytes32\"},{\"name\":\"deadline\",\"type\":\"uint256\"}]},\"primaryType\":\"Invoice\",\"domain\":{\"name\":\"AgentPayGuard\",\"version\":\"1\",\"chainId\":$CHAIN,\"verifyingContract\":\"$GUARD\"},\"message\":{\"merchant\":\"$SHOP\",\"payer\":\"$OWNER\",\"amount\":\"$1\",\"orderId\":\"$2\",\"deadline\":\"$3\"}}"
}
echo "# owner approves guard"; own $T "approve(address,uint256)" $GUARD 1500000
EXP=$(( $(date +%s)+1209600 ))
echo "# agent 1 (Invoice bot): budget 1.0, cap 0.6, must present merchant-signed invoices"
own $GUARD "setMandate(address,uint128,uint128,uint64)" $A1 1000000 600000 $EXP
own $GUARD "setMerchant(address,address,bool)" $A1 $SHOP true
own $GUARD "setRequireSignedInvoice(address,bool)" $A1 true
echo "# agent 2 (Research bot): budget 0.3, cap 0.1, plain payments"
own $GUARD "setMandate(address,uint128,uint128,uint64)" $A2 300000 100000 $EXP
own $GUARD "setMerchant(address,address,bool)" $A2 $SHOP true
DL=$(( $(date +%s)+3600 )); O=$(oid inv-5001); SIG=$(sign 400000 $O $DL)
echo "# 1 agent1 pays a signed invoice 0.4"; tx $GUARD "payWithInvoice(address,address,uint256,bytes32,uint256,bytes)" $OWNER $SHOP 400000 $O $DL $SIG --private-key $K1
O2=$(oid inv-5002); SIG2=$(sign 400000 $O2 $DL)
echo "# 2 agent1 presents the 0.4 signature but asks for 0.6 (tampered) -> BadInvoiceSignature"
cast send $GUARD "payWithInvoice(address,address,uint256,bytes32,uint256,bytes)" $OWNER $SHOP 600000 $O2 $DL $SIG2 --private-key $K1 --gas-limit 300000 --legacy --rpc-url $RPC 2>&1 | grep -E "^status|^transactionHash" | tr -s ' ' | tr '\n' ' '; echo
echo "# 3 agent1 tries a plain pay() (no signed invoice) -> SignedInvoiceRequired"
cast send $GUARD "pay(address,address,uint256,bytes32)" $OWNER $SHOP 100000 $(oid inv-5003) --private-key $K1 --gas-limit 300000 --legacy --rpc-url $RPC 2>&1 | grep -E "^status|^transactionHash" | tr -s ' ' | tr '\n' ' '; echo
echo "# 4 agent2 pays 0.1 (within its cap)"; tx $GUARD "pay(address,address,uint256,bytes32)" $OWNER $SHOP 100000 $(oid res-6001) --private-key $K2
echo "# 5 agent2 asks 0.2 (over its 0.1 cap) -> OverPerTxCap"
cast send $GUARD "pay(address,address,uint256,bytes32)" $OWNER $SHOP 200000 $(oid res-6002) --private-key $K2 --gas-limit 300000 --legacy --rpc-url $RPC 2>&1 | grep -E "^status|^transactionHash" | tr -s ' ' | tr '\n' ' '; echo
echo "shop2 balance: $(cast call $T 'balanceOf(address)(uint256)' $SHOP --rpc-url $RPC)"
