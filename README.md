# Native Modern Linux on Android Tablets: Galaxy Tab A8 (`SM-X205`) Bring-Up

[![Platform](https://img.shields.io/badge/Platform-Baremetal%20Linux%20(aarch64)-1793d1?logo=archlinux)](https://archlinuxarm.org/)
[![Distro Target](https://img.shields.io/badge/Distro-Manjaro%20ARM%20Generic%2023.02-35bf5c?logo=manjaro)](https://manjaro.org/)
[![Device](https://img.shields.io/badge/Device-Samsung%20Galaxy%20Tab%20A8%20LTE-0c4da2?logo=samsung)](https://www.samsung.com)
[![SoC](https://img.shields.io/badge/SoC-Unisoc%20Tiger%20T618%20(UMS512)-ff6600)](https://www.unisoc.com)
[![Status](https://img.shields.io/badge/Status-Failed%20%2F%20Shelved%20(Hardware%20Boundary)-critical)](#status--conclusion)

Extensive technical documentation, firmware reverse engineering, boot image tooling, and failure analysis for attempting to run **pure bare-metal Linux (Manjaro ARM / Arch Linux ARM with KDE Plasma)** directly on the **Samsung Galaxy Tab A8 LTE (`SM-X205`)** without Android runtime, Halium, or compatibility layers.

---

## Table of Contents

- [Project Motivation & Goal](#project-motivation--goal)
- [Target Hardware Architecture](#target-hardware-architecture)
- [The Bare-Metal Architecture](#the-bare-metal-architecture)
- [Firmware Archaeology & Discovery](#firmware-archaeology--discovery)
- [Boot Image Construction & Tooling](#boot-image-construction--tooling)
- [Storage & Root Filesystem Strategy](#storage--root-filesystem-strategy)
- [Experimental Trials & Failure Modes](#experimental-trials--failure-modes)
  - [Trial 1: Mainline DTB (`ums512-1h10.dtb`)](#trial-1-mainline-dtb-ums512-1h10dtb---watchdog-reboot-loop)
  - [Trial 2: Stock Vendor DTB (`samsung.dtb`)](#trial-2-stock-vendor-dtb-samsungdtb---abi-collapse--instant-crash)
- [Why the Project Failed: The Blind Bring-Up Boundary](#why-the-project-failed-the-blind-bring-up-boundary)
- [The Viable Path: What the Working Repository Got Right](#the-viable-path-what-the-working-repository-got-right)
- [Repository Structure](#repository-structure)
- [Status & Conclusion](#status--conclusion)

---

## Project Motivation & Goal

Typical Linux implementations on Android devices rely on Halium, Libhybris, PRoot/Chroot in Termux, or Droidian, keeping the vendor Android BSP kernel and low-level drivers active in an Android container.

This project was a **"Hail Mary" attempt at full bare-metal mainline Linux**:
* **Complete eradication of Android:** No Android runtime, no `super.img`, no Android `init`, and no proprietary Android HALs.
* **Direct Boot Execution:** Booting an upstream Linux 6.x `Image` and Arch Linux `initramfs` directly via Samsung's native secondary bootloader.
* **Desktop Userspace:** Running a complete Manjaro ARM KDE Plasma environment powered by the Unisoc Mali-G52 MP2 GPU and generic Linux drivers.

---

## Target Hardware Architecture

| Parameter | Specification |
| :--- | :--- |
| **Model** | Samsung Galaxy Tab A8 LTE (`SM-X205`, codename `gta8` / `gta8lte`) |
| **System on Chip** | Unisoc Tiger T618 (`UMS512` / `ums512_25c10`) |
| **CPU Architecture** | 64-bit ARMv8.2-A (2× Cortex-A75 @ 2.0 GHz + 6× Cortex-A55 @ 1.8 GHz) |
| **Graphics** | ARM Mali-G52 MP2 (Bifrost 2nd Gen) |
| **Display Panel** | 10.5" 1920×1200 WUXGA TFT LCD (MIPI-DSI via Novatek/Chililin controller) |
| **Storage / RAM** | 32GB/64GB eMMC 5.1 + MicroSD slot; 3GB/4GB LPDDR4X |
| **Boot Chain** | Unisoc BootROM $\rightarrow$ SPL $\rightarrow$ SML/TrustZone $\rightarrow$ Samsung ABOOT $\rightarrow$ `boot.img` |
| **Bootloader State** | `OEM LOCK: OFF (U)`, Knox blown (`WARRANTY VOID: 0x1`), single non-A/B `boot` partition (64 MiB) |

---

## The Bare-Metal Architecture

Because modern Samsung devices cannot boot standard U-Boot script files (`boot.scr`) directly from an SD card, Linux was packaged inside an Android **Boot Image Header Version 2**:

```
+------------------------------------------------------------------+
|                   Samsung Primary Bootloader                     |
+------------------------------------------------------------------+
                                │
                                ▼
+------------------------------------------------------------------+
|         Custom Android boot.img (Header Version 2)               |
|                                                                  |
|   ├── Kernel:     Mainline Linux 6.x Image (~42.2 MB)            |
|   ├── Ramdisk:    Manjaro ARM initramfs-linux.img (~7.9 MB)      |
|   └── DTB:        Mainline / Vendor Device Tree Blob             |
+------------------------------------------------------------------+
                                │
                                ▼
+------------------------------------------------------------------+
|               Linux Early Userspace (initramfs)                  |
|                                                                  |
|   ├── Loads essential storage & serial drivers                  |
|   ├── Searches for root filesystem via PARTUUID                  |
|   └── Mounts root partition and pivots to /sbin/init             |
+------------------------------------------------------------------+
                                │
                                ▼
+------------------------------------------------------------------+
|              Manjaro ARM Linux Root Filesystem                   |
|                                                                  |
|   ├── Partition:  MicroSD /dev/mmcblk1p2 (ext4)                  |
|   ├── Userspace:  systemd + Arch Linux aarch64                   |
|   └── Desktop:    Wayland compositor + KDE Plasma                |
+------------------------------------------------------------------+
```

---

## Firmware Archaeology & Discovery

Inspection of factory Samsung firmware dumps (`X205XXS6DYG6`) revealed several critical technical discoveries:

1. **Mainline SoC Parity:** Upstream Linux contains mainline device trees for the Unisoc UMS512 platform (`sprd/ums512.dtsi` and `sprd/ums512-1h10.dts`). Samsung's stock `dtbo.img` explicitly listed the platform as `"Unisoc UMS512 1H10 board"`.
2. **Boot Image Parameters (Extracted via `unpack_bootimg`):**
   ```text
   boot magic:                  ANDROID!
   boot image header version:   2
   kernel load address:         0x00008000
   ramdisk load address:        0x01000000
   tags load address:           0x00000100
   dtb load address:            0x01f00000
   page size:                   2048
   cmdline:                     console=ttyS1,115200n8
   ```
3. **Serial Console Configured:** Samsung's stock cmdline natively configured `console=ttyS1,115200n8`, confirming a hardware UART interface exists on the board.

See [`hardware/boot_headers.md`](hardware/boot_headers.md) and [`docs/BOOT_CHAIN_ANALYSIS.md`](docs/BOOT_CHAIN_ANALYSIS.md) for full metadata tables and analysis.

---

## Boot Image Construction & Tooling

Kernel and early userspace components were built and compiled:
* **Kernel:** Upstream `torvalds/linux` compiled for ARM64 with `CONFIG_SERIAL_SPRD=y`, `CONFIG_MMC_SDHCI_SPRD=y`, and `CONFIG_DRM_SPRD=y`.
* **Initramfs:** Extracted directly from `Manjaro-ARM-kde-plasma-generic-23.02.img`.
* **Packaging Tool:** Custom automation script invoking `mkbootimg` with exact stock offsets:

```bash
./scripts/build_test_boot.sh \
  --kernel /path/to/Image \
  --ramdisk /path/to/initramfs-linux.img \
  --dtb /path/to/ums512-1h10.dtb \
  --root "PARTUUID=0930e7b6-3b48-4cc7-ae34-31e19515f1f4 rw rootwait" \
  --out test_boot.img
```

The resulting 50.1 MiB image fits comfortably inside the 64 MiB physical `boot` partition.

---

## Storage & Root Filesystem Strategy

Two strategies were attempted to provide the Linux root filesystem:

1. **Internal Userdata Reformat (`/dev/block/mmcblk0p56`):**
   * Attempted to wipe Samsung's encrypted FBE userdata and format as ext4.
   * **Result:** Blocked. Production Samsung Android builds reject `adb root` (`adbd cannot run as root in production builds`), and without a pre-existing root shell or custom recovery (TWRP), eMMC partitions could not be re-partitioned.
2. **External MicroSD Card (`/dev/mmcblk1p2`):**
   * Flashed `Manjaro-ARM-kde-plasma-generic-23.02.img` to an SD card.
   * Root partition verified with PARTUUID `0930e7b6-3b48-4cc7-ae34-31e19515f1f4`.
   * Directed kernel to root via `root=PARTUUID=0930e7b6-3b48-4cc7-ae34-31e19515f1f4 rw rootwait`.

See [`docs/STORAGE_AND_ROOTFS.md`](docs/STORAGE_AND_ROOTFS.md) for detailed partition analysis.

---

## Experimental Trials & Failure Modes

Flashing was performed via Heimdall (`heimdall flash --boot <image> --no-reboot`).

### Trial 1: Mainline DTB (`ums512-1h10.dtb`) - Watchdog Reboot Loop

```text
[ Heimdall Flash ]
       │
       ▼
[ Samsung Boot Warning Splash Displayed ]
       │  "This tablet is not running Samsung's official software"
       ▼
[ Screen Freezes on Splash for ~3 Minutes ]
       │  Kernel executes headless; no display driver; initramfs blocks
       ▼
[ Unisoc Hardware Watchdog Times Out ]
       │  Hard SoC reset triggered
       ▼
[ Loop Repeats 3 Times ]
       │
       ▼
[ Halts in Samsung Sysdump Mode ]
```

* **Outcome:** The kernel booted and ran. However, because `ums512-1h10.dtb` only describes a serial-output evaluation board, the display panel was never initialized. The kernel sat in an unmanaged early userspace state until the Unisoc hardware watchdog timer expired, causing a 3-cycle reboot loop into `sysdump`.

### Trial 2: Stock Vendor DTB (`samsung.dtb`) - ABI Collapse & Instant Crash

To solve the missing peripheral problem, the 163 KiB vendor DTB extracted from Samsung firmware was packaged into the boot image:

```text
[ Heimdall Flash ]
       │
       ▼
[ Power On ]
       │
       ▼
[ Instant Kernel Abort / Panic ]
       │  Linux 6.x parser fails on legacy 4.14 vendor bindings & clock nodes
       ▼
[ Immediate Drop to Odin / Download Mode ]
       │  "ODIN MODE / CURRENT BINARY: Custom"
```

* **Outcome:** Instant collapse on boot. Legacy vendor device tree bindings created for Android 4.14 are structurally incompatible with modern Linux 6.x DT parsers, triggering a panic at instruction zero.

See [`docs/DTB_ARCHAEOLOGY.md`](docs/DTB_ARCHAEOLOGY.md) and [`docs/FAILURE_ANALYSIS_POSTMORTEM.md`](docs/FAILURE_ANALYSIS_POSTMORTEM.md) for complete technical breakdowns.

---

## Why the Project Failed: The Blind Bring-Up Boundary

The project hit a definitive technical dead end due to three insurmountable diagnostic bottlenecks:

1. **No Display Framebuffer:** Neither upstream nor vendor DTBs could initialize the Tab A8's Novatek MIPI-DSI display bridge under mainline Linux.
2. **No Hardware UART Console:** While `console=ttyS1,115200n8` was configured, accessing `ttyS1` physically requires micro-soldering copper wires to tiny test pads on the Tab A8 motherboard.
3. **No Interactive Feedback:** Without serial output or on-screen `dmesg`, troubleshooting kernel panics, SDHCI power faults, or initramfs crashes was operating completely in the dark.

---

## The Viable Path: What the Working Repository Got Right

While this repository documents the pure **bare-metal mainline "Hail Mary"** that ran headfirst into hardware silence, the companion repository **[`xengoski/galaxy-tab-a8-linux`](https://github.com/xengoski/galaxy-tab-a8-linux)** approached the problem from the opposite direction and succeeded in turning the Galaxy Tab A8 into a daily-drivable Linux tablet.

### Key Architectural Differences

| Subsystem | Bare-Metal Mainline (This Repo) | Droidian / Halium Port ([`galaxy-tab-a8-linux`](https://github.com/xengoski/galaxy-tab-a8-linux)) |
| :--- | :--- | :--- |
| **Kernel Stack** | Upstream Linux 6.x (generic ARM64) | Device-specific Android BSP / Halium 4.14 kernel |
| **Display & GPU** | **Dead / Black screen** (missing DSI panel DTS bindings) | **60 FPS Hardware-Accelerated** (Wayfire 0.9.0 via native `hwcomposer` & Mali-G52 MP2 GLES 3.2) |
| **Touch & Input** | Headless / No input handling (expected physical USB keyboard) | **Universal `/dev/uinput` touch keyboard** + kinetic multi-touch gesture daemon (`gta8-input-daemon`) |
| **Audio Routing** | Silent / Unmanaged Unisoc VBC | **Working internal speakers** routed through Unisoc VBC DAC0 via ALSA/PulseAudio |
| **Power & Battery** | Kernel watchdog timeout resets after ~3 minutes | **Stable FSA9685 USB-C sink charging lock** (`gta8-usb-debug.sh`) & proper PMIC rails |
| **Sensors** | Dead / No I2C sensor driver | **Auto-rotation** via `iio-sensor-proxy` + `sensorfwd` SensorHub integration |
| **Cellular (LTE)** | Dead / Missing baseband modem daemon | **Functional Unisoc LTE baseband** via `ofono2mm` + `modem_control` |
| **Storage / Boot** | Blocked on reformatting `/data` (ADB root locked out) | **Non-destructive dual-boot** alongside Samsung Android without wiping user data |

### What `galaxy-tab-a8-linux` Solved:

1. **Bypassing the Upstream Mainline Display Dead-End:**
   Instead of spending months reverse engineering the Novatek MIPI-DSI display bridge and writing a custom kernel panel driver, it utilized the vendor Android `hwcomposer` interface with libhybris. This unlocked 60 FPS compositor rendering directly on the Mali-G52 GPU without touching CPU software rasterization (`llvmpipe`).
2. **Preserving Low-Level Hardware Drivers:**
   By keeping the vendor BSP device tree, all the missing hardware that choked mainline (PMIC SC2730, FSA9685 charging lock, VBC audio DAC, SensorHub, touch digitizer) was active and working out of the box.
3. **Solving the Touch UX Challenge:**
   A major obstacle in pure Linux tablet ports is the lack of physical input during early setup. The working repo built custom daemons specifically for tablet ergonomics: a system-wide `/dev/uinput` touch keyboard, a sliding quick control center, and multi-touch trackpad gestures (2-finger kinetic scroll, opposing pinch-to-zoom disambiguation, and 3-finger app switching).
4. **Zero-Risk Dual-Booting:**
   Rather than risking a permanent brick by trying to repartition eMMC storage through broken `adb root` permissions, it loads via an initramfs bootloader integration, leaving Android untouched.

If you are looking for an **active, hardware-accelerated, daily-drivable desktop experience** on the Tab A8, refer directly to [**`xengoski/galaxy-tab-a8-linux`**](https://github.com/xengoski/galaxy-tab-a8-linux).

---

## Repository Structure

```
.
├── README.md                            # Complete technical project documentation
├── hardware/
│   ├── boot_headers.md                  # Extracted header offsets, memory addresses & PIT sizes
│   └── pit_dump.txt                     # Raw Heimdall partition table dump from SM-X205
├── docs/
│   ├── BOOT_CHAIN_ANALYSIS.md           # Samsung / Unisoc boot flow & Knox security analysis
│   ├── DTB_ARCHAEOLOGY.md               # Detailed comparison: Mainline vs. Vendor DTBs
│   ├── STORAGE_AND_ROOTFS.md            # Partition layouts, ADB root limits & MicroSD setup
│   └── FAILURE_ANALYSIS_POSTMORTEM.md   # Exhaustive post-mortem of Trial 1 and Trial 2 failures
└── scripts/
    ├── build_test_boot.sh               # mkbootimg wrapper for Android header v2 assembly
    └── extract_stock_boot.sh            # Samsung boot image unpacker and DTB extractor
```

---

## Status & Conclusion

> [!WARNING]
> **Conclusion:** Native bare-metal modern Linux (Manjaro ARM / Arch ARM) cannot boot to a functional interactive state on the Samsung Galaxy Tab A8 (`SM-X205`) out of the box. 

While the bootloader permits custom kernel execution, completing this port requires:
1. Writing a custom, from-scratch Device Tree Source (`.dts`) porting the Tab A8 display, touch, and PMIC nodes into modern Linux bindings.
2. Soldering physical UART RX/TX lines to the board for interactive kernel debugging.

This repository serves as a permanent technical archive and post-mortem of the attempt.
