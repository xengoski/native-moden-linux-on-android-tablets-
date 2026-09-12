# Technical Post-Mortem & Comprehensive Failure Analysis

This post-mortem documents the failure mechanisms, hardware behavior, and debugging boundaries encountered while attempting to boot bare-metal mainline Linux (Manjaro ARM) on the **Samsung Galaxy Tab A8 LTE (`SM-X205`)**.

---

## 1. Summary of Experimental Trials

Two primary boot configurations were assembled and flashed to the physical `boot` partition using `heimdall`:

```
Trial 1: [Mainline 6.x Image] + [Manjaro initramfs] + [Mainline ums512-1h10.dtb (15 KB)]
         └── Result: Bootloader accepted; display frozen for ~3 mins; 3× watchdog reboot loop; dropped into Sysdump.

Trial 2: [Mainline 6.x Image] + [Manjaro initramfs] + [Stock Samsung DTB (163 KB)]
         └── Result: Bootloader accepted; immediate hard crash; dropped straight into Odin/Download Mode.
```

---

## 2. Deep Dive: Trial 1 Failure (Mainline DTB & Watchdog Timeout)

### Flashing Command:
```bash
heimdall flash --boot test_boot.img --no-reboot
```

### Observed Physical Behavior:
1. The tablet rebooted out of Download Mode.
2. The display powered on and rendered Samsung's red/orange unlocked bootloader warning:
   > *"This tablet is not running Samsung's official software..."*
3. The Samsung boot splash remained completely static on screen.
4. The tablet sat in this exact state for **approximately 3 minutes**.
5. After ~3 minutes, the device automatically reset, re-displayed the warning, repeated this cycle **exactly 3 times**, and finally halted at Samsung's low-level **`sysdump`** hardware crash screen.

### Root Cause Analysis:
* **The Kernel Booted:** If the bootloader rejected the boot image signature, header format, or memory offsets, the device would immediately abort to Odin mode within milliseconds. Remaining alive for 3 minutes is conclusive proof that Samsung's bootloader successfully jumped to the kernel entry point (`0x00008000`).
* **Display Engine Silence:** The upstream `ums512-1h10.dtb` describes a reference development board that outputs to a serial console. It has zero definitions for the Tab A8's Novatek MIPI-DSI display bridge or backlight PWM. Consequently, the display framebuffer was never claimed by the kernel, leaving the last hardware image painted by the bootloader (the warning splash) frozen on the LCD panel.
* **Storage & Rootfs Starvation:** In headless early userspace, the kernel either:
  1. Failed to power up the MicroSD card slot due to missing regulator mappings (`vmmc-supply`), causing `initramfs` to block indefinitely waiting for `PARTUUID=0930e7b6-3b48-4cc7-ae34-31e19515f1f4`.
  2. Hit a kernel panic inside early init.
* **Watchdog Reset:** Because userland never initialized to pet the Unisoc hardware watchdog timer (`/dev/watchdog`), the hardware watchdog expired after its ~180-second countdown, triggering a hard SoC reset. After three consecutive hardware resets, the primary bootloader flagged a critical boot failure and entered `sysdump`.

---

## 3. Deep Dive: Trial 2 Failure (Stock Vendor DTB & ABI Collapse)

Hypothesizing that the mainline DTB lacked essential board peripherals, the stock 163 KiB DTB blob extracted from Samsung's firmware (`samsung.dtb`) was bundled into `test_boot_samsungdtb.img`.

### Flashing Command:
```bash
heimdall flash --boot test_boot_samsungdtb.img --no-reboot
```

### Observed Physical Behavior:
1. Flash completed successfully.
2. The tablet attempted to power on.
3. Instead of sitting on the boot splash or executing into userspace, the tablet **immediately crashed** and defaulted straight back to the Odin/Download screen:
   ```text
   ODIN MODE
   PRODUCT NAME: SM-X205
   CURRENT BINARY: Custom
   ...
   ```

### Root Cause Analysis:
* **Device Tree ABI Incompatibility:** Samsung's stock DTB was generated for an Android 4.14 legacy kernel branch with dozens of out-of-tree Spreadtrum/Unisoc patches (`sprd,sc2730-pmic`, `sprd,iommu-v1`, proprietary clock and power-domain nodes).
* **Early Kernel Abort:** When a modern 6.x mainline kernel parses a Device Tree containing alien or defunct bindings, missing mandatory standard properties (like `#clock-cells`, updated interrupt flags, or standardized regulator hierarchies), it triggers an unhandled page fault or early panic before even console registration occurs.
* **Immediate Fallback:** With the kernel exploding at instruction zero, the bootloader's boot-failure counter triggered immediately, vectoring the CPU back into Download Mode.

---

## 4. The Blind Bring-Up Boundary

The decisive technical barrier that forced this project to stall was the **inability to observe execution in real time**:

```
+-------------------------------------------------------------+
|               The "Blind Bring-Up" Problem                  |
+-------------------------------------------------------------+
| 1. No Serial Console:    console=ttyS1 requires micro-soldering |
|                          to test pads on the motherboard.    |
| 2. No Display Output:    Upstream DTS lacks panel drivers.  |
| 3. No ADB Connectivity:  Linux kernel never reached USB gadget|
|                          initialization.                    |
| 4. No pstore / ramoops:  Crash logs in RAM were wiped or    |
|                          locked by Samsung's secure boot.   |
+-------------------------------------------------------------+
```

Without an interactive serial console or visual framebuffer output, diagnosing exact kernel panic stack traces or missing driver symbols degraded into pure guesswork.

---

## 5. Conclusion & Final State

The bare-metal Manjaro ARM attempt demonstrated that:
1. **The Samsung bootloader is not the blocker:** It happily loads custom 64-bit ARM kernels via Android boot image header version 2.
2. **Mainline UMS512 code exists:** The core SoC boots.
3. **The definitive blocker is board-level DTS support:** Mainline lacks display, touch, and PMIC drivers for the Tab A8, while vendor DTBs cannot be parsed by modern kernels.

At this juncture, the bare-metal Linux installation attempt is concluded and documented as **failed** due to the requirement for custom board DTS engineering and hardware serial soldering.
