# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2020-21, Intel Corporation.
#
# yuanmcdma.ko：Altera MCDMA 内核 netdev 驱动

ifneq ($(KERNELRELEASE),)
# kbuild part of makefile

ccflags-y += -O2
ccflags-y += -Wformat=2 -Wmissing-prototypes -Wstrict-prototypes -Wno-format-nonliteral
ccflags-y += -fstack-protector-strong -DFORTIFY_SOURCE=2 -DGENHDR_STRUCT

# Flags Prevent compiler from optimizing out security checks
# -fno-strict-overflow - Dont assume strict overflow does not occure
# -fno-delete-null-pointer - Dont delete NULL pointer checks
# -fwrapv - Signed integers wrapping may occure
ccflags-y += -fno-strict-overflow -fno-delete-null-pointer-checks -fwrapv
ccflags-y += -UDEBUG
ccflags-y += -UIFC_MCDMA_HEX_DUMP
ccflags-y += -DIFC_MCDMA_LB_CFG
ccflags-y += -UIFC_MCDMA_LB_DFLT_CFG
ccflags-y += -UIFC_MCDMA_HOL
ccflags-y += -UIFC_MCDMA_DEBUG
ccflags-y += -DIFC_QDMA_INTF_ST

ccflags-y += -DIFC_DATA_WIDTH=512
ccflags-y += -DMCDMA_ALIGN_ADDRESS
ccflags-y += -USKB_HEX_DUMP
ccflags-y += -DENABLE_DEBUGFS
ccflags-y += -DIFC_SELECT_QUEUE_ALGO
ccflags-y += -DIFC_MCDMA_X16
ccflags-y += -UIFC_MCDMA_BAS
ccflags-y += -DIFC_MCDMA_IOMMU_SUPPORT

ccflags-y += -I$(src)/../common/include -I$(src)/../../include

obj-m += yuanmcdma.o
yuanmcdma-y += ifc_mcdma_pci.o ifc_mcdma_net.o ifc_mcdma_ethtool.o ifc_mcdma_debugfs.o ifc_mcdma_ioctl.o ifc_mcdma_bas.o

else

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

install: all
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules_install

.PHONY: all clean install
endif
