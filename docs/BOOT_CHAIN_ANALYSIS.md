# Boot Chain & Architecture Analysis

This document details the low-level boot chain architecture of the **Samsung Galaxy Tab A8 LTE (`SM-X205`)**, its Unisoc bootloader stages, Knox verification, and how bare-metal Linux was integrated into Samsung's boot pipeline.

---

## 1. Unisoc Boot Flow Overview

Unlike typical single-board computers (Raspberry Pi, Pine64, Radxa) which execute boot scripts (`boot.scr`) or read raw kernel images directly off FAT32/ext4 partitions, the Galaxy Tab A8 relies on Samsung's locked/signed multi-stage boot sequence designed for Android:

```
[ Power On ]
      │
      ▼
[ Boot ROM (Primary Boot Loader - PBL) ]
      │  Initializes core clocks, internal SRAM, and checks Boot Pins
      ▼
[ SPL Loader (splloader / Secondary Program Loader) ]
      │  Initializes DDR4 SDRAM, PMIC rails, and basic storage controllers
      ▼
[ SML / TOS (TrustZone & Secure OS) ]
      │  Loads Unisoc secure execution environment (ARM Trusted Firmware / TOS)
      ▼
[ Samsung Bootloader (ABOOT / Little Kernel derivative) ]
      │  Checks OEM unlock flag, parses PIT partition table, enforces Knox status
      ▼
[ Android Boot Image Loader ]
      │  Reads partition 'boot' (mmcblk0p40), parses Android bootimg Header v2
      ▼
[ Linux Kernel Execution ]
   ├── Loads Kernel to 0x00008000
   ├── Loads Ramdisk to 0x01000000
   ├── Passes DTB from 0x01f00000
   └── Jumps to Kernel entry point with cmdline
```

---

## 2. Bootloader Constraints & Knox State

To execute custom code on the Tab A8, standard Android security mechanisms were bypassed via Samsung's developer unlock procedure:

```text
ODIN MODE
PRODUCT NAME:          SM-X205
CURRENT BINARY:        Custom
FRP LOCK:              OFF
OEM LOCK:              OFF (U)
KG STATUS:             COMPLETED (00)
UNISOC SECURE BOOT:    ENABLE
WARRANTY VOID:         0x1 (0x304)
RP SWREV:              B6 Kb6,Kr6,Dt6,Ub6,Ubs6 S6
SECURE DOWNLOAD:       ENABLE
GRDM STATUS:           NORMAL (00000502)
```

### Critical Flags Analyzed:
1. **`OEM LOCK: OFF (U)`**: Bootloader signature enforcement is lifted for boot images. Unsigned or custom-signed kernel payloads are permitted to load into RAM and execute.
2. **`WARRANTY VOID: 0x1`**: The hardware eFuse has been permanently blown. Samsung Knox services (Secure Folder, Knox Vault) are dead, but low-level flashing remains unobstructed.
3. **`KG STATUS: COMPLETED`**: KnoxGuard (enterprise lock / MDM) is satisfied and not actively intercepting or blocking boot attempts.
4. **`CURRENT BINARY: Custom`**: Confirms that Samsung's bootloader acknowledges and accepts the presence of a non-Samsung binary on the `boot` partition without aborting to Download Mode on integrity alone.

---

## 3. The Bare-Metal Linux Strategy

In traditional postmarketOS or Halium installations, Android system services or a compatibility wrapper are maintained in the background (or Halium initramfs scripts emulate Android userspace). 

In this **Manjaro Hail Mary** project, the objective was the complete eradication of Android userspace:

```
+-------------------------------------------------------+
|                    Target System                      |
+-------------------------------------------------------+
| Distro:        Manjaro ARM (Arch Linux aarch64 base)  |
| Kernel:        Mainline Linux 6.x (upstream torvalds) |
| Early Init:    Arch Linux systemd initramfs           |
| Userspace:     KDE Plasma Desktop (Wayland / DRM)     |
| Android Stack: None (0% Android runtime, no libhybris)|
+-------------------------------------------------------+
```

To achieve this without U-Boot:
1. **Kernel Injection:** Mainline `Image` was packaged as the kernel payload.
2. **Initramfs Substitution:** Android's stock `init` binary and recovery ramdisks were replaced with Arch Linux's `initramfs-linux.img`.
3. **DTB Injection:** Mainline UMS512 Device Tree Blobs (`ums512-1h10.dtb`) or stock Samsung DTBs were passed via the v2 header offset.
4. **Root Filesystem Hand-off:** Command line arguments (`root=PARTUUID=... rw rootwait`) were directed to an external high-speed MicroSD card partition or internal userdata (`/dev/mmcblk0p56`).

Despite matching the boot image header version 2 and memory offsets to the microsecond of the stock image, execution encountered severe hardware bring-up roadblocks at the kernel stage.
