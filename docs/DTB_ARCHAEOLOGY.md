# Device Tree Archaeology: Mainline vs. Vendor Samsung DTB

The Device Tree Blob (DTB) is the critical hardware description that tells an ARM64 Linux kernel how to talk to physical memory, interrupt controllers, clocks, regulators, display buses, and peripheral controllers.

During this project, extensive reverse engineering and comparative analysis were conducted between **Upstream Mainline Linux DTS** and **Samsung's Factory DTB Blob**.

---

## 1. Upstream Linux Mainline DTB: `ums512-1h10.dts`

The mainline kernel (`torvalds/linux`) includes baseline support for the Unisoc UMS512 SoC:
* `arch/arm64/boot/dts/sprd/ums512.dtsi` (SoC architecture definitions)
* `arch/arm64/boot/dts/sprd/ums512-1h10.dts` (Unisoc 1H10 evaluation / reference development board)

### Size Comparison:
* **Compiled `ums512-1h10.dtb`:** `15,072 bytes` (~14.7 KiB)
* **Samsung Stock DTB (`samsung.dtb`):** `163,537 bytes` (~159.7 KiB)

The upstream mainline DTB is more than **10× smaller** than the vendor DTB.

### What Upstream Mainline Defines:
```dts
/dts-v1/;
#include "ums512.dtsi"

/ {
    model = "Spreadtrum UMS512 1H10 Board";
    compatible = "sprd,ums512-1h10", "sprd,ums512";

    aliases {
        serial0 = &uart0;
        serial1 = &uart1;
    };

    memory@80000000 {
        device_type = "memory";
        reg = <0x0 0x80000000 0x0 0x80000000>;
    };

    chosen {
        stdout-path = "serial1:115200n8";
    };
};
```

### Upstream Supported Subsystems:
* Basic CPU topology (2× Cortex-A75 @ 2.0 GHz, 6× Cortex-A55 @ 1.8 GHz)
* GICv3 interrupt controller
* Core system timers and ARM architected timers
* UART serial interfaces (`uart0`, `uart1`)
* Basic SDHCI controller (`sdio0`, `sdio1`)
* Minimal clock tree declarations

### What Upstream Mainline Lacks for Galaxy Tab A8:
* **Display Engine & DSI Bridge:** No panel timing parameters, DSI controller configuration, or backlight PWM nodes.
* **Touch Digitizer:** No I2C bus wiring or GPIO interrupt bindings for the tablet's capacitive touch panel.
* **PMIC & Regulators:** No SC2730 / SC2721 PMIC power-distribution tree. Regulators default to unmanaged or bootloader-latched states.
* **Sound / Audio Routing:** Completely absent Unisoc VBC (Voice Band Codec) and DSP bindings.
* **Wi-Fi / Bluetooth:** Broadcom/Unisoc combo wireless chips lack firmware-loading and SDIO attachment nodes.

---

## 2. Samsung Stock DTB Blob: `samsung.dtb`

Extracted directly from the factory `boot.img`, the vendor DTB contains exhaustive vendor-specific hardware mappings:

```text
dtb size: 163,537 bytes
strings sample:
  sprd,sc2730
  sprd,ums512-25c10
  samsung,gta8
  sec,panel-nt36672c
  goodix,gt9886
  sprd,iommu-v1
  sprd,vbc
```

### Embedded Android Cmdline:
The stock DTB contains an embedded `chosen` node passing dozens of proprietary Android boot arguments:
```text
console=ttyS1,115200n8 earlycon=sprd_serial,0x70100000,115200n8 androidboot.hardware=ums512_25c10 androidboot.boot_devices=soc/soc:ap-ahb/20300000.sdio androidboot.serialno=...
```

---

## 3. The Failure Paradox: Why Neither DTB Booted

| Device Tree Blob | Kernel Compatibility | Hardware Coverage | Boot Behavior | Failure Reason |
| :--- | :--- | :--- | :--- | :--- |
| **`ums512-1h10.dtb`** (Upstream Mainline) | **100% compatible** with Linux 6.x ABI | **< 15%** of Tab A8 physical peripherals | Booted kernel headless into early userspace; hung for ~3 mins; watchdog reboot loop. | Lacked display panel drivers (black screen) and storage/SD quirks; watchdog timed out. |
| **`samsung.dtb`** (Vendor Extracted) | **0% compatible** with Linux 6.x ABI | **100%** of Tab A8 physical peripherals | Immediate hard crash; dropped straight into Odin/Download Mode. | Incompatible with Linux 6.x DT parser; references non-existent vendor drivers and legacy 4.14 bindings. |

### Conclusion of DTB Archaeology
A vendor DTB from an Android 4.14 kernel cannot simply be fed to a modern mainline 6.x kernel. To make bare-metal Linux work, one would have to manually port and rewrite the panel, power regulator, and GPIO nodes from Samsung's 163 KiB DTB into an upstream-compliant DTS patch.
