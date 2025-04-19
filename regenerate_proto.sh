#!/bin/bash

set -e

echo "Regenerating Swift code from protobuf definitions..."

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc is not installed. Please install it first."
    echo "You can install it via brew: brew install protobuf"
    exit 1
fi

# Check if swift-protobuf plugin is installed
if ! command -v protoc-gen-swift &> /dev/null; then
    echo "Error: protoc-gen-swift is not installed. Please install it first."
    echo "You can install it via brew: brew install swift-protobuf"
    exit 1
fi

# Directory variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROTO_DIR="$SCRIPT_DIR/Sources/FileMirrorProtocol/Protos"
PROTO_FILE="FileMirrorProtocol.proto"

# Create output directory if it doesn't exist
mkdir -p "$PROTO_DIR"

echo "Generating Swift code from $PROTO_FILE..."

# Run protoc with the Swift plugin
protoc --proto_path="$PROTO_DIR" \
       --swift_opt=Visibility=Public \
       --swift_out="$PROTO_DIR" \
       "$PROTO_DIR/$PROTO_FILE"

echo "Swift code generation completed successfully!"
echo "Generated file: $PROTO_DIR/FileMirrorProtocol.pb.swift" 