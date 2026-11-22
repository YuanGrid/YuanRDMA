#
# FPGA 网卡 DPDK 驱动（net/mcdma）
#
# 流程：下载官方 dpdk-25.11.2 -> 拷入 drivers/net/mcdma -> 打 patches/ -> meson/ninja 编译 -> 安装到 output/
#
#   make                         # 编译并安装到 output/
#   make CPU_SET=core-avx-i      # 指定 -Dcpu_instruction_set（默认 native，只保证本机可用）
#   make DPDK_TARBALL=/path/xx   # 离线时使用本地 tarball
#   make clean                   # 删除 build/ 和 output/
#   make distclean               # 额外删除下载的 tarball
#

DPDK_VER     := 25.11.2
DPDK_SHA256  := 418bfe3212640ee95a1cb10af6ed360cad2387686fe2721f8a3a9cd02d5ef4f2
DPDK_URL     := https://fast.dpdk.org/rel/dpdk-$(DPDK_VER).tar.xz

TOP          := $(CURDIR)
DL_DIR       := $(TOP)/dl
BUILD_DIR    := $(TOP)/build
SRC_DIR      := $(BUILD_DIR)/dpdk-stable-$(DPDK_VER)
MESON_DIR    := $(SRC_DIR)/build
OUT          := $(TOP)/output
DPDK_TARBALL ?= $(DL_DIR)/dpdk-$(DPDK_VER).tar.xz

CPU_SET      ?= native
DRIVERS      := bus/pci,bus/vdev,mempool/ring,net/mcdma
APPS         := test-pmd

MESON_CFG := --buildtype=release
MESON_CFG += -Dprefix=$(OUT) -Dlibdir=lib
MESON_CFG += -Dcpu_instruction_set=$(CPU_SET)
MESON_CFG += -Denable_drivers=$(DRIVERS)
MESON_CFG += -Denable_apps=$(APPS)
MESON_CFG += -Dtests=false -Dexamples= -Denable_docs=false

PATCHES := $(sort $(wildcard $(TOP)/patches/*.patch))
PMD_SRC := $(shell find $(TOP)/drivers -type f)

all: $(BUILD_DIR)/.installed

$(DL_DIR)/dpdk-$(DPDK_VER).tar.xz:
	mkdir -p $(DL_DIR)
	curl -fSL -o $@.tmp $(DPDK_URL)
	mv $@.tmp $@

$(BUILD_DIR)/.extracted: $(DPDK_TARBALL)
	echo "$(DPDK_SHA256)  $(DPDK_TARBALL)" | sha256sum -c -
	rm -rf $(SRC_DIR)
	mkdir -p $(BUILD_DIR)
	tar -xf $(DPDK_TARBALL) -C $(BUILD_DIR)
	cd $(SRC_DIR) && for p in $(PATCHES); do echo "apply $$(basename $$p)"; patch -p1 -s < $$p || exit 1; done
	touch $@

# PMD 源码改动后重新同步到 DPDK 源码树
$(BUILD_DIR)/.synced: $(BUILD_DIR)/.extracted $(PMD_SRC)
	rm -rf $(SRC_DIR)/drivers/net/mcdma
	cp -r $(TOP)/drivers/net/mcdma $(SRC_DIR)/drivers/net/
	touch $@

$(BUILD_DIR)/.configured: $(BUILD_DIR)/.synced
	rm -rf $(MESON_DIR)
	cd $(SRC_DIR) && meson setup $(MESON_CFG) build
	touch $@

$(BUILD_DIR)/.installed: $(BUILD_DIR)/.configured FORCE
	ninja -C $(MESON_DIR)
	meson install -C $(MESON_DIR) --quiet
	install -m 0755 $(SRC_DIR)/usertools/dpdk-devbind.py $(OUT)/bin/dpdk-devbind.py
	touch $@

clean:
	rm -rf $(BUILD_DIR) $(OUT)

distclean: clean
	rm -rf $(DL_DIR)

FORCE:
.PHONY: all clean distclean FORCE
