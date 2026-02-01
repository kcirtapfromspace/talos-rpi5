# Talos Linux on Raspberry Pi 5 - Troubleshooting Summary

## Executive Summary

We are attempting to run Talos Linux v1.12.1 on a Raspberry Pi 5 to join an existing Kubernetes cluster. The effort has hit a fundamental incompatibility between the RPi5's hardware requirements and Talos's software architecture.

**The Core Problem**: RPi5 requires 16K memory pages for networking, but Talos's mount system fails on 16K page kernels.

## Current State

| Configuration | Kernel | Pages | Networking | Talos Boot |
|--------------|--------|-------|------------|------------|
| RPi kernel (wittenbude) | 6.12.25 | 16K | ✅ Works | ❌ Shadow bind mount EINVAL |
| Official Talos kernel | 6.18.6 | 4K | ❌ No NIC activity | ✅ Boots cleanly |

## Technical Background

### Why RPi5 Needs 16K Pages
- The RP1 chip (south bridge handling Ethernet, USB, GPIO) uses the STMMAC/MACB driver
- Raspberry Pi Foundation's `bcm2712_defconfig` defaults to 16K pages
- The network DMA buffers appear to require 16K alignment

### Why Talos Fails on 16K Pages
- Talos v1.12 uses the new Linux mount API (`open_tree`, `move_mount` syscalls)
- The `open_tree(OPEN_TREE_CLONE)` syscall returns `EINVAL` on 16K page kernels
- This affects shadow bind mounts for `/etc/hosts`, `/etc/resolv.conf`, CRI configs
- Similar issue documented: k3s doesn't support 16K pages (issue #7335)

### Why 4K Pages Break Networking
- Mainline kernel 6.18.x has RP1 pinctrl support but networking doesn't initialize
- Possible causes:
  - RPi DTB files incompatible with mainline's PCIe-based RP1 discovery
  - Missing platform-specific driver initialization
  - Rev 1.1 boards may need kernel 6.19+

## What We Tried

### Attempt 1: wittenbude Patches + 16K Pages
- Applied patches from wittenbude/talos-rpi5 for v1.11.x
- Updated to Talos v1.12.1 codebase
- Built with RPi kernel 6.12.25 (16K pages)
- **Result**: NIC lights on, but Talos loops on shadow bind mount errors

### Attempt 2: Clear Cache + Rebuild
- Discovered Docker buildx was caching old kernel
- Cleared all buildx cache, rebuilt entire stack
- **Result**: Same shadow bind mount errors

### Attempt 3: Official Talos Kernel + 4K Pages
- Used upstream siderolabs/pkgs with kernel 6.18.6
- Includes official RPi5 pinctrl support (CONFIG_PINCTRL_RP1, CONFIG_PINCTRL_BCM2712)
- Added RPi5 firmware/DTB files manually
- **Result**: Talos boots cleanly, but no network (NIC lights off)

## Issue Filed

GitHub Issue: https://github.com/wittenbude/talos-rpi5/issues/7

---

# PRD: Additional Troubleshooting Steps

## Objective

Identify a working configuration to run Talos v1.12.x on Raspberry Pi 5 with functional networking.

## Priority Order

### P0: Quick Wins (< 1 day effort)

#### 1. Test Kernel 6.19+ with 4K Pages
**Hypothesis**: Mainline 6.19 has better RPi5 rev 1.1 support including proper DTB files.

**Steps**:
1. Update siderolabs/pkgs to use kernel 6.19.x
2. Verify bcm2712d0-rpi-5-b.dts is included
3. Build and test with 4K pages
4. Check if NIC initializes

**Success Criteria**: NIC lights on, DHCP address obtained

#### 2. Use Mainline DTB Files Instead of RPi DTB
**Hypothesis**: RPi DTB files expect RPi kernel behavior, mainline DTB expects PCIe discovery.

**Steps**:
1. Extract DTB files from mainline kernel build (not RPi firmware)
2. Replace RPi DTB files in boot partition
3. Test with official Talos kernel 6.18.6

**Success Criteria**: NIC initializes with mainline DTB

#### 3. Test with RPi5 Rev 1.0 Board
**Hypothesis**: Rev 1.0 (4GB) has better mainline support than rev 1.1 (16GB).

**Steps**:
1. Obtain RPi5 rev 1.0 board
2. Test official Talos kernel build
3. Compare behavior

**Success Criteria**: Determine if issue is rev-specific

### P1: Medium Effort (1-3 days)

#### 4. Debug 16K Page EINVAL
**Hypothesis**: The EINVAL can be traced to a specific kernel code path.

**Steps**:
1. Add debug logging to Talos mount code
2. Build custom kernel with VFS debugging enabled
3. Capture full dmesg and strace of failing syscall
4. Identify exact kernel function returning EINVAL
5. Check if it's a kernel bug or expected behavior

**Success Criteria**: Root cause identified, potential fix path known

#### 5. Test Fallback Mount Implementation
**Hypothesis**: Talos could fall back to traditional bind mounts on 16K kernels.

**Steps**:
1. Modify `internal/pkg/mount/v3/mount.go` to catch EINVAL
2. Implement fallback to `MS_BIND` mount syscall
3. Test with 16K page kernel

**Success Criteria**: Shadow bind mounts work via fallback

#### 6. Enable RP1 Debug Logging
**Hypothesis**: The RP1/MACB driver is failing silently on 4K pages.

**Steps**:
1. Enable kernel debug for MACB, RP1, PCIe drivers
2. Boot with `loglevel=7 dyndbg="+p"`
3. Capture full dmesg
4. Identify where network initialization fails

**Success Criteria**: Specific driver failure identified

### P2: High Effort (3-7 days)

#### 7. Backport RP1 Ethernet Patches
**Hypothesis**: Specific patches from RPi kernel enable networking on 4K pages.

**Steps**:
1. Identify ethernet-related commits in raspberrypi/linux
2. Extract patches for MACB/RP1 ethernet
3. Apply to mainline 6.18.6
4. Build and test

**Success Criteria**: Networking works with 4K pages + backported patches

#### 8. Engage Siderolabs Directly
**Hypothesis**: Siderolabs may have internal knowledge or roadmap for RPi5.

**Steps**:
1. File issue on siderolabs/talos about 16K page incompatibility
2. Reference their pinctrl commit showing RPi5 work
3. Ask about official RPi5 support timeline
4. Propose collaboration on fix

**Success Criteria**: Guidance from Siderolabs on recommended approach

#### 9. Build Hybrid Kernel
**Hypothesis**: Combine RPi5 networking patches with 4K page configuration.

**Steps**:
1. Start with RPi kernel 6.12.x source
2. Force CONFIG_ARM64_4K_PAGES=y
3. Test if networking still works
4. If not, identify which patches require 16K pages

**Success Criteria**: Identify minimum patch set for 4K networking

### P3: Long-term / Research

#### 10. Contribute 16K Page Fix to Talos
**Hypothesis**: The mount API issue can be fixed upstream.

**Steps**:
1. Reproduce issue in minimal test case
2. Identify if kernel or userspace fix needed
3. Submit PR to siderolabs/talos or Linux kernel
4. Work through review process

**Success Criteria**: Fix merged upstream

#### 11. Monitor Upstream Progress
**Hypothesis**: This will be fixed by natural kernel/Talos evolution.

**Steps**:
1. Watch siderolabs/pkgs for RPi5 commits
2. Monitor Linux kernel for RP1/BCM2712 updates
3. Test new releases as they come out

**Success Criteria**: Working build from upstream without custom patches

## Resources Required

- Raspberry Pi 5 (ideally both rev 1.0 and rev 1.1)
- Serial debug probe for early boot debugging
- Time for kernel compilation cycles (~15-30 min each)
- GitHub access for issue tracking

## Decision Points

1. **If P0 items succeed**: Use that configuration, document for community
2. **If P0 items fail**: Proceed to P1 debugging
3. **If 16K page fix is simple**: Contribute upstream
4. **If no fix found**: Wait for upstream support or use different SBC

## Timeline Estimate

- P0 items: 1-2 days
- P1 items: 3-5 days
- P2 items: 1-2 weeks
- P3 items: Ongoing

## Current Recommendation

Start with **P0 #1 (Kernel 6.19+)** as it requires minimal effort and addresses known rev 1.1 compatibility issues mentioned in forum posts.
