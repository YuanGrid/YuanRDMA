# YuanRDMA 安装指南

本文说明如何准备 YuanRDMA 研发与运行所需的软件环境，以及如何从源码编译出可用的固件、驱动和用户态软件包。

面向两类人：

- **开发者**：要改 RTL / 驱动 / provider，需要完整的编译与仿真环境。
- **用户**：只用已经发布好的固件与软件包，只需要驱动加载与测试环境。

一键安装脚本：`deploy/yuanrdma_install.sh`。它按本文第 2~6 节逐项安装，每步打印正在装什么、成功还是失败。先自检：

```bash
./deploy/yuanrdma_install.sh --check       # 只体检，不装任何东西
```

---

## 1. 环境要求

| 项 | 要求 | 说明 |
|---|---|---|
| 操作系统 | **Ubuntu 22.04 LTS x86_64** | 本项目只在 22.04 上验证过；其它发行版包名不同 |
| 内核 | `5.15.0-203-generic`（上板验证版本） | 驱动模块的 vermagic 必须与 `uname -r` 一致 |
| 架构 | x86_64 | — |
| 磁盘 | ≥ 60 GiB 空闲 | Quartus 编译工作目录约 40 GiB，CUDA 约 6 GiB |
| 权限 | root 或 sudo | 安装软件包、加载内核模块、烧写固件都需要 |

检查当前环境：

```bash
lsb_release -d && uname -r && uname -m && df -h /
```

---

## 2. 系统软件包

编译链、Python、RDMA、DPDK、内核头文件、调试工具，共 44 个包。脚本只装缺的：

```bash
sudo ./deploy/yuanrdma_install.sh --only apt
```

分组与用途：

| 组 | 包 | 用途 |
|---|---|---|
| 编译链 | `build-essential` `gcc-12` `g++-12` `make` `pkg-config` `git` `rsync` `bc` `unzip` `ccache` | provider / perftest / 内核模块 |
| Python | `python3` `python3-pip` `python3-dev` `python3-venv` `python3-lxml` `python3-pyelftools` | 仿真台子、`tool/` 脚本、DPDK 构建 |
| RDMA | `libibverbs-dev` `librdmacm-dev` `libnl-3-dev` `libnl-route-3-dev` `cmake` | rdma-core v66 编译 |
| DPDK | `meson` `ninja-build` `libnuma-dev` `libelf-dev` | `code/dpdk` 的 `net_mcdma` PMD |
| 内核 | `linux-headers-generic` + `linux-headers-$(uname -r)` | `code/kernel` 外部模块编译 |
| 调试 | `ethtool` `pciutils` `ipmitool` `tcpdump` `strace` `lsof` `psmisc` `procps` `xxd` `jq` | 上板排障、PFC/DCQCN 验证；`procps`（pgrep/pkill）与 `xxd` 供门禁与报文脚本使用 |

> **gcc-12 为什么必须装**：`code/kernel` 的外部模块编译会沿用内核的编译器。只装默认的 gcc-11，在部分内核配置下会失败。装完后编译内核模块可显式 `make CC=gcc-12`。

**内核头文件必须与运行内核同版本**，否则 `code/kernel` 编不过：

```bash
ls /usr/src/linux-headers-$(uname -r)     # 必须存在
```

---

## 3. Python 依赖（仿真必需）

cocotb 台子按 **cocotb 1.9 API** 编写，**不要升到 2.x**（2.x 移除了 `cocotb.result` 等模块，台子会直接导入失败）。

```bash
sudo pip3 install "cocotb==1.9.2" "cocotb-bus==0.3.0" "cocotbext-axi==0.1.28" scapy
```

| 包 | 版本 | 用途 |
|---|---|---|
| `cocotb` | 1.9.2 | 仿真框架 |
| `cocotb-bus` | 0.3.0 | 总线模型 |
| `cocotbext-axi` | 0.1.28 | roce_* 台子的 AXI 从机模型 |
| `scapy` | ≥2.4,<3 | `tool/` 下构造 RoCEv2 / PFC 原始帧 |

验证：

```bash
python3 -c "import cocotb, cocotb_bus, cocotbext.axi; import importlib.metadata as m; print(m.version('cocotb'), m.version('cocotbext-axi'))"
```

> 注意导入名与包名不同：`cocotb-bus` → `cocotb_bus`，`cocotbext-axi` → `cocotbext.axi`（子模块）。

---

## 4. Verilator（仿真必需，需 ≥ 5.0）

**apt 的 Verilator 4.038 不能用**——本仓库全部 cocotb 台子都开了 `--timing`，4.x 不支持这个开关。必须源码编译 5.032。

```bash
sudo ./deploy/yuanrdma_install.sh --only verilator
```

手工等价命令：

```bash
git clone --depth 1 -b v5.032 https://github.com/verilator/verilator
cd verilator
autoconf && ./configure --prefix=/opt/verilator
make -j"$(nproc)" && sudo make install
```

装到 `/opt/verilator` 不会自动进 `PATH`，需要：

```bash
echo 'export PATH=/opt/verilator/bin:$PATH' | sudo tee /etc/profile.d/verilator.sh
source /etc/profile.d/verilator.sh
```

验证：

```bash
verilator --version        # 应输出 Verilator 5.032
```

---

## 5. Quartus Prime Pro（仅编译固件需要）

**只做驱动 / 仿真 / 测试的话，这一节可以跳过。**

| 项 | 值 |
|---|---|
| 版本 | **Quartus Prime Pro 26.1.1** |
| 安装位置 | 本项目默认 `/home/quartus/program` |
| license | 默认 `/home/quartus/software/ALTERA_LICENSE/license_26.1.dat` |

Quartus 体积大且需要 license，**安装脚本不代为下载**。安装完成后设置环境变量：

```bash
export QUARTUS_ROOT=/home/quartus/program
export LM_LICENSE_FILE=/home/quartus/software/ALTERA_LICENSE/license_26.1.dat
```

验证：

```bash
$QUARTUS_ROOT/quartus/bin/quartus_sh --version
```

> **遇到 `Unknown device part AGIB...` 先查 license**，不是器件型号写错。

---

## 6. CUDA 12.4（仅 NCCL / GPUDirect 需要）

只做 RDMA 功能验证可以跳过。要做 NCCL 多卡通信或 GPUDirect RDMA 才需要。

| 项 | 值 |
|---|---|
| 版本 | **CUDA 12.4** |
| GPU 对应 | Tesla T4 = compute capability **7.5**，编译用 `NVCC_GENCODE=compute_75,sm_75` |
| 驱动要求 | ≥ 550.54.14（本机 580.178.04 满足） |

### 安装步骤

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-4
```

> ⚠️ **必须装 `cuda-toolkit-12-4`，不要装 `cuda` 或 `cuda-12-4`。**
> 后两者依赖 `cuda-drivers` 元包，会替换或升级现有显卡驱动，可能影响正在进行的编译与上板环境。

### 环境变量

```bash
sudo tee /etc/profile.d/cuda.sh >/dev/null <<'EOF'
export CUDA_HOME=/usr/local/cuda-12.4
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
EOF
source /etc/profile.d/cuda.sh
```

### 验证

```bash
nvcc --version                              # release 12.4
nvidia-smi                                  # 驱动版本未被改动
```

实际编译一次确认可用：

```bash
cd /tmp && cat > t.cu <<'EOF'
#include <cstdio>
int main(){int n=0;cudaGetDeviceCount(&n);cudaDeviceProp p;cudaGetDeviceProperties(&p,0);
printf("devices=%d name=%s cc=%d.%d\n",n,p.name,p.major,p.minor);return 0;}
EOF
nvcc -arch=sm_75 -o t t.cu && ./t
```

期望输出包含 `cc=7.5`。

---

## 7. NCCL 与 nccl-tests（可选）

仅做多卡集合通信验证时需要。依赖第 6 节的 CUDA。

```bash
# NCCL 2.22.3
git clone -b v2.22.3 https://github.com/NVIDIA/nccl.git
cd nccl
make -j src.build CUDA_HOME=/usr/local/cuda-12.4 \
     NVCC_GENCODE="-gencode=arch=compute_75,code=sm_75"

# nccl-tests v2.21.1
git clone -b v2.21.1 https://github.com/NVIDIA/nccl-tests.git
cd nccl-tests
make -j MPI=0 CUDA_HOME=/usr/local/cuda-12.4 \
     NCCL_HOME=$HOME/nccl/build \
     NVCC_GENCODE="-gencode=arch=compute_75,code=sm_75"
```

运行前需要的环境变量（本卡实测值）：

```bash
export NCCL_IB_HCA=yuanrdma0
export NCCL_IB_GID_INDEX=2        # 本卡实测值（不同平台的默认 index 不一样，必须显式指定）
export NCCL_SOCKET_IFNAME=eth0
export NCCL_NET_GDR_LEVEL=0       # 未装 nvidia_peermem，走 host 内存
export NCCL_P2P_DISABLE=1         # 单卡无 NVLink
export NCCL_IB_TIMEOUT=22
```

> **GPUDirect RDMA** 需要 `nvidia_peermem` 内核模块，默认不装。没有它 NCCL 会回退到 host 内存中转，功能可用但带宽低。

---

## 8. 编译本项目

环境就绪后，按依赖顺序编译。

### 8.1 用户态软件包（rdma-core + provider + perftest + 内核模块）

```bash
cd deploy
./yuannic_user_build.sh              # 全量：rdma-core v66 + provider + perftest + ko + 工具
./yuannic_user_build.sh --no-ko      # 只编用户态，不编内核模块
./yuannic_user_build.sh --clean      # 清理后重编
```

产物在 `build/user_tools/YuanNIC_User_Package/`，**不向系统路径安装任何文件**，与系统 DOCA 栈完全隔离：

```
YuanNIC_User_Package/
├── bin/        perftest + ibv_* + yuancli + ynictrl
├── lib/        libibverbs / librdmacm / libyuanrdma-rdmav65.so
├── include/    头文件
├── ko/         yuanrdma.ko / yuanmcdma.ko / yuannic.ko
├── env.sh      运行前 source，切换库与程序路径
├── tools/      flash_and_init.sh / roce_perf_test.sh
└── firmware/   最新一版固件：.jic（整片 flash）/ .rpd（在线升级）/ .sof（JTAG 临时加载）+ SHA256SUMS
```

`firmware/` 取自仓库根 `firmware/`（可用 `YUANNIC_FW_DIR` 指定），按「日期，再按 Build 号」选最新一版。
包内 `tools/flash_and_init.sh --flash <镜像名>` 直接在包内 `firmware/` 里找镜像，配置 flash 器件为 MX66U2G。

每次使用前：

```bash
source build/user_tools/YuanNIC_User_Package/env.sh
```

### 8.2 FPGA 固件

**需要第 5 节的 Quartus。**

```bash
cd build/YuanNIC-NH400-C
./yuannic_build.sh <VER> <BUILD> 1X400G [all|boot|active]
# 例：./yuannic_build.sh 26.12.02 0116 1X400G all
```

| 参数 | 含义 |
|---|---|
| `VER` | 版本号，如 `26.12.16` |
| `BUILD` | 构建号，如 `6457` |
| `1X400G` | 配置（单口 400G） |
| `all` / `boot` / `active` | 编哪个工程；`all` 额外合成含 Factory + Release 双镜像的 `.jic` |

产物（`.sof` / `.rpd` / `.jic`）归档到仓库根 `firmware/`。全量编译约 **2~2.5 小时**。

C 卡同理，在 `build/YuanNIC-NH400-C/` 下执行。

---

## 9. 上板

> ⚠️ 烧写会覆盖板上镜像，且可能让卡掉出 PCIe 总线需要冷断电。脚本要求**显式加开关**才烧写。

```bash
cd deploy

# 不烧写，只重新拉起驱动与网络（日常最常用）
./flash_and_init.sh

# 烧 flash（.jic，掉电保持）
./flash_and_init.sh --flash B6456

# 烧 SRAM（.sof，掉电回退到 flash 里那版，调试用）
./flash_and_init.sh --sram B6456
```

烧写前的固件检查：

```bash
tool/pre_flash_check.sh --with-ynictrl
```

### 验证链路

```bash
ibv_devinfo -d yuanrdma0          # 应看到 PORT_ACTIVE，rate 400 Gb/sec
ip link show eth0                 # 应 UP
ping -c 3 <对端 IP>
```

### 跑性能测试

```bash
cd deploy
PEER_PASS=<对端密码> ./roce_perf_test.sh --label B6457
```

必须显式给出 `PEER_PASS`（无内置默认值）。测试结果按 Gbps 记录。

---

## 10. 一键安装与自检

```bash
sudo ./deploy/yuanrdma_install.sh                 # 装全部
sudo ./deploy/yuanrdma_install.sh --only apt      # 只装系统包
sudo ./deploy/yuanrdma_install.sh --skip-cuda     # 不做 NCCL 的机器
./deploy/yuanrdma_install.sh --check              # 只体检
./deploy/yuanrdma_install.sh --dry-run            # 只打印计划
./deploy/yuanrdma_install.sh -h                   # 完整用法
```

脚本行为：

- **幂等**：已装的跳过并标注「已存在」，可重复执行。
- **只装缺的**：先 `dpkg -s` 求差集，不重复下载。
- **缺什么直接 apt 装**，不手工下载第三方包。
- **失败不吞**：每步记录状态，末尾汇总；有失败退出码 1。
- **不烧写、不动 BMC、不改厂商固件。**

退出码：`0` 全部成功 / `1` 有步骤失败 / `2` 用法或环境错误。

---

## 11. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `make` 编 `code/kernel` 报编译器错误 | 缺 gcc-12 或内核头不匹配 | 装 `gcc-12`，确认 `/usr/src/linux-headers-$(uname -r)` 存在 |
| `Unknown device part AGIB...` | 缺 license 或版本不符 | 检查 `LM_LICENSE_FILE`，确认 Quartus 是 26.1.1 |
| `ibv_devinfo` 看不到设备 | 驱动未加载 / 固件不匹配 | `./flash_and_init.sh`，再查 `dmesg \| grep yuanrdma` |
| 装了 CUDA 后 `nvidia-smi` 异常 | 误装了 `cuda` 元包改动了驱动 | 重装 `nvidia-driver-580-server`，以后只装 `cuda-toolkit-12-4` |
| `nvcc: command not found` | 环境变量未持久化 | 按第 6 节写 `/etc/profile.d/cuda.sh` 并重新登录 |

---

## 12. 相关文档

| 文档 | 内容 |
|---|---|
| [README.md](README.md) | 项目总览、特性、架构 |
| [deploy/yuanrdma_install.sh](deploy/yuanrdma_install.sh) | 一键安装脚本（第 10 节） |
