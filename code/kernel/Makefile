#
# FPGA 网卡内核驱动：yuannic.ko、yuanmcdma.ko
#
#   make                          # 编译本机内核的 ko
#   make KDIR=/path/to/linux      # 指定内核源码/头文件目录
#   make clean
#

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
export KVER KDIR

SUBDIRS := mcdma yuannic_netdev
OUT     := $(CURDIR)/output

all:
	@for d in $(SUBDIRS); do $(MAKE) -C $$d all || exit 1; done
	@mkdir -p $(OUT)
	cp -f yuannic_netdev/yuannic.ko mcdma/mcdma_kmod/yuanmcdma.ko $(OUT)/

clean:
	@for d in $(SUBDIRS); do $(MAKE) -C $$d clean || exit 1; done
	rm -rf $(OUT)

.PHONY: all clean
