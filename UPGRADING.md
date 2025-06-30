# Upgrading Talos
When a new version of Talos is released it may be necessary to adjust the patches we are applying to the upstream repositories.

1. Make sure you're starting from a clean slate
```
make clean
```
2. Update the versions in the _Makefile_ with the latest tag available in siderolabs repositories.
```
PKG_VERSION = vX.XX.X   <-- siderolabs/pkgs
TALOS_VERSION = vX.XX.X <-- siderolabs/talos
```
3. Clone all checkouts
```
make checkouts
```
4. Update patches as outlined bellow
5. Commit and push changes
```
git commit -am 'Talos upgrade to vX.XX.X'
git push
```
7. Create new tag
```
git tag vX.XX.X-rpi5
git push origin vX.XX.X-rpi5
```

## Pkgs
The [siderolabs/pkgs](https://github.com/siderolabs/pkgs) repository produces a set of packages which is used to build the rootfs. We are concerned about customizing the Kernel package, by using the the [raspberrypi/linux](https://github.com/raspberrypi/linux) kernel .

**TBD: Will be added next time the pkgs repository is updated**

## Talos
The [siderolabs/talos](https://github.com/siderolabs/talos) repository is where packages and Talos come together. We'll need to customise the list of available kernel modules to be copied in to the initramfs.

1. Try to apply the patches. If there are errors proceed to step 2, if not no further changes are needed.
```
make patches-pkgs
```
2. Manually add the required changes, commit and regenerate the patch. Essentially the _hack/modules-arm64.txt_ file needs to be overwritten with the one appropriate for the kernel build.
```
cd cd checkouts/talos
cp <updated modules-arm64.txt> hack/modules-arm64.txt
git commit -am '[PATCH] Patched for Raspberry Pi 5'
git format-patch --output-directory "../../patches/siderolabs/talos" HEAD~1
```
