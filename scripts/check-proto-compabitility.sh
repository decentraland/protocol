#!/bin/bash
set -e -x

# Check if the first argument (branch_name) is provided
if [ -z "$1" ]; then
    echo "Error: Missing branch name parameter."
    echo "Usage: $0 <branch_name>"
    exit 1
fi

# Continue with the rest of the script
branch_name="$1"
echo "Branch name provided: $branch_name"

# Download the main branch ref zip
protocol_zip_url="https://github.com/decentraland/protocol/archive/refs/heads/${branch_name}.zip"
protocol_zip_local="./protocol-main.zip"

TMP_ZIP_DIR=$(mktemp -d)

curl -L "$protocol_zip_url" -o "$protocol_zip_local"
unzip "$protocol_zip_local" -d "$TMP_ZIP_DIR"
rm "$protocol_zip_local" || true

ln -s "$(pwd)/node_modules" "$TMP_ZIP_DIR/protocol-main/node_modules"

# Run the `proto-compatibility-tool` and exclude the downloaded folder.
echo "Checking the compatibility against $base_url"
./node_modules/.bin/proto-compatibility-tool --recursive "$TMP_ZIP_DIR/protocol-main/proto" "proto"
# ../proto-compatibility-tool/dist/bin.js --recursive "$TMP_ZIP_DIR/protocol-main" "."

# rm -rf "$TMP_ZIP_DIR" || true