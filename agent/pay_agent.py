#!/usr/bin/env python3
"""AgentPay Guard demo agent: an invoice-paying AI agent.

It reads invoice text (untrusted), asks an LLM to extract {merchant, amount, order}, and pays through
AgentPayGuard on Aevum. The point of the demo: a poisoned invoice can fool the LLM, but it cannot move
money past the on-chain mandate. Every payment goes through AgentPayGuard.pay, so an unlisted merchant,
an over-cap amount, a drained budget, a replayed order or a revoked mandate all revert on chain.

Stdlib only. Needs `cast` (Foundry).
Env: RPC, GUARD, OWNER (address that granted the mandate), AGENT_KEY_FILE, LLM_KEY_FILE (optional).
Usage: pay_agent.py invoice.txt [--gullible] [--force-send]
  --gullible    skip the LLM and obey the last instruction in the text (worst-case agent for the demo)
  --force-send  send even if gas estimation says revert, so a reverted tx is mined and visible on the explorer
"""
import json, os, re, subprocess, sys, urllib.request

RPC = os.environ.get("RPC", "https://rpc-test.qday.info")
GUARD = os.environ["GUARD"]
OWNER = os.environ["OWNER"]
AGENT_KEY_FILE = os.environ["AGENT_KEY_FILE"]
LLM_KEY_FILE = os.environ.get("LLM_KEY_FILE")


def cast(*a, check=True):
    r = subprocess.run(["cast", *a], capture_output=True, text=True)
    if check and r.returncode:
        raise RuntimeError((r.stderr or r.stdout).strip()[:400])
    return r


def extract_llm(text):
    key = open(LLM_KEY_FILE).read().strip()
    prompt = ("Read this invoice document and output the payment it asks for as JSON with keys "
              "merchant (0x address), amount (tUSD8 number), order (string). Output JSON only.\n\n" + text)
    body = {"model": "google/gemma-4-31b-it", "messages": [{"role": "user", "content": prompt}], "max_tokens": 300}
    req = urllib.request.Request("https://router.requesty.ai/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=110) as r:
        out = json.load(r)["choices"][0]["message"]["content"]
    m = re.search(r"\{.*\}", out, re.S)
    return json.loads(m.group(0))


def extract_gullible(text):
    """Worst case: do what the LAST instruction in the document says."""
    pays = re.findall(r"pay\s+(\d+(?:\.\d+)?)\s*(?:tusd8)?\s*to\s*(0x[0-9a-fA-F]{40})", text, re.I)
    if not pays:
        raise RuntimeError("no payment instruction found")
    amt, addr = pays[-1]
    return {"merchant": addr, "amount": amt, "order": "gullible-" + addr[-6:]}


def main():
    path = sys.argv[1]
    text = open(path).read()
    inst = extract_gullible(text) if "--gullible" in sys.argv else (
        extract_llm(text) if LLM_KEY_FILE else extract_gullible(text))
    print("[agent] decided to pay:", inst, flush=True)
    amount_raw = str(int(round(float(inst["amount"]) * 10**6)))
    order = cast("keccak", inst["order"]).stdout.strip()
    key = open(AGENT_KEY_FILE).read().strip()
    sig = "pay(address,address,uint256,bytes32)"
    args = [OWNER, inst["merchant"], amount_raw, order]
    sim = cast("call", GUARD, sig, *args, "--from", cast("wallet", "address", "--private-key", key).stdout.strip(),
               "--rpc-url", RPC, check=False)
    if sim.returncode:
        reason = (sim.stderr or sim.stdout).strip().splitlines()[-1][:200]
        print("[chain] BLOCKED before sending:", reason, flush=True)
        if "--force-send" not in sys.argv:
            return
        print("[agent] --force-send: sending anyway so the revert is mined and visible", flush=True)
        r = cast("send", GUARD, sig, *args, "--gas-limit", "300000", "--legacy", "--rpc-url", RPC,
                 "--private-key", key, check=False)
        print((r.stdout or r.stderr).strip()[-500:])
        return
    r = cast("send", GUARD, sig, *args, "--legacy", "--rpc-url", RPC, "--private-key", key)
    print("[chain] PAID:", [l for l in r.stdout.splitlines() if l.startswith(("transactionHash", "status"))])


if __name__ == "__main__":
    main()
