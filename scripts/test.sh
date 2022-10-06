#!/bin/bash

set -e # stop execution on first non-zero result

rm -rf "$(pwd)/out-ts" || true
rm -rf "$(pwd)/out-cs" || true

mkdir -p "$(pwd)/out-ts"
mkdir -p "$(pwd)/out-cs"

for file in "$(pwd)"/*.proto; do 
  echo "> Generating $file"
  node_modules/.bin/protoc \
    --plugin=./node_modules/.bin/protoc-gen-ts_proto \
    --csharp_out="$(pwd)/out-cs" \
    --ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen \
    --ts_proto_out="$(pwd)/out-ts" \
    -I="$(pwd)/node_modules/protobufjs" \
    -I="$(pwd)" \
    "$file";
done

echo "> Compiling TS project $file"

node_modules/.bin/tsc -p tsconfig.json

rm -rf out-js || true
rm -rf out-cs || true