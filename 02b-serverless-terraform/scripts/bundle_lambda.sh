#!/usr/bin/env bash
# Builds the folder that Terraform zips into the Lambda package:
# the handler plus the libraries it needs (the X-Ray SDK).
# Run from anywhere; the pipeline runs it before terraform init.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=build/lambda-src

rm -rf "$OUT"
mkdir -p "$OUT"
cp lambda/handler.py "$OUT/"

# Use a throwaway virtualenv so this works on runners where system pip is locked.
VENV="$(mktemp -d)"
trap 'rm -rf "$VENV"' EXIT
python3 -m venv "$VENV"

# Download Linux wheels built for the Lambda runtime (Python 3.12, x86_64), whatever
# machine this runs on. --no-deps because boto3/botocore are already in the runtime.
"$VENV/bin/pip" install --quiet --no-deps \
  --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 \
  --only-binary=:all: --target "$OUT" -r lambda/requirements.txt

echo "Lambda package folder ready: $(du -sh "$OUT" | cut -f1)"
