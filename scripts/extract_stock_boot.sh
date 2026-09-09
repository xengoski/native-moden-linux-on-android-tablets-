#!/usr/bin/env bash
# extract_stock_boot.sh
# Unpacks Samsung Galaxy Tab A8 stock boot.img or boot.img.lz4 to inspect
# header metadata, kernel, ramdisk, and DTB structures.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <boot.img or boot.img.lz4> [output_directory]"
    exit 1
fi

INPUT_IMG="$1"
OUT_DIR="${2:-boot_unpacked}"

mkdir -p "$OUT_DIR"

if [[ "$INPUT_IMG" == *.lz4 ]]; then
    echo "Decompressing LZ4 image..."
    RAW_IMG="${OUT_DIR}/boot_raw.img"
    lz4 -d "$INPUT_IMG" "$RAW_IMG"
    INPUT_IMG="$RAW_IMG"
fi

echo "Unpacking Android boot image metadata..."
unpack_bootimg --boot_img "$INPUT_IMG" --out "$OUT_DIR"

echo "=== Extracted Components ==="
ls -lh "$OUT_DIR"

if [[ -f "${OUT_DIR}/dtb" ]]; then
    echo "Checking DTB structure..."
    file "${OUT_DIR}/dtb"
    strings "${OUT_DIR}/dtb" | grep -i -E "ums512|x205|samsung|sprd" | head -n 20 || true
fi
