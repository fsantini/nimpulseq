#!/bin/bash
# Delete all files in this directory with no extension or with .seq extension
dir="$(dirname "$0")"
find "$dir" -maxdepth 1 -type f \( -name "*.seq" -o ! -name "*.*" \) -delete
