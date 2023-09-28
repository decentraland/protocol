# Protocol definitions

This module is intended to be installed as a node_module via `npm install @dcl/protocol`.

It is recommended that every project compiles the needed files only as part of its build process. Some imports are required:

- `-I=$(pwd)/node_modules/@dcl/protocol/public`
- `-I=$(pwd)/node_modules/@dcl/protocol/proto`

An example compilation looks like this:

```bash
protoc \
  --plugin=./node_modules/.bin/protoc-gen-dcl_ts_proto \
  --dcl_ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen \
  --dcl_ts_proto_out="$(pwd)/out-ts" \
  -I="$(pwd)/node_modules/@dcl/protocol/public" \
  -I="$(pwd)/node_modules/@dcl/protocol/proto" \
  "$(pwd)/node_modules/@dcl/protocol/public/sdk-components.proto"
```

# Style Guidelines

1. All .proto files are snake_case.proto.
2. For pascal or camel case usage, please make a deterministic one from the snake case. Example: nft_shape will transform to NftShape.
3. See https://docs.buf.build/best-practices/style-guide. The most of other styles are taken from there, the Buf configuration is in proto/buf.yml.
4. Use public/ folder only for .proto with protocol exposing, that is only for files with `import public`. This folder is not processed by the linter.

# Dev with Decentraland Repositories

Many repositories depend on this protocol definition and that sometimes implies some merge order. We don't have to worry much about compatibility because the checks are running with each PR, if you break something, the CI will warn you. But, in some cases, it's desirable to merge the implementation in a specific order to avoid unexpected behavior in the corner cases (multiple repositories are waiting for the build at the same time).

> **Important Note: Avoid Merging Protocol PR Without Completed Unity Implementation**
>
> Please don't merge a protocol PR into the main branch unless the corresponding implementation in Unity has been completed. This is important to avoid any potential issues or build failures in Unity.
>
> The ideal order for introducing breaking changes in the protocol is as follows:
>
> 1. Create a PR in the Protocol repository.
> 2. Use the npm test link from the CI of the protocol PR in the protocol-dependent application for development.
> 3. Once both the protocol PR and the protocol-dependent application (e.g. unity-renderer) PR are ready for merging, synchronize their merging as follows:
>    1. Merge the protocol PR.
>    2. Modify protocol-dependent application PR to use the `@dcl/protocol@next` package to stop using the PR npm test link.
>    3. Merge the protocol-dependent application PR.

Some dev-cases are described here:

## SDK: New component or component modification

Repositories: [unity-renderer](https://github.com/decentraland/unity-renderer/) and [js-sdk-toolchain](https://github.com/decentraland/js-sdk-toolchain/)

At the protocol level both operations shouldn't be a problem, but `js-sdk-toolchain` CI will fail if the component is not tested. This can happen if the PR **`A`** from the protocol is merged, and you update your PR **`B`** from `js-sdk-toolchain` with the changes before the PR **`A`** from `js-sdk-toolchain` is merged.

Some guidelines and testing before merge:

- The protocol package is uploaded to S3 while developing in a PR. This can be used in the target repositories
- Testing in the playground: Playground allows us to test by adding query parameters: `https://playground.decentraland.org/?&renderer-branch=**feat/my-new-component**&sdk-branch=**feat/new-component-approach**`
- Testing locally: you can write an example scene and install the package `@dcl/sdk` uploaded to S3 commented in the PR comments.
- Testing in the Unity Editor: if you need to test with the editor opened, write the `ws` query parameter in your local or playground test.
- Start merging when the three PRs are already to merge: first merge the Protocol one, then update the other two with the version @next and merge them at the same time.

## SDK: New APIs or APIs modifications

Repositories: [kernel](https://github.com/decentraland/kernel/), [js-sdk-toolchain](https://github.com/decentraland/js-sdk-toolchain/) and [scene-runtime](https://github.com/decentraland/scene-runtime/)
In this case, there is no problem with when each PR is merged. It's recommendable to merge first the rpc server-side (in this case, Kernel), second the `scene-runtime` (and this would require a second update from `kernel`) and last the `js-sdk-toolchain`.

## Comms

TODO
