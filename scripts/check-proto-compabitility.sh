#!/bin/bash
set -e -x

# Download the main branch ref zip
protocol_main_zip_url="https://github.com/decentraland/protocol/archive/refs/heads/main.zip"
protocol_main_zip_local="./protocol-main.zip"

TMP_ZIP_DIR=$(mktemp -d)

curl -L "$protocol_main_zip_url" -o "$protocol_main_zip_local"
unzip "$protocol_main_zip_local" -d "$TMP_ZIP_DIR"
rm "$protocol_main_zip_local" || true

ln -s "$(pwd)/node_modules" "$TMP_ZIP_DIR/protocol-main/node_modules"

# Run the `proto-compatibility-tool` and exclude the downloaded folder.
echo "Checking the compatibility against $base_url"
./node_modules/.bin/proto-compatibility-tool --recursive "$TMP_ZIP_DIR/protocol-main" "."

# rm -rf "$TMP_ZIP_DIR" || true