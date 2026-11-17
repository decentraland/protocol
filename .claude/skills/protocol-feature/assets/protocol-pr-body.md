# Protocol PR body template

Fill-in body for a `decentraland/protocol` PR in the house style of #474, #489 and #499: plain lead, per-field semantics, field numbering, how to test, implementation links.

How to use: copy everything between the two rules into `pr-protocol.md` in the bundle, replace every `<...>`, delete the `<!-- -->` guidance and any section that does not apply, print the result in full, then `gh pr create --repo decentraland/protocol --base main --title "<title>" --body-file pr-protocol.md`.

| Kind | Title | Branch | Precedent |
|---|---|---|---|
| new component | `feat: <Name> component (id <NNNN>)` | `feat/<slug>` | #474 |
| field on an existing component | `feat: add <field> to <Message>` | `feat/<slug>` | #489 |
| scene API (`kernel/apis`) | `feat: <Service>.<Rpc> scene API` | `feat/<slug>` | #497 |

## Before you post

- [ ] Title matches the table above and the branch is `feat/<slug>`, because squash merge turns the title into the commit subject.
- [ ] The lead paragraph says what a scene can do now, not which files changed.
- [ ] Every new field has a type, a default and the sentence "unset changes nothing" (or the reason it cannot be `optional`, as with `repeated` fields).
- [ ] `## Field numbering` names the branches and open PRs checked today and every skipped number, because main carries no `reserved` lines for them.
- [ ] `make buf-lint && make test` and `make list-components-ids` ran on this branch and the body quotes their real output.
- [ ] Each `## Implementation` and `## Related` line is a real `owner/repo#N` or says "pending".
- [ ] The does-not-do sentence is present when a reader could assume a wider scope.
- [ ] The body was printed in full and read before `gh pr create`.
- [ ] After `github-actions[bot]` posts `# Test this pull request`, the `branch//` tarball URL goes verbatim into the SDK, unity and godot bundles.

---

<!-- Lead: the gap today and the one-line change, in plain language. Lowercase openers are fine (#489). No file list. -->
<What scenes cannot do today>. Adds <`field` / `Component` (id <NNNN>)> so <what a scene can now do>.

<!-- One paragraph per field or message. Each one: type, meaning, units, default, and the no-op case. "Unset changes nothing" is the sentence reviewers look for. -->
`<field>` (`optional <type>`, <units or range>) <meaning>. Default <value>: unset changes nothing, so existing scenes are unaffected.

<!-- New component only: who writes it, which entities it is valid on, what happens elsewhere, whether it is relayed (#474: "local to the client that renders it and is never relayed to other players, and only the scene the player currently stands in can write it"). -->
Valid on <entities>; ignored elsewhere. Written by <scene | engine>. <Local-only | relayed>. <LWW | grow-only, and why>.

<!-- What it deliberately does NOT do, when a reader could assume otherwise (#499: "This is voice-only and separate from the general audio effects proposed in #377"). -->
This does not <scope left out>; that stays <where it lives or a linked issue>.

## Field numbering

<!-- Paste the output of the cross-branch check, then the rationale in one or two sentences (#489). Keep a skipped number explicit so the next author does not reuse it. The commands (after `git fetch origin`):
for b in origin/main origin/experimental-bevy origin/protocol-squad origin/experimental; do echo $b; git show $b:proto/decentraland/sdk/components/<file>.proto | grep -nE '= [0-9]+;'; done
for b in $(git branch -r | grep -v HEAD); do git grep -h -o 'ecs_component_id) = [0-9]*' $b -- proto 2>/dev/null; done | sed 's/.*= //' | sort -n | uniq | tail
gh pr list --repo decentraland/protocol --state open
-->
Checked `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`, `origin/experimental` and open PRs on <date>.

* `<Message>` takes `<field> = <N>`; <N-1> is the last number on `main`.
* `<Message>` skips **<A-B>** because they are `<field names>` on `experimental-bevy` and stay reserved for them to land on `main` separately.
* Component id <NNNN>: next free after <max id on main> on `main`; open PRs claim <ids> (<#PRs>); `experimental-bevy` (and `protocol-squad`) use 1200-1203, 1206-1208, 1500, 1501, 1503 (1204-1205 are unused on every branch).

## How to test

```bash
make buf-lint && make test
make list-components-ids          # <NNNN> appears once
make check-component-id ID=<NNNN> # prints "id <NNNN> is free" on main before this PR
```

<!-- buf breaking: say what you ran and the result. Adding "optional" to an existing field or renaming a field is reported as breaking by buf 1.8.0 (WIRE_JSON); a new optional field passes. -->
<!-- `make buf-breaking` compares against `https://github.com/decentraland/protocol.git#subdir=proto` (Makefile), so it needs network and reads GitHub main, not your local branch. -->
`make buf-breaking` against `main`: <passes | reports "<rule>" on <field>, expected because <reason>>.

## Implementation

<!-- One line per repo, `owner/repo#N` so GitHub links it. Write "pending" until the PR exists and edit this body when it opens (`gh pr edit <N> --repo decentraland/protocol --body-file pr-protocol.md`). -->
- js-sdk-toolchain: decentraland/js-sdk-toolchain#<N> (pending)
- unity-explorer: decentraland/unity-explorer#<N> (pending)
- bevy-explorer: decentraland/bevy-explorer#<N> (pending) — vendored proto matches <main | experimental-bevy>
- godot-explorer: decentraland/godot-explorer#<N> (pending)

Merge order: this PR first, then every consumer repins from the `Test this pull request` tarball to the published `@dcl/protocol@next` build, then SDK and explorers, test scene last.

## Related

<!-- Drop lines that do not exist for this feature; keep the ADR line when ADR_BY_SIZE requires one. -->
- Test scene: decentraland/sdk7-test-scenes#<N> (`scenes/<x>,<y>-<slug>`, world `sdk7testscenes.dcl.eth` at `<x>,<y>`)
- Docs: decentraland/docs#<N> (draft until an `@dcl/sdk` release)
- SDK skills: decentraland/sdk-skills#<N>
- ADR: decentraland/adr#<N> (ADR-<NNN>, Draft; branch preview <https://<branch-slug>.adr-cvq.pages.dev>)

---

## Last verified

2026-10-10 against protocol `d7ddc10` (origin/main; ids compared across `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`, `origin/experimental`), `Makefile` (`BUF_VERSION=1.8.0`, `buf-breaking` against `https://github.com/decentraland/protocol.git#subdir=proto`), `proto/buf.yaml` (`WIRE_JSON`), `scripts/check-component-id.sh`, and PRs #474, #489, #499, #497 read with `gh pr view`.
