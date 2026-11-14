# chopin-linux —— 顶层编排
SHELL := /bin/bash
TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
KERNEL := $(TOP)/kernel
DEBIAN := $(TOP)/debian

.PHONY: all help bootstrap check kernel debian bootimg artifacts clean distclean

all: check

help:
	@echo "make bootstrap   初始化 submodule，并从 v7.3.4 重建内核源码"
	@echo "make kernel      编译内核（Image.gz + dtbs + modules）"
	@echo "sudo make debian 构建 Debian rootfs + GNOME + initramfs + 镜像 + boot.img"
	@echo "make bootimg     只重新打包 boot.img（需要 stock/boot_a.img）"
	@echo "make check       校验补丁/校验和/脚本语法/内核 tree"
	@echo "make artifacts   汇总产物到 out/ 并生成 SHA256SUMS"
	@echo "make clean       删除 out/、debian/build/、debian/out/"
	@echo "make distclean   再删除 kernel/linux/（可用 bootstrap 恢复）"

bootstrap:
	$(TOP)/scripts/bootstrap.sh

check:
	$(TOP)/scripts/check.sh

kernel:
	@if [ ! -d $(KERNEL)/linux ]; then $(MAKE) -C $(KERNEL) bootstrap; fi
	$(MAKE) -C $(KERNEL) build

debian:
	$(MAKE) -C $(DEBIAN) build

bootimg:
	$(MAKE) -C $(DEBIAN) bootimg

artifacts:
	$(TOP)/scripts/collect-artifacts.sh

clean:
	$(MAKE) -C $(KERNEL) clean
	$(MAKE) -C $(DEBIAN) clean

distclean:
	$(MAKE) -C $(KERNEL) distclean
	$(MAKE) -C $(DEBIAN) distclean
	rm -rf $(TOP)/out
