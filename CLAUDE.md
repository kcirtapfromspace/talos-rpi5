# CLAUDE.md - Talos RPi5 Build Workflow

This file documents the build workflow and rules for creating Talos Linux images for Raspberry Pi 5.

## Architecture Overview

```
checkouts/
├── pkgs/          # Kernel and package builds
├── talos/         # Talos imager and configs
└── sbc-raspberrypi5/  # RPi5-specific overlay
```

## Build Commands

All builds use the local Docker registry at `localhost:5001`.

### 1. Clear Build Cache (Required Before Rebuilds)

Cache invalidation is critical - Docker buildx aggressively caches layers.

```bash
docker builder prune -af
```

### 2. Build Kernel Package

```bash
cd checkouts/pkgs && \
gmake kernel PLATFORM=linux/arm64 \
  PUSH=true \
  REGISTRY=localhost:5001 \
  USERNAME=wittenbude
```

### 3. Build Talos Imager

```bash
cd checkouts/talos && \
gmake imager PLATFORM=linux/arm64 \
  PUSH=true \
  REGISTRY=localhost:5001 \
  USERNAME=wittenbude \
  PKG_KERNEL=localhost:5001/wittenbude/kernel:$(cd ../pkgs && git describe --tag --always --dirty)
```

### 4. Build Bootable Image

```bash
cd checkouts/talos && \
docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged \
  localhost:5001/wittenbude/imager:$(git describe --tag --always --dirty) \
  metal --arch arm64 \
  --board=rpi_generic \
  --overlay-name=rpi5 \
  --overlay-image=ghcr.io/siderolabs/sbc-raspberrypi:v0.1.1 \
  --extra-kernel-arg="console=tty1" \
  --extra-kernel-arg="console=ttyAMA10,115200" \
  --system-extension-image=ghcr.io/siderolabs/iscsi-tools:v0.1.10
```

Output: `_out/metal-arm64.raw.zst`

## Flash Commands (Require sudo)

### Decompress and Flash to SD Card

```bash
# macOS - identify disk first
diskutil list

# Unmount (replace diskN with actual disk)
diskutil unmountDisk /dev/diskN

# Flash (use rdiskN for raw device, faster)
zstd -d -c _out/metal-arm64.raw.zst | sudo dd of=/dev/rdiskN bs=4m status=progress

# Eject
diskutil eject /dev/diskN
```

## UART Serial Console

RPi5 requires UART for boot debugging. The kernel args above enable console output.

### Monitor UART Logs

```bash
# Start logging (run in separate terminal)
screen -L -Logfile /tmp/uart.log /dev/cu.usbserial-* 115200

# Or with picocom
picocom -b 115200 /dev/cu.usbserial-*
```

### Tail Logs While Booting

```bash
tail -f /tmp/uart.log
```

## Key Kernel Configuration (config-arm64)

These settings are critical for RPi5 boot and SD card detection:

```
# Memory pages - MUST be 4K for Talos boot
CONFIG_ARM64_4K_PAGES=y
# CONFIG_ARM64_16K_PAGES is not set

# SD card drivers - MUST be built-in (=y), not modules (=m)
CONFIG_MMC_SDHCI_PLTFM=y
CONFIG_MMC_SDHCI_BRCMSTB=y

# Ethernet (MACB driver for RP1)
CONFIG_MACB=y
CONFIG_PHYLIB=y
CONFIG_PHYLINK=y
CONFIG_BROADCOM_PHY=y
```

## Worker Node Configuration

The worker config (`_out/worker.yaml`) must specify:

```yaml
machine:
  install:
    disk: /dev/mmcblk0  # SD card path on RPi5
    image: ghcr.io/kcirtapfromspace/talos-rpi5-installer:v1.12.1-sd-fix
```

### Apply Config to Node in Maintenance Mode

```bash
talosctl apply-config --insecure \
  --nodes <node-ip> \
  --file _out/worker.yaml
```

## Publishing to ghcr.io

For images that need to be pulled by the RPi5 (can't reach localhost):

```bash
# Authenticate with write:packages scope
gh auth refresh -h github.com -s write:packages
gh auth token | docker login ghcr.io -u USERNAME --password-stdin

# Tag and push
docker tag localhost:5001/wittenbude/installer:TAG ghcr.io/USERNAME/talos-rpi5-installer:TAG
docker push ghcr.io/USERNAME/talos-rpi5-installer:TAG
```

## Docker Buildx Builder

Use `desktop-linux` builder for access to host networking (localhost:5001):

```bash
docker buildx use desktop-linux
```

The `local-multiarch` builder runs in a container and cannot reach the host's localhost.

## Known Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Boot crash at BL31 | 16K memory pages | Use `CONFIG_ARM64_4K_PAGES=y` |
| `/dev/mmcblk0` not found | SD driver as module | Set `CONFIG_MMC_SDHCI_BRCMSTB=y` |
| Kernel changes not applied | Build cache | Run `docker builder prune -af` |
| Can't push to localhost:5001 | Wrong builder | Use `docker buildx use desktop-linux` |
| No ethernet on RPi5 | 4K pages + RP1 driver | Known issue - see TROUBLESHOOTING_SUMMARY.md |

## Debugging Checklist

1. Always clear cache before rebuild: `docker builder prune -af`
2. Watch UART logs during boot: `tail -f /tmp/uart.log`
3. Verify SD card driver loaded: look for `mmc0: new` in UART output
4. Check disk path matches config: `lsblk` in maintenance mode
5. Verify installer image is accessible by RPi5 (use ghcr.io if needed)
