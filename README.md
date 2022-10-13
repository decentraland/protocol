# Protocol definitions

This module is intended to be installed as a node_module via `npm install @dcl/protocol`.

It is recommended that every project compiles the needed files only as part of its build process. Some imports are required:

- `-I=$(pwd)/node_modules/@dcl/protocol/public`
- `-I=$(pwd)/node_modules/@dcl/protocol/proto`

An example compilation looks like this:

```bash
protoc \
  --plugin=./node_modules/.bin/protoc-gen-ts_proto \
  --ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen \
  --ts_proto_out="$(pwd)/out-ts" \
  -I="$(pwd)/node_modules/@dcl/protocol/public" \
  -I="$(pwd)/node_modules/@dcl/protocol/proto" \
  "$(pwd)/node_modules/@dcl/protocol/public/bff-services.proto"
```

# Style Guidelines
1. All .proto files are snake_case.proto.
2. For pascal or camel case usage, please make a deterministic one from the snake case. Example: nft_shape will transform to NftShape.
3. See https://docs.buf.build/best-practices/style-guide. The most of other styles are taken from there, the Buf configuration is in proto/buf.yml.
4. Use public/ folder only for .proto with protocol exposing, that is only for files with `import public`. This folder is not processed by the linter.