# ============================================================================
# YuanNIC 开源组件构建入口
#
# 只负责**编译**本目录下 vendored 的开源组件，不做产品打包、不烧写、不往系统
# 路径安装（verilator 的 install-verilator 除外，需显式调用）。
# 产品打包仍走 deploy/yuannic_user_build.sh。
#
# 组件与来源：
#   rdma-core   v66       CMake + Ninja，默认注入 code/rdmasw 的 yuanrdma provider
#   perftest    6.31      autotools，对着上面编出的 rdma-core 编
#   nccl        v2.22.3   make，需要 CUDA
#   nccl-tests  v2.21.1   make，需要 CUDA + 已编好的 nccl
#   verilator   5.032     autoconf/configure，系统已有 >=5.0 时默认跳过
#   surf / blue-rdma      RTL 参考工程，无编译，只读
#
# 用法：
#   make                    # 编译全部可用组件（缺工具链的自动跳过，不报错）
#   make perftest           # 只编 perftest（会自动先编 rdma-core）
#   make rdma-core          # 只编 rdma-core + yuanrdma provider
#   make nccl nccl-tests    # 只编 NCCL 相关（需要 CUDA）
#   make verilator          # 编 Verilator（已装 >=5.0 时跳过，VERILATOR_FORCE=1 强制）
#   make install-verilator  # 把编出的 Verilator 装到 VERILATOR_PREFIX（默认 /opt/verilator）
#   make list               # 组件清单：版本、源码、产物
#   make check              # 体检工具链与已编产物
#   make clean              # 删除 build/（全部中间目录与产物）
#   make clean-perftest     # 只清一个组件，其余同理
#
# 产物统一落在 code/github/build/<组件>/，不进 git（.gitignore 的 /code/github/*
# 已覆盖本目录，只有 rdma-core / perftest / nccl-tests 三个源码树是白名单）。
#
# 常用变量（可写在命令行或环境里）：
#   JOBS=8                      并行度，默认 nproc
#   CUDA_HOME=/usr/local/cuda   CUDA 根目录，默认 /usr/local/cuda
#   NCCL_GENCODE=...            NVCC 的 -gencode，默认 compute_75,sm_75（Tesla T4）
#   NCCL_TESTS_MPI=1            编 nccl-tests 时带 MPI（需 MPI_HOME）
#   WITH_PROVIDER=0             编「干净」的 rdma-core，不注入 yuanrdma provider
#   VERILATOR_FORCE=1           系统已有 verilator 也强制重编 vendored 那份
#   VERILATOR_PREFIX=/opt/verilator   install-verilator 的目标路径
#   SUDO=sudo                   install-verilator 需要 root 时用
#
# 版本锁定：
#   源码树已经在仓库里（code/github/），本 Makefile **不下载、不切分支**。
#   要换上游版本就换源码树本身，并同步改这里注释里的版本号。
# ============================================================================

SHELL := /bin/bash
.SUFFIXES:
.DEFAULT_GOAL := all

GITHUB := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ROOT   := $(abspath $(GITHUB)/../..)
BUILD  := $(GITHUB)/build

JOBS ?= $(shell nproc)

# ---------------------------------------------------------------- 源码位置
RDMACORE_SRC := $(GITHUB)/rdma-core
PERFTEST_SRC := $(GITHUB)/perftest
NCCL_SRC     := $(GITHUB)/nccl
NCCLT_SRC    := $(GITHUB)/nccl-tests
VERI_SRC     := $(GITHUB)/verilator

# provider 注入源（只在本仓库里，不存在时 WITH_PROVIDER=1 会报错退出）
PROVIDER     := $(ROOT)/code/rdmasw/rdma-core-provider/yuanrdma
HW_HEADER    := $(ROOT)/code/rdmasw/include/yuanrdma_hw.h
ABI_HEADER   := $(ROOT)/code/kernel/yuanrdma/yuanrdma_abi_defs.h

# ---------------------------------------------------------------- 产物位置
RDMA_C_DIR   := $(BUILD)/rdma-core
RDMA_C_OUT   := $(RDMA_C_DIR)/src
RDMA_C_BDIR  := $(RDMA_C_OUT)/build
RDMA_C_INST  := $(RDMA_C_DIR)/install
RDMA_C_STAMP := $(RDMA_C_DIR)/.stamp

PT_DIR       := $(BUILD)/perftest
PT_OUT       := $(PT_DIR)/src
PT_INST      := $(PT_DIR)/install
PT_STAMP     := $(PT_DIR)/.stamp

NCCL_DIR     := $(BUILD)/nccl
NCCL_OUT     := $(NCCL_DIR)/src
NCCL_BDIR    := $(NCCL_OUT)/build
NCCL_STAMP   := $(NCCL_DIR)/.stamp

NCCLT_DIR    := $(BUILD)/nccl-tests
NCCLT_OUT    := $(NCCLT_DIR)/src
NCCLT_BIN    := $(NCCLT_DIR)/bin
NCCLT_STAMP  := $(NCCLT_DIR)/.stamp

VERI_DIR     := $(BUILD)/verilator
VERI_OUT     := $(VERI_DIR)/src
VERI_INST    := $(VERI_DIR)/install
VERI_STAMP   := $(VERI_DIR)/.stamp

# ---------------------------------------------------------------- 工具链
CMAKE   ?= $(shell command -v cmake 2>/dev/null)
NINJA   := $(shell command -v ninja 2>/dev/null)
RSYNC   := $(shell command -v rsync 2>/dev/null)
CUDA_HOME ?= /usr/local/cuda
NVCC    := $(shell command -v nvcc 2>/dev/null || { [ -x "$(CUDA_HOME)/bin/nvcc" ] && echo "$(CUDA_HOME)/bin/nvcc"; })

NCCL_GENCODE   ?= -gencode=arch=compute_75,code=sm_75
NCCL_TESTS_MPI ?= 0
MPI_HOME       ?=
WITH_PROVIDER  ?= 1
VERILATOR_FORCE ?= 0
VERILATOR_PREFIX ?= /opt/verilator
SUDO ?=

# 系统里已有 verilator 且 >= 5.0 时记下版本，verilator 目标据此跳过
HAVE_VERILATOR := $(shell command -v verilator >/dev/null 2>&1 && \
    verilator --version 2>/dev/null | awk '$$2+0 >= 5.0 {print $$2}')

# ---------------------------------------------------------------- 通用
define say
printf '\n\033[1m==> %s\033[0m\n' "$(1)"
endef

.PHONY: all rdma-core perftest nccl nccl-tests verilator install-verilator \
        list check clean clean-rdma-core clean-perftest clean-nccl \
        clean-nccl-tests clean-verilator rebuild help

# ============================================================================
# all：按依赖顺序逐个编，缺工具链的组件由各自目标打印后跳过
# ============================================================================
all:
	@$(MAKE) --no-print-directory rdma-core
	@$(MAKE) --no-print-directory perftest
	@$(MAKE) --no-print-directory nccl
	@$(MAKE) --no-print-directory nccl-tests
	@$(MAKE) --no-print-directory verilator
	@echo
	@echo "全部完成。产物在 $(BUILD)/<组件>/，用 'make list' 看路径。"

# ============================================================================
# rdma-core（默认注入 yuanrdma provider）
# ============================================================================
rdma-core: $(RDMA_C_STAMP)

$(RDMA_C_STAMP): | $(RDMA_C_DIR)
	@$(call say,rdma-core)
	@[ -n "$(RSYNC)" ] || { echo "缺少 rsync（apt install rsync）"; exit 1; }
	@[ -n "$(CMAKE)" ] && [ -n "$(NINJA)" ] || { echo "缺少 cmake/ninja（apt install cmake ninja-build）"; exit 1; }
	@test -d "$(RDMACORE_SRC)" || { echo "找不到源码树 $(RDMACORE_SRC)"; exit 1; }
	rsync -a --delete --exclude .git --exclude .git_upstream "$(RDMACORE_SRC)/" "$(RDMA_C_OUT)/"
	@if [ "$(WITH_PROVIDER)" = "1" ]; then \
	    test -d "$(PROVIDER)"   || { echo "缺少 provider：$(PROVIDER)"; exit 1; }; \
	    test -f "$(HW_HEADER)"  || { echo "缺少 $(HW_HEADER)"; exit 1; }; \
	    test -f "$(ABI_HEADER)" || { echo "缺少 $(ABI_HEADER)"; exit 1; }; \
	    rm -rf "$(RDMA_C_OUT)/providers/yuanrdma"; \
	    cp -a "$(PROVIDER)" "$(RDMA_C_OUT)/providers/yuanrdma"; \
	    cp "$(ABI_HEADER)" "$(RDMA_C_OUT)/kernel-headers/rdma/yuanrdma-abi.h"; \
	    cp "$(HW_HEADER)"  "$(RDMA_C_OUT)/providers/yuanrdma/yuanrdma_hw.h"; \
	    grep -q 'add_subdirectory(providers/yuanrdma)' "$(RDMA_C_OUT)/CMakeLists.txt" || \
	        sed -i 's#^add_subdirectory(providers/erdma)$$#add_subdirectory(providers/erdma)\nadd_subdirectory(providers/yuanrdma)#' \
	            "$(RDMA_C_OUT)/CMakeLists.txt"; \
	    grep -q 'rdma/yuanrdma-abi.h' "$(RDMA_C_OUT)/kernel-headers/CMakeLists.txt" || \
	        sed -i 's#^  rdma/erdma-abi.h$$#  rdma/erdma-abi.h\n  rdma/yuanrdma-abi.h#' \
	            "$(RDMA_C_OUT)/kernel-headers/CMakeLists.txt"; \
	    grep -q 'add_subdirectory(providers/yuanrdma)' "$(RDMA_C_OUT)/CMakeLists.txt" \
	        || { echo "provider 注册失败（CMakeLists.txt）"; exit 1; }; \
	    grep -q 'rdma/yuanrdma-abi.h' "$(RDMA_C_OUT)/kernel-headers/CMakeLists.txt" \
	        || { echo "ABI 头注册失败（kernel-headers/CMakeLists.txt）"; exit 1; }; \
	    echo "   已注入 yuanrdma provider"; \
	else \
	    echo "   WITH_PROVIDER=0：编干净 rdma-core，不含 yuanrdma provider"; \
	fi
	@mkdir -p "$(RDMA_C_BDIR)"
	@cd "$(RDMA_C_BDIR)" && \
	    "$(CMAKE)" -GNinja \
	        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
	        -DNO_MAN_PAGES=1 \
	        -DNO_PYVERBS=1 \
	        -DENABLE_RESOLVE_NEIGH=0 \
	        -DENABLE_STATIC=0 \
	        -DCMAKE_INSTALL_PREFIX="$(RDMA_C_INST)" \
	        .. && \
	    ninja -j "$(JOBS)"
	@touch $@
	@echo "   rdma-core 完成：$(RDMA_C_BDIR)/lib"

$(RDMA_C_DIR):
	@mkdir -p $@

# ============================================================================
# perftest（对着上面编出的 rdma-core 编，不碰系统 DOCA/OFED 那套）
# ============================================================================
perftest: $(PT_STAMP)

$(PT_STAMP): $(RDMA_C_STAMP) | $(PT_DIR)
	@$(call say,perftest)
	rsync -a --delete --exclude .git --exclude .git_upstream "$(PERFTEST_SRC)/" "$(PT_OUT)/"
	@test -x "$(PT_OUT)/autogen.sh" || { echo "perftest 源码不完整（缺 autogen.sh）"; exit 1; }
	@cd "$(PT_OUT)" && ./autogen.sh
	@cd "$(PT_OUT)" && \
	    CPPFLAGS="-I$(RDMA_C_BDIR)/include" \
	    LDFLAGS="-L$(RDMA_C_BDIR)/lib -Wl,-rpath,$(RDMA_C_BDIR)/lib" \
	    LD_LIBRARY_PATH="$(RDMA_C_BDIR)/lib$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	    ./configure --prefix="$(PT_INST)" --enable-option-checking=fatal
	@$(MAKE) -C "$(PT_OUT)" -j "$(JOBS)"
	@$(MAKE) -C "$(PT_OUT)" install
	@touch $@
	@echo "   perftest 完成：$(PT_INST)/bin（rpath 已指向 $(RDMA_C_BDIR)/lib）"

$(PT_DIR):
	@mkdir -p $@

# ============================================================================
# nccl（需要 CUDA）
# ============================================================================
nccl:
ifeq ($(strip $(NVCC)),)
	@echo
	@echo "==> nccl：跳过（未找到 nvcc，见 INSTALL.md 第 6 节）"
else
	@$(MAKE) --no-print-directory $(NCCL_STAMP)
endif

$(NCCL_STAMP): | $(NCCL_DIR)
	@$(call say,nccl)
	rsync -a --delete --exclude .git --exclude .git_upstream "$(NCCL_SRC)/" "$(NCCL_OUT)/"
	$(MAKE) -C "$(NCCL_OUT)" -j "$(JOBS)" src.build \
	    CUDA_HOME="$(CUDA_HOME)" NVCC_GENCODE="$(NCCL_GENCODE)"
	@touch $@
	@echo "   nccl 完成：$(NCCL_BDIR)/lib/libnccl.so"

$(NCCL_DIR):
	@mkdir -p $@

# ============================================================================
# nccl-tests（需要 CUDA + nccl）
# ============================================================================
nccl-tests:
ifeq ($(strip $(NVCC)),)
	@echo
	@echo "==> nccl-tests：跳过（未找到 nvcc，见 INSTALL.md 第 6 节）"
else
	@$(MAKE) --no-print-directory $(NCCLT_STAMP)
endif

$(NCCLT_STAMP): $(NCCL_STAMP) | $(NCCLT_DIR)
	@$(call say,nccl-tests)
	rsync -a --delete --exclude .git --exclude .git_upstream "$(NCCLT_SRC)/" "$(NCCLT_OUT)/"
	$(MAKE) -C "$(NCCLT_OUT)" -j "$(JOBS)" \
	    MPI="$(NCCL_TESTS_MPI)" \
	    $(if $(MPI_HOME),MPI_HOME="$(MPI_HOME)",) \
	    CUDA_HOME="$(CUDA_HOME)" \
	    NCCL_HOME="$(NCCL_BDIR)" \
	    NVCC_GENCODE="$(NCCL_GENCODE)" \
	    BUILDDIR="$(NCCLT_BIN)"
	@touch $@
	@echo "   nccl-tests 完成：$(NCCLT_BIN)/all_reduce_perf 等"

$(NCCLT_DIR):
	@mkdir -p $@

# ============================================================================
# verilator（系统已有 >=5.0 时默认跳过）
# ============================================================================
verilator:
ifeq ($(VERILATOR_FORCE),1)
	@$(MAKE) --no-print-directory $(VERI_STAMP)
else ifneq ($(strip $(HAVE_VERILATOR)),)
	@echo
	@echo "==> verilator：跳过（系统已有 $(HAVE_VERILATOR)，VERILATOR_FORCE=1 可强制重编）"
else
	@$(MAKE) --no-print-directory $(VERI_STAMP)
endif

$(VERI_STAMP): | $(VERI_DIR)
	@$(call say,verilator)
	rsync -a --delete --exclude .git --exclude .git_upstream "$(VERI_SRC)/" "$(VERI_OUT)/"
	@cd "$(VERI_OUT)" && autoconf && ./configure --prefix="$(VERI_INST)"
	@$(MAKE) -C "$(VERI_OUT)" -j "$(JOBS)"
	@touch $@
	@echo "   verilator 完成：$(VERI_OUT)/bin/verilator"
	@echo "   安装到系统用：make install-verilator"

$(VERI_DIR):
	@mkdir -p $@

install-verilator: $(VERI_STAMP)
	@$(call say,安装 verilator 到 $(VERILATOR_PREFIX))
	@cd "$(VERI_OUT)" && $(SUDO) $(MAKE) install prefix="$(VERILATOR_PREFIX)"
	@echo "   验证：$(VERILATOR_PREFIX)/bin/verilator --version"
	@echo "   PATH 若未包含该目录：export PATH=$(VERILATOR_PREFIX)/bin:\$$PATH"

# ============================================================================
# 辅助
# ============================================================================
list:
	@echo "组件        版本        源码                          产物"
	@printf '%-12s %-11s %-29s %s\n' "rdma-core"  "v66"      "code/github/rdma-core"      "$(RDMA_C_BDIR)/lib"
	@printf '%-12s %-11s %-29s %s\n' "perftest"   "6.31"     "code/github/perftest"       "$(PT_INST)/bin"
	@printf '%-12s %-11s %-29s %s\n' "nccl"       "v2.22.3"  "code/github/nccl"           "$(NCCL_BDIR)/lib"
	@printf '%-12s %-11s %-29s %s\n' "nccl-tests" "v2.21.1"  "code/github/nccl-tests"     "$(NCCLT_BIN)"
	@printf '%-12s %-11s %-29s %s\n' "verilator"  "5.032"    "code/github/verilator" "$(VERI_OUT)/bin"
	@echo
	@echo "surf / blue-rdma 是 RTL 参考工程，无编译目标。"

check:
	@echo "工具链"
	@printf '  %-10s %s\n' cmake     "$(if $(CMAKE),$(CMAKE),缺失)"
	@printf '  %-10s %s\n' ninja     "$(if $(NINJA),$(NINJA),缺失)"
	@printf '  %-10s %s\n' rsync     "$(if $(RSYNC),$(RSYNC),缺失)"
	@printf '  %-10s %s\n' nvcc      "$(if $(NVCC),$(NVCC),缺失)"
	@printf '  %-10s %s\n' verilator "$(if $(HAVE_VERILATOR),$(HAVE_VERILATOR),缺失或 <5.0)"
	@echo "已编产物"
	@for p in "$(RDMA_C_STAMP)" "$(PT_STAMP)" "$(NCCL_STAMP)" "$(NCCLT_STAMP)" "$(VERI_STAMP)"; do \
	    if [ -f "$$p" ]; then echo "  [OK]   $$p"; else echo "  [--]   $$p"; fi; \
	done

clean-rdma-core:
	rm -rf "$(RDMA_C_DIR)"
clean-perftest:
	rm -rf "$(PT_DIR)"
clean-nccl:
	rm -rf "$(NCCL_DIR)"
clean-nccl-tests:
	rm -rf "$(NCCLT_DIR)"
clean-verilator:
	rm -rf "$(VERI_DIR)"

clean:
	rm -rf "$(BUILD)"

rebuild: clean
	@$(MAKE) --no-print-directory all

help:
	@sed -n '2,44p' $(MAKEFILE_LIST) | sed 's/^# \{0,1\}//'
