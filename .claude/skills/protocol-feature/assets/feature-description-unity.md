# Feature: <Feature Name>

<!-- Input for unity-explorer's dcl-sdk-feature-architect agent. Copy this file to the unity-explorer repo root as feature-description.md (execute mode only), then run from that repo:
     claude --agent dcl-sdk-feature-architect --permission-mode plan
   and prompt: "Read @feature-description.md and create a plan to implement that DCL SDK feature."
   The architect assumes ../protocol, ../js-sdk-toolchain and ../sdk7-test-scenes as siblings and never commits. -->

## Overview
One paragraph: what the feature does and why the SDK needs it. Link the proposal bundle and the protocol PR.

## Components

### PB<Name> (LWW — scene writes, Explorer reads)   <!-- or GOVS — Explorer writes, scene reads -->
Fields (from protocol.diff, numbers final):
- `optional <type> <field> = <n>;` // default <x> — <meaning>

Component ID: <nnnn> (verified with `scripts/next-component-id.sh --check <nnnn>` across every branch, open PR and engine copy; `make check-component-id` sees the local tree only)

## Behavior
- How the Explorer applies each field at runtime (the hook from the proposal's section 3: path:symbol)
- Asset lifecycle, pooling, cleanup (component removed, entity destroyed, world disposed)
- Scene-current guard and system ordering constraints
- For result components: what triggers a write and whether it is PUT (LWW) or APPEND (GOVS)

## Reference components
- <existing component with the same shape, e.g. AvatarNametag (#9829) for a new LWW component>

## Out of scope for Unity
- <anything the proposal assigns to another engine or a later PR>
