# Protocol definitions

This module is intended to be installed as a node_module via `npm install @dcl/protocol`.

It is recommended that every project compiles the needed files only as part of its build process. Some imports are required:

- `-I=$(pwd)/node_modules/protobufjs`
- `-I=$(pwd)/node_modules/@dcl/protocol`

An example compilation looks like this:

```bash
protoc \
  --plugin=./node_modules/.bin/protoc-gen-ts_proto \
  --ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen \
  --ts_proto_out="$(pwd)/out-ts" \
  -I="$(pwd)/node_modules/protobufjs" \
  -I="$(pwd)/node_modules/@dcl/protocol" \
  "$(pwd)/node_modules/@dcl/protocol/bff-services.proto"
```
