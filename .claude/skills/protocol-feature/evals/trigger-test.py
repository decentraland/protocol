#!/usr/bin/env python3
"""Trigger test for the protocol-feature router description, run against the real repo.

For every query in the eval set it runs `claude -p <query>` with the repo as cwd (plan permission mode,
so nothing is written) and records whether the protocol-feature skill (or a phase skill) was invoked as the
FIRST tool call (immediate) or within MAX_TOOLS tool calls (eventual). A query is a pass when the majority
of its runs match its should_trigger flag. Needs python >= 3.10 and the `claude` CLI on PATH.

usage: python3 trigger-test.py evals/trigger-eval.json <repo-root> <runs-per-query> <workers> <out.json>
(run from the repo root; ~10 s per triggering run, up to 4 min per non-triggering one)"""
import json, os, subprocess, sys, time, select
from concurrent.futures import ThreadPoolExecutor
eval_set, repo, runs, workers, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
MAX_TOOLS, TIMEOUT = 6, 240
SKILL_MARK = "protocol-"
def one(query):
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    cmd = ["claude", "-p", query, "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-mode", "plan"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=repo, env=env)
    t0 = time.time(); buf = ""; tools = []; pending = None; acc = ""; immediate = None; eventual = False
    def decide(name, inp):
        nonlocal immediate, eventual
        hit = (name == "Skill" and SKILL_MARK in inp) or (name == "Read" and ".claude/skills/protocol-" in inp)
        if immediate is None: immediate = hit
        if hit: eventual = True
        return hit
    try:
        while time.time() - t0 < TIMEOUT and len(tools) < MAX_TOOLS and not eventual:
            if p.poll() is not None:
                rest = p.stdout.read(); buf += rest.decode("utf-8", "replace") if rest else ""; 
                if not buf.strip(): break
            r, _, _ = select.select([p.stdout], [], [], 1.0)
            if not r:
                if p.poll() is not None: break
                continue
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk: break
            buf += chunk.decode("utf-8", "replace")
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                try: ev = json.loads(line)
                except Exception: continue
                if ev.get("type") == "stream_event":
                    se = ev.get("event", {}); st = se.get("type")
                    if st == "content_block_start" and se.get("content_block", {}).get("type") == "tool_use":
                        pending = se["content_block"].get("name", ""); acc = ""
                    elif st == "content_block_delta" and pending:
                        d = se.get("delta", {})
                        if d.get("type") == "input_json_delta": acc += d.get("partial_json", "")
                    elif st == "content_block_stop" and pending:
                        tools.append(pending); decide(pending, acc); pending = None
                elif ev.get("type") == "result":
                    break
    finally:
        if p.poll() is None: p.kill(); p.wait()
    return {"immediate": bool(immediate), "eventual": eventual, "tools": tools, "secs": round(time.time() - t0)}
items = json.load(open(eval_set))
jobs = [(q["query"], q["should_trigger"], i) for q in items for i in range(runs)]
results = {}
with ThreadPoolExecutor(max_workers=workers) as ex:
    futs = {ex.submit(one, q): (q, st, i) for q, st, i in jobs}
    for f in futs:
        q, st, i = futs[f]
        try: r = f.result()
        except Exception as e: r = {"immediate": False, "eventual": False, "tools": [f"ERR {e}"], "secs": 0}
        results.setdefault(q, {"should_trigger": st, "runs": []})["runs"].append(r)
        print(f"[{'T' if st else 'F'}] imm={r['immediate']} evt={r['eventual']} {r['secs']}s tools={r['tools'][:4]} :: {q[:70]}", flush=True)
summary = {"immediate_pass": 0, "eventual_pass": 0, "total": len(results)}
for q, d in results.items():
    imm = sum(r["immediate"] for r in d["runs"]) / len(d["runs"]); evt = sum(r["eventual"] for r in d["runs"]) / len(d["runs"])
    d["immediate_rate"] = imm; d["eventual_rate"] = evt
    want = d["should_trigger"]
    summary["immediate_pass"] += int((imm >= 0.5) == want); summary["eventual_pass"] += int((evt >= 0.5) == want)
json.dump({"summary": summary, "results": results}, open(out, "w"), indent=1)
print(json.dumps(summary))
