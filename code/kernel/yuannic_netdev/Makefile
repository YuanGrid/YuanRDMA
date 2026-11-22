# SPDX-License-Identifier: GPL-2.0
#
# yuannic.ko：FPGA 网卡基础字符设备/netdev 模块（源自 Supernova kernel/modules/yuannic_netdev）
#

ifneq ($(KERNELRELEASE),)

obj-m += yuannic.o
yuannic-objs := yuannic_netdev.o

ccflags-y := -O3 -Wall -g -std=gnu99
ccflags-y += -I$(src) -I$(src)/onic -I$(src)/../include
ccflags-y += -I$(src)/../mcdma/mcdma_kmod -I$(src)/../mcdma/common/include

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
