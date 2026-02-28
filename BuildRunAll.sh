#!/bin/bash
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if command -v buildrun >/dev/null 2>&1; then
    exec buildrun --project-dir "$DIR" "$@"
else
    exec "$DIR/../buildrun" --project-dir "$DIR" "$@"
fi
