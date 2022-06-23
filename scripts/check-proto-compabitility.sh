#!/bin/bash

# Download the main branch ref zip
protocol_main_zip_url="https://github.com/decentraland/protocol/archive/refs/heads/main.zip"
protocol_main_zip_local="./protocol-main.zip"

curl -L "$protocol_main_zip_url" -o "$protocol_main_zip_local"
rm -rf ./temp || true
unzip "$protocol_main_zip_local" -d ./temp
rm "$protocol_main_zip_local" || true


# Run the `proto-compatibility-tool` and exclude the downloaded folder.
echo "Checking the compatibility against $base_url"
for i in `find * -name "*.proto" -type f`; do
    if [[ $i != temp* ]]; then
        proto-compatibility-tool "$i" "./temp/protocol-main/${i}"
    fi
done

rm -rf ./temp || true