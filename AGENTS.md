# AGENTS.md - Task Delegation for Talos RPi5 Builds

This file defines agent configurations for common tasks in the Talos RPi5 build workflow.

## Build Agents

### kernel-builder

**Purpose:** Build and push kernel package with cache invalidation.

**Steps:**
1. Clear Docker build cache
2. Build kernel for arm64
3. Push to local registry
4. Report kernel image tag

**Commands:**
```bash
docker builder prune -af && \
cd checkouts/pkgs && \
gmake kernel PLATFORM=linux/arm64 PUSH=true REGISTRY=localhost:5001 USERNAME=wittenbude
```

### imager-builder

**Purpose:** Build Talos imager with custom kernel.

**Prerequisites:** kernel-builder must complete first.

**Steps:**
1. Get kernel tag from pkgs checkout
2. Build imager with custom kernel reference
3. Push to local registry

**Commands:**
```bash
cd checkouts/talos && \
gmake imager PLATFORM=linux/arm64 PUSH=true REGISTRY=localhost:5001 USERNAME=wittenbude \
  PKG_KERNEL=localhost:5001/wittenbude/kernel:$(cd ../pkgs && git describe --tag --always --dirty)
```

### image-builder

**Purpose:** Generate bootable metal image for RPi5.

**Prerequisites:** imager-builder must complete first.

**Steps:**
1. Run imager container with RPi5 overlay
2. Output compressed raw image to _out/

**Commands:**
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

## User-Assisted Tasks

These tasks require physical access or sudo privileges. The agent provides commands; the user executes them.

### flash-sd-card

**Purpose:** Flash built image to SD card.

**User Actions Required:**
1. Insert SD card
2. Identify disk device
3. Execute flash command with sudo

**Commands to Provide:**
```bash
# Step 1: Identify disk
diskutil list

# Step 2: Unmount (user replaces diskN)
diskutil unmountDisk /dev/diskN

# Step 3: Flash (user replaces rdiskN)
zstd -d -c _out/metal-arm64.raw.zst | sudo dd of=/dev/rdiskN bs=4m status=progress

# Step 4: Eject
diskutil eject /dev/diskN
```

### uart-monitor

**Purpose:** Monitor serial console output from RPi5.

**User Actions Required:**
1. Connect UART adapter
2. Start screen/picocom session

**Commands to Provide:**
```bash
# Start logging session (user identifies serial device)
screen -L -Logfile /tmp/uart.log /dev/cu.usbserial-* 115200

# Or in a separate terminal, tail the logs
tail -f /tmp/uart.log
```

### apply-worker-config

**Purpose:** Apply Talos worker configuration to node in maintenance mode.

**Prerequisites:**
- Node must be booted and in maintenance mode
- Node IP must be known (from DHCP or UART logs)

**Commands:**
```bash
talosctl apply-config --insecure --nodes <NODE_IP> --file _out/worker.yaml
```

## Background Task Pattern

For long-running builds, use the background task pattern:

1. **Agent starts build in background**
2. **User monitors UART logs** in separate terminal
3. **Agent checks build output** periodically
4. **User confirms physical actions** (insert SD, power cycle, etc.)

### Example Workflow

```
Agent: Starting kernel build in background...
       [Bash command runs with run_in_background=true]

Agent: Build running. Meanwhile, please:
       1. Connect UART adapter to RPi5
       2. Run: screen -L -Logfile /tmp/uart.log /dev/cu.usbserial-* 115200

User: UART connected

Agent: [Checks build output]
       Build complete. Image ready at _out/metal-arm64.raw.zst

       Flash the SD card:
       diskutil unmountDisk /dev/disk4
       zstd -d -c _out/metal-arm64.raw.zst | sudo dd of=/dev/rdisk4 bs=4m status=progress

User: Flashed, booting now

Agent: [Reads /tmp/uart.log to monitor boot progress]
```

## Kernel Config Agent

### kernel-config-checker

**Purpose:** Verify kernel config has correct settings for RPi5.

**Checks:**
- `CONFIG_ARM64_4K_PAGES=y` (not 16K)
- `CONFIG_MMC_SDHCI_PLTFM=y` (built-in)
- `CONFIG_MMC_SDHCI_BRCMSTB=y` (built-in)
- `CONFIG_MACB=y` (ethernet)

**File:** `checkouts/pkgs/kernel/build/config-arm64`

## Registry Publishing Agent

### ghcr-publisher

**Purpose:** Push images to ghcr.io for RPi5 access.

**Prerequisites:**
- GitHub CLI authenticated
- write:packages scope enabled

**Commands:**
```bash
# Ensure auth has packages scope
gh auth refresh -h github.com -s write:packages

# Login to ghcr.io
gh auth token | docker login ghcr.io -u USERNAME --password-stdin

# Tag and push
docker tag localhost:5001/wittenbude/installer:TAG ghcr.io/USERNAME/talos-rpi5-installer:TAG
docker push ghcr.io/USERNAME/talos-rpi5-installer:TAG
```

## Troubleshooting Agent

### boot-debugger

**Purpose:** Diagnose boot failures from UART logs.

**Input:** UART log file path (e.g., `/tmp/uart.log`)

**Checks:**
1. BL31/ATF messages - early boot
2. U-Boot initialization
3. Kernel decompression and start
4. SD card detection (`mmc0: new`)
5. Root filesystem mount
6. Talos machined startup
7. Network interface initialization

**Common Patterns:**
- Crash at BL31 → 16K pages issue
- No mmc0 messages → SD driver not built-in
- EINVAL on mount → 16K pages + Talos mount API incompatibility
- No eth0 activity → Ethernet driver issue (known problem with 4K pages)
