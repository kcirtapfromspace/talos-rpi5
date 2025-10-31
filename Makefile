REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= wittenbude
PUSH ?= true

TAG ?= $(shell git describe --tags --exact-match)

EXTENSIONS ?= ghcr.io/siderolabs/iscsi-tools:v0.2.0

PKGS_TAG = $(shell cd checkouts/pkgs && git describe --tag --always --dirty --match v[0-9]\*)
TALOS_TAG = $(shell cd checkouts/talos && git describe --tag --always --dirty --match v[0-9]\*)
SBCOVERLAY_TAG = $(shell cd checkouts/sbc-raspberrypi5 && git describe --tag --always --dirty)-$(PKGS_TAG)

#
# Help
#
.PHONY: help
help:
	@echo "patches   : Apply all patches"
	@echo "kernel    : Build kernel"
	@echo "overlay   : Build Raspberry Pi 5 overlay"
	@echo "installer : Build installer docker image and disk image"
	@echo "release   : Use only when building the final release, this will tag relevant images with the current Git tag."
	@echo "clean     : Clean up any remains"



#
# Patches
#
.PHONY: patches-pkgs patches-talos patches
patches-pkgs:
	cd "checkouts/pkgs" && \
		git am "$(PWD)/patches/siderolabs/pkgs/0001-Patched-for-Raspberry-Pi-5.patch"

patches-talos:
	cd "checkouts/talos" && \
		git am "$(PWD)/patches/siderolabs/talos/0001-Patched-for-Raspberry-Pi-5.patch"

patches: patches-pkgs patches-talos



#
# Kernel
#
.PHONY: kernel
kernel:
	cd "checkouts/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PLATFORM=linux/arm64 \
			kernel



#
# Overlay
#
.PHONY: overlay
overlay:
	@echo SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)
	cd "checkouts/sbc-raspberrypi5" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=$(PUSH) \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			sbc-raspberrypi5



#
# Installer/Image
#
.PHONY: installer
installer:
	cd "checkouts/talos" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			IMAGER_ARGS="--overlay-name=rpi5 --overlay-image=$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG) $(foreach ext,$(EXTENSIONS),--system-extension-image=$(ext))" \
			kernel initramfs imager installer-base installer && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			metal --arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG)" \
			--overlay-name="rpi5" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG)" \
			$(foreach ext,$(EXTENSIONS),--system-extension-image="$(ext)")



#
# Release
#
.PHONY: release
release:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG)
