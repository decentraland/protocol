# Proposals

A proposal is one directory per feature, `proposals/<slug>/`, holding the single document that carries a protocol change from an idea to merged PRs across the SDK and the three explorers, plus the artifacts each phase produces:

| File | Written by |
|---|---|
| `proposal.md` | every phase (need, design, technology verification, definition, implementation, review), with a Gate log and a Decision log |
| `protocol.diff` | phase 4, the exact `.proto` change |
| `actions.md` | phase 5, one brief per repo in merge order |
| `pr-<repo>.md` | phases 4-5, the PR body each repo will carry |
| `review.md` | phase 6 |

The process, the gates and the policy values are documented in `.claude/skills/protocol-feature/references/process.md` and `references/policy.md`; the skills under `.claude/skills/protocol-*` drive it (`/protocol-feature "<idea>"` to start, `--draft` to simulate all six phases without opening anything).

## Lifecycle

`draft -> designed -> verified -> defined -> implementing -> in-review -> done`, with `rejected`, `blocked` and `parked` as exits. The frontmatter `status` and `phase` fields are the source of truth; `scripts/proposal-gate.sh status` lists every bundle.

## What gets committed

- A real feature commits its bundle in the protocol PR that defines it, so the reasoning, the numbering rationale and the per-engine verification stay next to the schema they changed.
- A simulation (`--draft`, dry runs, hypothetical scenarios) stays local unless it is worth keeping as a worked example; the reference example lives in `.claude/skills/protocol-feature/examples/`.
- `rejected` and `parked` bundles are deleted after the decision is recorded in the related issue or PR, so this directory only lists live work.
