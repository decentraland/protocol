#!/bin/bash
set -e -x

# Use BASE_BRANCH environment variable or default to main
BRANCH="${BASE_BRANCH:-main}"

# Download the reference branch zip
protocol_branch_zip_url="https://github.com/decentraland/protocol/archive/refs/heads/${BRANCH}.zip"
protocol_branch_zip_local="./protocol-${BRANCH}.zip"

TMP_ZIP_DIR=$(mktemp -d)

curl -L "$protocol_branch_zip_url" -o "$protocol_branch_zip_local"
unzip "$protocol_branch_zip_local" -d "$TMP_ZIP_DIR"
rm "$protocol_branch_zip_local" || true

ln -s "$(pwd)/node_modules" "$TMP_ZIP_DIR/protocol-${BRANCH}/node_modules"

# Run the `proto-compatibility-tool` and exclude the downloaded folder.
echo "Checking the compatibility against branch: ${BRANCH}"
./node_modules/.bin/proto-compatibility-tool --recursive "$TMP_ZIP_DIR/protocol-${BRANCH}/proto" "proto"
# ../proto-compatibility-tool/dist/bin.js --recursive "$TMP_ZIP_DIR/protocol-main" "."

# rm -rf "$TMP_ZIP_DIR" || true