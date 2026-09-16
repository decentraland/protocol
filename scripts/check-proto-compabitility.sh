#!/bin/bash
set -euo pipefail

# Keep a single compatibility definition. The legacy proto-compatibility-tool
# aborts on valid reserved field names, while Buf validates both reserved names
# and wire-level schema changes against the current main branch.
if [[ ! -x ./node_modules/.bin/buf ]]; then
  make node_modules/.bin/buf
fi

./node_modules/.bin/buf breaking proto/ --against 'https://github.com/decentraland/protocol.git#subdir=proto'
