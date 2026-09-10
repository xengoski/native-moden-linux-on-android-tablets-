# Storage Architecture & Root Filesystem Obstacles

A functional bare-metal Linux installation requires a block device containing an unencrypted, writeable root filesystem (ext4 / btrfs). On the **Samsung Galaxy Tab A8 (`SM-X205`)**, provisioning and accessing storage presented significant technical hurdles.

---

## 1. eMMC Partition Layout (from ADB & PIT Inspection)

Inspecting `/dev/block/by-name/` revealed the storage geometry:

```text
lrwxrwxrwx 1 root root 21 2026-07-25 07:34 boot -> /dev/block/mmcblk0p40
lrwxrwxrwx 1 root root 21 2026-07-25 07:34 dtbo -> /dev/block/mmcblk0p41
lrwxrwxrwx 1 root root 21 2026-07-25 07:34 recovery -> /dev/block/mmcblk0p42
lrwxrwxrwx 1 root root 21 2026-07-25 07:34 super -> /dev/block/mmcblk0p49
lrwxrwxrwx 1 root root 21 2026-07-25 07:34 userdata -> /dev/block/mmcblk0p56
```

---

## 2. Plan A: Reformatting Internal Userdata (`mmcblk0p56`)

The initial strategy was to wipe Samsung's encrypted FBE (File-Based Encryption) Android `userdata` partition and format it directly as native ext4:

```
/dev/block/mmcblk0p56 (eMMC Partition 56)
               │
               ▼
   [ mkfs.ext4 /dev/block/mmcblk0p56 ]
               │
               ▼
   [ Extract Manjaro ARM Root Filesystem ]
               │
               ▼
   Pass cmdline: "root=/dev/mmcblk0p56 rw rootwait"
```

### The Blocker:
When attempting to execute low-level block storage commands over ADB:
```bash
~ ❯ adb shell blockdev --getsize64 /dev/block/mmcblk0p56
blockdev: /dev/block/mmcblk0p56: Permission denied

~ ❯ adb root
adbd cannot run as root in production builds

~ ❯ adb shell su -c "tune2fs -l /dev/block/mmcblk0p56"
/system/bin/sh: su: inaccessible or not found
```

* The tablet had an **unlocked bootloader**, but was **not rooted** within Android userspace.
* Stock Samsung `adbd` is configured with strict production permissions and SELinux enforcement (`enforcing`).
* Without a custom recovery environment (like TWRP) to execute arbitrary shell scripts with root privilege, the internal eMMC could not be pre-formatted from the outside.

---

## 3. Plan B: External MicroSD Card Rootfs

To circumvent internal eMMC access restrictions, the project pivoted to an external high-speed MicroSD card.

### Imaged Target:
* **Image:** `Manjaro-ARM-kde-plasma-generic-23.02.img.xz`
* **Partition 1 (FAT32, ~487 MiB):** Boot partition containing Linux `Image`, `initramfs-linux.img`, and extlinux configurations.
* **Partition 2 (ext4, ~5.3 GiB):** Full Manjaro ARM userspace (Arch Linux package base, KDE Plasma, systemd).

### Partition UUID Verification:
Checking the MicroSD card block device on the host system:
```bash
sudo blkid /dev/sda2
# Output:
# /dev/sda2: UUID="f3a5..." PARTUUID="0930e7b6-3b48-4cc7-ae34-31e19515f1f4" TYPE="ext4"
```

Matching `extlinux.conf` verification:
```text
APPEND initrd=/initramfs-linux.img root=PARTUUID=0930e7b6-3b48-4cc7-ae34-31e19515f1f4 rw rootwait console=ttyS1,115200n8
```

### Hardware Complications:
1. **Host Card Reader Failure:** The physical SD card adapter was temporarily misplaced, exposing the limitation that modern Android MTP (`mtp://SAM...`) does not expose raw storage block devices to host Linux machines.
2. **Kernel SDHCI Probing:** Because `ums512-1h10.dtb` defines reference board SDIO nodes rather than the Galaxy Tab A8's specific regulator power pins (`vmmc-supply`, `vqmmc-supply`), the mainline kernel likely failed to power or initialize the MicroSD slot during boot, leaving `initramfs` unable to discover the root filesystem.
