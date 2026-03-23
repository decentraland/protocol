#!/usr/bin/env python3
"""
protoc-gen-bitwise — protoc plugin that generates C# bitwise serialization code.

Protocol:
  1. protoc writes a serialised CodeGeneratorRequest to this process's stdin.
  2. This plugin reads it, generates C# partial classes with Encode / Decode
     methods for every message that carries [(quantized)] or [(bit_packed)]
     field annotations.
  3. A serialised CodeGeneratorResponse is written to stdout.

Usage (from project root):
    protoc \\
      --proto_path=proto \\
      --bitwise_out=generated/ \\
      --plugin=protoc-gen-bitwise \\
      proto/my_messages.proto

Windows invocation (plugin not on PATH as executable):
    protoc \\
      --proto_path=proto \\
      --bitwise_out=generated/ \\
      --plugin=protoc-gen-bitwise=python protoc-gen-bitwise/plugin.py \\
      proto/my_messages.proto

Dependencies:
    pip install grpcio-tools   # or: pip install protobuf
"""

import os
import sys

# Ensure sibling modules (generator_csharp, options_pb2) are importable
# regardless of where protoc invokes this script from.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# On Windows, stdin/stdout are opened in text mode by default which corrupts
# the binary protobuf payload.
if sys.platform == 'win32':
    import msvcrt
    msvcrt.setmode(sys.stdin.fileno(),  os.O_BINARY)
    msvcrt.setmode(sys.stdout.fileno(), os.O_BINARY)

from google.protobuf.compiler import plugin_pb2

from generator_csharp import generate_csharp


def main() -> None:
    request_bytes = sys.stdin.buffer.read()

    request = plugin_pb2.CodeGeneratorRequest()
    request.ParseFromString(request_bytes)

    response = plugin_pb2.CodeGeneratorResponse()
    # Advertise proto3-optional support so protoc does not reject the plugin.
    response.supported_features = (
        plugin_pb2.CodeGeneratorResponse.FEATURE_PROTO3_OPTIONAL
    )

    # Build a lookup map for all file descriptors (needed for imports, though
    # the current generator only uses the directly requested files).
    file_by_name = {f.name: f for f in request.proto_file}

    for file_name in request.file_to_generate:
        # Skip the options definition file itself — it has no messages to generate.
        if file_name == 'decentraland/common/options.proto':
            continue

        file_proto = file_by_name.get(file_name)
        if file_proto is None:
            continue

        try:
            generated = generate_csharp(file_proto)
        except Exception as exc:  # noqa: BLE001
            error = response.file.add()
            error.name = ''  # empty name signals an error to protoc
            # Append error text; protoc will print it and fail.
            response.error = f'protoc-gen-bitwise: error processing {file_name}: {exc}'
            continue

        if generated is not None:
            out = response.file.add()
            out.name    = generated['name']
            out.content = generated['content']

    sys.stdout.buffer.write(response.SerializeToString())


if __name__ == '__main__':
    main()
