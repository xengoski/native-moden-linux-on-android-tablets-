# Samsung Galaxy Tab A8 (`SM-X205`) Boot Image Specifications

This document outlines the low-level Android boot image (version 2) header offsets, partition sizes, and memory layouts extracted directly from the factory Samsung firmware (`X205XXS6DYG6`).

---

## 1. Stock Android Boot Image Metadata

Extracted using `unpack_bootimg --boot_img fw/boot.img`:

```text
boot magic:                     ANDROID!
boot image header version:      2
kernel size:                    21,878,800 bytes (~20.86 MiB)
kernel load address:            0x00008000
ramdisk size:                   700,196 bytes (~683.7 KiB)
ramdisk load address:           0x01000000
second bootloader size:         0
second bootloader load address: 0x00000000
kernel tags load address:       0x00000100
page size:                      2048 bytes
os version:                     11.0.0
os patch level:                 2025-08
product name:                   SRPUI28A006
command line args:              console=ttyS1,115200n8
additional command line args:   (empty)
recovery dtbo size:             0
recovery dtbo offset:           0x0000000000000000
boot header size:               1660 bytes
dtb size:                       163,537 bytes (~159.7 KiB)
dtb address:                    0x0000000001f00000
```

---

## 2. Memory Offset Comparison Table

| Field | Stock Samsung Image (`fw/boot.img`) | Custom Mainline Image (`test_boot.img`) | Status / Alignment |
| :--- | :--- | :--- | :--- |
| **Magic** | `ANDROID!` | `ANDROID!` | Identical |
| **Header Version** | `2` | `2` | Identical |
| **Page Size** | `2048` | `2048` | Identical |
| **Base Address** | `0x00000000` | `0x00000000` | Identical |
| **Kernel Offset** | `0x00008000` | `0x00008000` | Identical |
| **Ramdisk Offset** | `0x01000000` | `0x01000000` | Identical |
| **Tags Offset** | `0x00000100` | `0x00000100` | Identical |
| **DTB Offset** | `0x01f00000` | `0x01f00000` | Identical |
| **Cmdline** | `console=ttyS1,115200n8` | `console=ttyS1,115200n8` | Identical base |
| **Kernel Size** | `21,878,800` bytes (Android 4.14) | `42,277,376` bytes (Linux 6.x `Image`) | Mainline is ~2× larger |
| **Ramdisk Size** | `700,196` bytes (Samsung minimal) | `7,880,682` bytes (Manjaro full) | Manjaro initramfs includes modules |
| **DTB Size** | `163,537` bytes (Vendor full) | `15,072` bytes (`ums512-1h10.dtb`) | 10× difference in hardware nodes |

---

## 3. Partition Information (from Heimdall PIT)

The SM-X205 uses a unified non-A/B partition layout:

* **`boot` partition block count:** `131072` blocks (512 bytes/block) = `67,108,864` bytes (**64 MiB**)
* **`recovery` partition block count:** `131072` blocks = **64 MiB**
* **`dtbo` partition block count:** `16384` blocks = **8 MiB**
* **`super` partition block count:** `8912896` blocks = **4.25 GiB** (Houses Android system/vendor/product dynamic partitions)
* **`userdata` partition block count:** Remainder of the 32GB/64GB eMMC storage (`/dev/block/mmcblk0p56`)

The assembled `test_boot.img` measured **50,178,048 bytes (~47.85 MiB)**, comfortably fitting inside the 64 MiB `boot` partition boundary with over 16 MiB headroom.
