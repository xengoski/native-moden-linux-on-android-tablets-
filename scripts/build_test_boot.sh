#!/usr/bin/env bash
# build_test_boot.sh
# Packages a mainline Linux kernel (Image), initramfs, and DTB into an Android
# boot image version 2 compatible with the Samsung Galaxy Tab A8 (SM-X205 / UMS512).

set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 --kernel <Image> --ramdisk <initramfs.img> --dtb <dtb_file> --out <output_boot.img> [options]

Options:
  --kernel       Path to arm64 kernel Image (e.g., Image or Image.gz)
  --ramdisk      Path to initramfs (e.g., Manjaro initramfs-linux.img)
  --dtb          Path to device tree blob (e.g., ums512-1h10.dtb or samsung.dtb)
  --cmdline      Kernel command line (default: "console=ttyS1,115200n8")
  --root         Optional root partition argument (e.g., "PARTUUID=0930e7b6-3b48-4cc7-ae34-31e19515f1f4 rw rootwait")
  --out          Path for the resulting boot image
EOF
    exit 1
}

KERNEL=""
RAMDISK=""
DTB=""
OUT=""
CMDLINE="console=ttyS1,115200n8"
ROOT_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel)  KERNEL="$2"; shift 2 ;;
        --ramdisk) RAMDISK="$2"; shift 2 ;;
        --dtb)     DTB="$2"; shift 2 ;;
        --cmdline) CMDLINE="$2"; shift 2 ;;
        --root)    ROOT_ARG="$2"; shift 2 ;;
        --out)     OUT="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
done

if [[ -z "$KERNEL" || -z "$RAMDISK" || -z "$DTB" || -z "$OUT" ]]; then
    usage
fi

if [[ -n "$ROOT_ARG" ]]; then
    CMDLINE="${CMDLINE} root=${ROOT_ARG}"
fi

echo "=== Building Android Boot Image (v2) for SM-X205 ==="
echo "Kernel:   $KERNEL"
echo "Ramdisk:  $RAMDISK"
echo "DTB:      $DTB"
echo "Cmdline:  $CMDLINE"
echo "Output:   $OUT"

# Samsung Galaxy Tab A8 SM-X205 Boot Image Parameters (Stock Header v2)
BASE_ADDR="0x00000000"
KERNEL_OFFSET="0x00008000"
RAMDISK_OFFSET="0x01000000"
TAGS_OFFSET="0x00000100"
DTB_OFFSET="0x01f00000"
PAGE_SIZE="2048"
HEADER_VERSION="2"

mkbootimg \
    --kernel "$KERNEL" \
    --ramdisk "$RAMDISK" \
    --dtb "$DTB" \
    --header_version "$HEADER_VERSION" \
    --pagesize "$PAGE_SIZE" \
    --base "$BASE_ADDR" \
    --kernel_offset "$KERNEL_OFFSET" \
    --ramdisk_offset "$RAMDISK_OFFSET" \
    --tags_offset "$TAGS_OFFSET" \
    --dtb_offset "$DTB_OFFSET" \
    --cmdline "$CMDLINE" \
    -o "$OUT"

echo "Boot image generated successfully at $OUT"
ls -lh "$OUT"
