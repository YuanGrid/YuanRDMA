# SPDX-License-Identifier: GPL-2.0
# yuanrdma.ko：YuanNIC-NH400-B RoCEv2 引擎的 ib_core 驱动（依赖 yuanmcdma.ko 提供的 PCI/netdev）

ifneq ($(KERNELRELEASE),)
obj-m := yuanrdma.o
yuanrdma-y := yuanrdma_main.o yuanrdma_verbs.o yuanrdma_gsi.o yuanrdma_cq_event.o
ccflags-y += -I$(src)/../../rdmasw/include -Wall
else
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
CC   ?= gcc-12

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) CC=$(CC) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
endif
