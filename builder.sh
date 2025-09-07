#!/usr/bin/env bash
# buildroot-py.sh — Build a BIOS-bootable “boots-to-Python” ISO for x86_64.
# Tested on Ubuntu-like environments (e.g., GitHub Codespaces).
set -euo pipefail

# -------- Settings you can tweak --------
BR_TAG="${BR_TAG:-2024.11}"        # A recent known-good Buildroot tag.
APP_NAME="${APP_NAME:-pyappliance}"
JOBS="${JOBS:-$(nproc)}"
# ---------------------------------------

echo "[*] Installing host deps (minimal, Buildroot builds most tools itself)…"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  git make gcc g++ build-essential bc bison flex libncurses-dev \
  unzip cpio rsync file wget gawk patch xz-utils python3 perl \
  genisoimage xorriso mtools dosfstools qemu-system-x86

# Workspace
ROOT="$(pwd)"
BR_DIR="${ROOT}/buildroot"
EXT_DIR="${ROOT}/${APP_NAME}-br"
mkdir -p "${EXT_DIR}"

if [ ! -d "${BR_DIR}" ]; then
  echo "[*] Cloning Buildroot ${BR_TAG}…"
  git clone --branch "${BR_TAG}" --depth=1 https://github.com/buildroot/buildroot.git "${BR_DIR}"
fi

echo "[*] Creating BR2_EXTERNAL tree…"
mkdir -p "${EXT_DIR}/configs" \
         "${EXT_DIR}/board/${APP_NAME}" \
         "${EXT_DIR}/board/${APP_NAME}/rootfs-overlay/app"

# -------- Your demo Python app (replace with your code later) --------
cat > "${EXT_DIR}/board/${APP_NAME}/rootfs-overlay/app/main.py" << 'PY'
#!/usr/bin/env python3
import os, socket, time, http.server, socketserver, threading

DATA = "/data"
os.makedirs(DATA, exist_ok=True)
with open(os.path.join(DATA, "hello.txt"), "a") as f:
    f.write(f"Boot OK at {time.ctime()}\n")

def ip_addrs():
    addrs = []
    for iface in os.listdir('/sys/class/net'):
        try:
            addrs.append((iface, open(f"/proc/net/fib_trie").read()))
        except Exception:
            pass
    return addrs

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            msg = "Hello from bare-min Linux Python!\n"
            msg += "Writing to /data/hello.txt and serving HTTP on :8080.\n"
            self.send_response(200); self.end_headers()
            self.wfile.write(msg.encode())
        else:
            super().do_GET()

def run_http():
    with socketserver.TCPServer(("", 8080), Handler) as httpd:
        httpd.serve_forever()

t = threading.Thread(target=run_http, daemon=True)
t.start()

print("HTTP server listening on 0.0.0.0:8080")
print("Try: curl http://<box-ip>:8080/")

# Keep foreground alive so you can watch logs on the serial console.
while True:
    time.sleep(60)
PY
chmod +x "${EXT_DIR}/board/${APP_NAME}/rootfs-overlay/app/main.py"

# If a local troll/main.py exists, copy it over the demo app
if [ -f "${ROOT}/troll/main.py" ]; then
  echo "[*] Using local troll/main.py for app…"
  install -m 0755 "${ROOT}/troll/main.py" "${EXT_DIR}/board/${APP_NAME}/rootfs-overlay/app/main.py"
fi

# -------- Minimal /init that boots to Python --------
cat > "${EXT_DIR}/board/${APP_NAME}/rootfs-overlay/init" << 'SH'
#!/bin/sh
# tiny init: mount basics, net via DHCP, mount /data if present, run /app/main.py
set -eux

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev || true
echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s

# Console quality-of-life
echo 0 > /proc/sys/kernel/printk
stty -F /dev/ttyS0 115200 || true

# Networking (assumes first NIC is eth0; busybox udhcpc is included)
ip link set lo up || true
ip link set eth0 up || true
udhcpc -i eth0 -q -t 5 -s /usr/share/udhcpc/default.script || true

# Mount a writable place for the app
mkdir -p /data
# If /dev/sda1 exists, try to mount it (ext4 or vfat), else use tmpfs
if [ -e /dev/sda1 ]; then
  mount -o rw /dev/sda1 /data 2>/dev/null || \
  mount -t vfat -o rw /dev/sda1 /data 2>/dev/null || \
  mount -t ext4 -o rw /dev/sda1 /data 2>/dev/null || \
  mount -t tmpfs tmpfs /data
else
  mount -t tmpfs tmpfs /data
fi

# Hand-off to your Python app
exec /usr/bin/python3 /app/main.py

# If the app exits, drop to a shell:
exec sh
SH
chmod +x "${EXT_DIR}/board/${APP_NAME}/rootfs-overlay/init"

# -------- Linux kernel config fragment: SATA + e1000/e1000e, console, ext4 --------
cat > "${EXT_DIR}/board/${APP_NAME}/linux.fragment" << 'KCFG'
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA=y
CONFIG_SATA_AHCI=y
CONFIG_ATA_PIIX=y
CONFIG_NETDEVICES=y
CONFIG_E1000=y
CONFIG_E1000E=y
CONFIG_VT=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_TTY=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_USE_FOR_EXT2=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_INET=y
CONFIG_IPV6=y
KCFG

# -------- External defconfig --------
cat > "${EXT_DIR}/configs/${APP_NAME}_defconfig" << 'DEF'
BR2_x86_64=y
BR2_KERNEL_HEADERS_6_1=y

# Toolchain
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_ENABLE_LOCALE=y

# Linux kernel (use latest known to Buildroot for the tag)
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_LATEST_VERSION=y
BR2_LINUX_KERNEL_USE_DEFCONFIG=y
BR2_LINUX_KERNEL_DEFCONFIG="x86_64_defconfig"
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="board/pyappliance/linux.fragment"
# Make sure serial console is visible in QEMU/real HW
BR2_LINUX_KERNEL_CUSTOM_CMDLINE="console=ttyS0,115200 console=tty0"

# BusyBox + core
BR2_PACKAGE_BUSYBOX=y

# Python
BR2_PACKAGE_PYTHON3=y
BR2_PACKAGE_PYTHON3_PIP=y

# Rootfs overlay with /init and /app/main.py
BR2_ROOTFS_OVERLAY="board/pyappliance/rootfs-overlay"

# Make a compressed initramfs (also used to produce the ISO)
BR2_TARGET_ROOTFS_CPIO=y
BR2_TARGET_ROOTFS_CPIO_GZIP=y

# Bootable ISO via Syslinux/isolinux (BIOS)
BR2_TARGET_SYSLINUX=y
BR2_TARGET_SYSLINUX_ISOLINUX=y
BR2_TARGET_SYSLINUX_SERIAL=y
BR2_TARGET_SYSLINUX_SERIAL_PORT=0
BR2_TARGET_SYSLINUX_SERIAL_SPEED=115200
BR2_TARGET_ROOTFS_ISO9660=y

# Strip, size wins
BR2_STRIP_strip=y
BR2_OPTIMIZE_S=y
DEF

# Patch BR2_EXTERNAL path inside fragment references
# (Buildroot resolves relative to BR2_EXTERNAL root, which we matched)
sed -i "s|board/pyappliance|board/${APP_NAME}|g" \
  "${EXT_DIR}/configs/${APP_NAME}_defconfig" \
  "${EXT_DIR}/board/${APP_NAME}/linux.fragment" || true

echo "[*] Kicking off Buildroot…"
cd "${BR_DIR}"
make BR2_EXTERNAL="${EXT_DIR}" "${APP_NAME}_defconfig"
make -j"${JOBS}"

echo
echo "=============================================="
echo "Build finished!"
echo "Kernel:      ${BR_DIR}/output/images/bzImage"
echo "Initramfs:   ${BR_DIR}/output/images/rootfs.cpio.gz"
echo "Bootable ISO:${BR_DIR}/output/images/rootfs.iso9660"
echo "=============================================="
echo
echo "To test in QEMU (BIOS, serial console):"
echo "  qemu-system-x86_64 \\"
echo "    -m 1024 -serial mon:stdio -nographic \\"
echo "    -cdrom output/images/rootfs.iso9660 \\"
echo "    -boot d -net nic,model=e1000e -net user"
echo
echo "On real hardware (OptiPlex 745):"
echo "  - Burn the ISO to a USB (e.g., 'dd if=rootfs.iso9660 of=/dev/sdX bs=4M status=progress')."
echo "  - Or use 'isohybrid' first if your tool requires it (xorriso usually handles this)."
echo
echo "At boot you'll see the Python app start and an HTTP server on port 8080."
echo "If you created an ext4 partition on /dev/sda1, your app will write to /data/hello.txt."
