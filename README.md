# pyappliance — Boots-to-Python Buildroot Image

This project produces a **minimal Linux appliance** for x86-64 that
boots directly into a Python script.  
It is designed for **BIOS-era hardware** like the Dell OptiPlex 745
(no UEFI required).

---

## Features

- **Tiny footprint** using [Buildroot](https://buildroot.org/)  
- **Linux kernel + BusyBox + Python 3**
- **BIOS boot via Syslinux/isolinux**
- **Disk support**: SATA (ICH8/PIIX/AHCI), ext4, FAT  
- **Networking**: Intel e1000/e1000e NICs with DHCP
- **Persistent storage**: mounts `/dev/sda1` as `/data` (if present)
- **Demo app**:
  - Writes to `/data/hello.txt`
  - Serves a simple HTTP endpoint on port **8080**

---

## Quick Start

### Build inside GitHub Codespaces (or Linux host)

```sh
git clone https://github.com/<yourname>/pyappliance.git
cd pyappliance
bash buildroot-py.sh
```

The first build will take some time (toolchains).  
When finished, you’ll find:

- Kernel: `buildroot/output/images/bzImage`
- Initramfs: `buildroot/output/images/rootfs.cpio.gz`
- Bootable ISO: `buildroot/output/images/rootfs.iso9660`

---

## Run in QEMU

```sh
cd buildroot
qemu-system-x86_64   -m 1024 -serial mon:stdio -nographic   -cdrom output/images/rootfs.iso9660   -boot d   -net nic,model=e1000e -net user
```

You should see the Python app boot and an HTTP server start:

```text
HTTP server listening on 0.0.0.0:8080
Try: curl http://127.0.0.1:8080/
```

---

## Run on Real Hardware (OptiPlex 745)

1. Burn the ISO to a USB stick:

   ```sh
   sudo dd if=buildroot/output/images/rootfs.iso9660 of=/dev/sdX bs=4M status=progress
   sync
   ```

   Replace `/dev/sdX` with your USB device.

2. Boot the PC from the USB (BIOS boot).  
3. (Optional) Create an **ext4 partition** as `/dev/sda1` for persistent storage.  
   The init script will mount it at `/data`.

---

## Customizing

- **Your Python app**: edit `board/pyappliance/rootfs-overlay/app/main.py`
- **Boot sequence**: edit `board/pyappliance/rootfs-overlay/init`
- **Kernel config fragment**: see `board/pyappliance/linux.fragment`
- **Buildroot defconfig**: see `configs/pyappliance_defconfig`

Run `make menuconfig` inside the `buildroot` directory if you want to
tweak options manually.

---

## Requirements

- Ubuntu-like host (or GitHub Codespaces)
- `make`, `gcc`, `qemu-system-x86`, and other basic build deps
  (the script installs them for you)

---

## Roadmap / Ideas

- Add SSL/TLS support (`BR2_PACKAGE_PYTHON3_SSL`)
- Build with [musl](https://musl.libc.org/) instead of glibc for smaller size
- Package extra Python modules (via Buildroot packages or `pip`)
- Support for additional NICs or storage drivers

---

## License

MIT — do what you like, but attribution is appreciated.
