#!/bin/bash
# Copies the entire typechain-types folder from contracts to sdk generated
set -e

SRC="../contracts/typechain-types"
DEST="src/generated"

rm -rf "$DEST"
cp -r "$SRC" "$DEST"
echo "Copied typechain-types to src/generated."
