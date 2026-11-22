# 源码在仓库里是 code/ynictrl/（原来在 Supernova 的 daemon/dpdk_net/nictrl/）。
# ynic_net_base.h 已拷进本目录 include/，编译自包含，不依赖仓库外路径。
# 产物：本目录下的 ynictrl。rdma_build.sh 会把它拷到 roce_nic/。

CC ?= gcc

CFLAGS += -Wall -g
#CFLAGS += -std=c99
CFLAGS += -std=gnu99
CFLAGS += -I./include -I./common -I./100g -I./10g -I./xfast -I./400g
CFLAGS += -I./
CFLAGS += -DNDEBUG

# 定义链接选项
LDFLAGS += -lm

# 定义目标文件
TARGET = ynictrl

# 定义源文件和对象文件
SRC = $(wildcard *.c)
SRC += $(wildcard common/*.c)
#SRC += $(wildcard 100g/*.c)
SRC += $(wildcard 10g/*.c)
SRC += $(wildcard xfast/*.c)
SRC += $(wildcard 400g/*.c)
OBJS = $(patsubst %.c,%.o,$(SRC))


# 默认目标
all: build_version.h $(TARGET)

# get_revision.sh 依赖 svn；仓库里没有 svn 工作副本，直接保留已有的 build_version.h。
# （原脚本取不到版本号时会写 "unknown"，这里等价于那个结果，且不依赖 svn 命令。）
build_version.h:
	@[ -f build_version.h ] || printf '#ifndef SVN_REVISION_H\n#define SVN_REVISION_H\n#define SVN_REVISION "unknown"\n#endif\n' > build_version.h
# 链接目标文件
$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

# 编译源文件
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# 清理生成的文件
clean:
	rm -f $(OBJS) build_version.h $(TARGET)
.PHONY: all clean
