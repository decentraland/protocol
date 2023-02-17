#!/bin/bash

set -e # stop execution on first non-zero result

rm -rf "$(pwd)/out-ts" || true
rm -rf "$(pwd)/out-js" || true
rm -rf "$(pwd)/out-cs" || true

mkdir -p "$(pwd)/out-ts"
mkdir -p "$(pwd)/out-js"
mkdir -p "$(pwd)/out-cs"

for file in "$(pwd)"/public/*.proto; do 
  
  ts_proto_opt="esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen,oneof=unions"
  if [[ $file == *editor.proto ]]
  then
    ts_proto_opt="$ts_proto_opt,useMapType=true"
  fi
  echo "> Generating $file with options: $ts_proto_opt"

  node_modules/.bin/protoc \
    --plugin=./node_modules/.bin/protoc-gen-ts_proto \
    --csharp_out="$(pwd)/out-cs" \
    --ts_proto_opt="${ts_proto_opt}" \
    --ts_proto_out="$(pwd)/out-ts" \
    -I="$(pwd)/proto" \
    -I="$(pwd)/public" \
    "$file";
done

echo "> Compiling TS project"

node_modules/.bin/tsc -p tsconfig.json

rm -rf out-cs || true
