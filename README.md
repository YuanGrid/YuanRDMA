# 垣易 YuanGrid / YuanRDMA

简体中文 | [English](README.en.md)

<p align="center">
  <img src="docs/logo/YuanRDMA.png" alt="YuanRDMA" width="880">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ETHERNET-400G-612B9B?style=flat-square&labelColor=B48B2E" alt="ETHERNET 400G">
  <img src="https://img.shields.io/badge/PCIE-GEN5%20X16-612B9B?style=flat-square&labelColor=B48B2E" alt="PCIE GEN5 X16">
  <img src="https://img.shields.io/badge/FPGA-AGILEX%207%20I-612B9B?style=flat-square&labelColor=B48B2E" alt="FPGA AGILEX 7 I">
  <img src="https://img.shields.io/badge/QUARTUS%20PRIME-26.1.1-612B9B?style=flat-square&labelColor=B48B2E" alt="QUARTUS PRIME 26.1.1">
  <img src="https://img.shields.io/badge/RDMA-ROCEv2%20RC%20%7C%20UD-612B9B?style=flat-square&labelColor=B48B2E" alt="RDMA RoCEv2 RC | UD">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/UBUNTU-22.04-612B9B?style=flat-square&labelColor=B48B2E" alt="UBUNTU 22.04">
  <img src="https://img.shields.io/badge/DOCA-3.5.0-612B9B?style=flat-square&labelColor=B48B2E" alt="DOCA 3.5.0">
  <img src="https://img.shields.io/badge/CUDA-12.4-612B9B?style=flat-square&labelColor=B48B2E" alt="CUDA 12.4">
  <img src="https://img.shields.io/badge/NCCL-2.22.3-612B9B?style=flat-square&labelColor=B48B2E" alt="NCCL 2.22.3">
  <img src="https://img.shields.io/badge/NCCL--TESTS-v2.21.1-612B9B?style=flat-square&labelColor=B48B2E" alt="NCCL-TESTS v2.21.1">
  <img src="https://img.shields.io/badge/RDMA--CORE-v66-612B9B?style=flat-square&labelColor=B48B2E" alt="RDMA-CORE v66">
</p>

YuanRDMA 是垣易科技（YuanGrid）研发的基于 FPGA 的 400G RoCEv2 RDMA 智能网卡，产品型号为 **YuanNIC**。它在 FPGA 中原生集成 RDMA 传输引擎，对主机呈现为一块标准 RDMA 设备：通过标准 `libibverbs` / `rdma-core` provider 接入，原版 perftest 不改代码即可运行，并与 NVIDIA ConnectX-7 网卡在同一网络中双向互通，面向 AI 集群、高速互联、低时延存储与智能卸载等场景。

YuanNIC 具备面向高速互联的硬件链路时序优化与协议卸载能力，支持线速报文处理、超低传输时延、400G 高速光口、可编程协议卸载、PFC 无损网络与 DCQCN 拥塞控制。项目覆盖从 RTL、固件构建、Linux 内核驱动、用户态 provider 到仿真验证与上板测试工具链的完整软硬件栈。

> 本仓库是 YuanNIC 的开源工程，以 Apache-2.0 协议开放 RTL、驱动与工具源码；编译产出 FPGA 固件与用户态库供最终用户使用。

## 系统架构

### 板内数据通路

主机侧只有 WQE 提交与 CQE 收取穿过 PCIe，数据面报文从 F-tile MAC 进出、在引擎内完成组包与解析，不经过主机软件栈。

![YuanNIC 板内数据通路](docs/image/on-card-datapath.png)

自下而上：400G QSFP-112 经 F-tile Ethernet Hard IP（MAC + PCS + RS-FEC）进出；流量管理做优先级队列、PFC 门控与 RX 分类（RoCE UDP 4791 走引擎，其余交 netdev）；RoCEv2 传输引擎负责 TX 组包与 RX 解析、PSN 与重传、ICRC 生成校验，以及 DCQCN 的 RP 限速与 CNP 生成；主机接口维护 doorbell、QPC / CQC 表、MR / MTT 翻译缓存与 CQ / EQ；DMA 层用 AXI MCDMA 的 BAM（CSR / doorbell）、BAS（引擎主动取 WQE、写 CQE）与 MCDMA（netdev）把两侧接起来。

### 通信控制路径

一次 RDMA 操作从应用提交到对端可用的完整路径如下。三条控制路径并存：常规 verbs（CPU 构建并提交 WQE）、IBGDA（GPU 自己写门铃发起）、GPUDirect RDMA（GPU 显存与网卡之间直接搬运，不经 CPU 中转）。应用侧不需要区分——三者共用同一套 verbs 语义和完成队列。

![YuanNIC 控制路径与数据路径](docs/image/control-path.png)

1. 应用调用 `ibv_post_send`，在主机内存构建 WQE，写入 SQ 并敲 doorbell（BAR2 UAR 页，WC 映射）。
2. 网卡 DMA 取 WQE，按 QPC 校验 `lkey / rkey`，经 MTT 翻译成物理地址。
3. 引擎组包：BTH / RETH / AETH / DETH + payload + ICRC，按 PFC 门控与 DCQCN 令牌桶放行。
4. 报文经 400GbE 发往对端；对端按 PSN 排序、落内存，硬件回 ACK / NAK；拥塞时交换机打 ECN，对端回 CNP。
5. 完成后网卡把 CQE 写回主机内存，应用轮询 CQ 取完成，按 `wr_id` 归还缓冲。
6. RDMA Write 的对端内存由网卡直接写，对端 CPU 不参与；Send 由网卡写入 RQ 缓冲后才产生 CQE。
7. GPU 场景：显存做 `dma-buf` MR 注册后，数据直达显存；IBGDA 则由 GPU 侧写门铃，把 CPU 从提交路径上摘掉。


## 应用场景

1. **AI 训练与推理集群的网络底座**：大模型训练的多机通信（AllReduce / AllGather / ReduceScatter）本质上是 GPU 显存之间的大批量数据搬运，也是决定集群有效算力的关键变量。YuanNIC 走标准 verbs 接口，NCCL 自带的 IB verbs 插件零改造即可运行；多 QP 并行下发把 4 QP 的发送方向推到 352 Gb/s，配合 PFC 无损与 DCQCN 拥塞控制，在共享以太交换网上守住 collective 带宽的确定性。192 卡以上的集群，通信占比往往是迭代时间的大头——可编程网卡让拥塞控制参数与重传策略随集群规模动态调整，把网络从"不可控的瓶颈"变成"可规划的算力延伸"。
2. **超低时延存储与分布式文件系统**：RDMA Read / Write 绕过内核协议栈，单次写时延约 2.2 µs；128 个 QP、单个 MR 最大 512 MiB 的规格，足以承载 NVMe-oF 前端与分布式 KV / 对象存储的数据面。KVCache 卸载、参数服务器这类"一块大 buffer 反复写远端"的负载，正是 Write with Immediate 加完成队列异步流水的最优形态。存储与计算的边界由此被重新划定——远端内存的访问代价被压缩到接近本地。
3. **GPU 显存直连与推理服务的 KVCache 互通**：GPUDirect RDMA（dma-buf MR 注册）让数据不经主机内存中转直达显存；P/D 分离推理中 KV Cache 在节点间搬运，这条路径省掉两次拷贝。IBGDA 让 GPU 自己写门铃发起请求，把 CPU 从每次通信的提交路径上彻底摘除。两项均已实现，上板验证在路线图中——它们共同指向一个方向：通信从"CPU 代劳"演进为"设备自主"，为未来万卡级推理集群铺路。
4. **无损以太与智算网络测试**：400GbE 单口、PFC 按优先级门控、ECN + DCQCN 全寄存器可配，既能验证交换机在 PFC / ECN 场景下的真实行为，也能作为测试仪表的对端网卡。超大规模智算网络的稳定性，最终取决于无损以太链路上每一个参数的确定性——而这正是可编程硬件最擅长的事。
5. **可编程协议卸载与研究平台**：RTL、驱动、provider、仿真台全部在本仓库，改协议字段、改拥塞控制算法、改重传策略都只需重编固件；cocotb 仿真台与编译前门禁让改动能先离线验证再上板。硬件不再是一次性固化的黑盒，而是可持续演进的协议载体——面向 RDMA、拥塞控制与 FPGA 网络加速，这正是下一代数据中心网络创新的基座。

## 主要特性

**RDMA 传输**

- QP 建立：支持两种建链方式——RoCE CM（借助内核驱动经 QP1 / GSI 交换 CM MAD，即标准 `rdma_cm` 路径）与 TCP 交换建链信息（NCCL、perftest 一类走 verbs 自己交换 QP 信息的路径，不依赖 CM）。
- QP 规模：默认 128 个 QP，`QP_NUM` 参数化，可扩展到 4096；QPN 落在基址对齐的连续窗口内，软件侧 `FROCE_MAX_QP` / `FROCE_QPN_BASE` 与 RTL 同步。
- RoCEv2 RC 传输：RDMA Write / Write with Immediate / Read / Send / Send with Immediate，硬件实现 PSN、ACK/NAK、Go-back-N 重传与超时定时器。
- RoCEv2 UD 传输（Send / Send with Immediate，带 DETH），CQE 回报源 QPN。
- ICRC 硬件生成与校验。

**资源规模**

- 默认 128 个 QP（可扩展到 4096）、64 个 CQ，SQ / RQ 深度 4096，CQ 深度最高 32768。
- MTT 131072 项，单个 MR 最大 512 MiB；硬件实现 lkey / rkey 校验与地址翻译缓存。
- GPUDirect RDMA：支持 dma-buf MR 注册（`ibv_reg_dmabuf_mr`，内核 ≥ 6.2，待上板验证）。

**无损网络与拥塞控制**

- PFC（IEEE 802.1Qbb）：按优先级的发送准入门控，配合 F-tile 硬核 MAC 完成 PFC 帧收发。
- DCQCN：RP / NP / CNP 完整实现，覆盖全部 QP（当前 128 个，随 `QP_NUM` 扩展），参数全部寄存器可配。

**主机接口与软件栈**

- PCIe Gen5 x16（Altera R-tile）+ AXI MCDMA，doorbell / WQE 取指 / CQE 写回全部硬件完成。
- Linux 内核驱动 `yuanrdma.ko`（接入 `ib_core`），以太网驱动 `yuannic.ko`。
- rdma-core v66 provider `libyuanrdma`，与系统 DOCA 栈隔离共存。
- DPDK PMD `net_mcdma`（基于 DPDK 25.11.2）。
- 运维诊断工具：`rdmacli`（PFC / DSCP / ECN、DCQCN 参数配置，寄存器与计数器诊断，卡死现场快照）、`nictrl`（网卡管理）。

## 性能

测试条件：YuanNIC-NH400-A，对端 NVIDIA ConnectX-7，400GbE 直连，原版 perftest，消息 1 MiB、每项 30 s。

| 用例 | FPGA 作客户端 | FPGA 作服务端 |
|---|---|---|
| `ib_write_bw`（1 QP） | 141.8 Gb/s（35.5%） | 97.9 Gb/s（24.5%） |
| `ib_read_bw`（1 QP） | 77.2 Gb/s（19.3%） | 89.8 Gb/s（22.5%） |
| `ib_send_bw`（1 QP） | 147.0 Gb/s（36.8%） | 98.5 Gb/s（24.6%） |
| `ib_write_bw`（4 QP） | **352.1 Gb/s（88.0%）** | — |
| `ib_read_bw`（4 QP） | — | **328.2 Gb/s（82.1%）** |

括号内为占总带宽（400 Gb/s 线速）的百分比。多 QP 并发时发送方向达到线速的 88%、接收方向 82%；单 QP 受每包组包开销限制，约 36%，这也是需要多 QP 并行下发的原因。

时延（typical）：`ib_write_lat` 约 **2.2 µs**，`ib_read_lat` / `ib_send_lat` 约 2.7 µs。

## 支持的硬件

<p align="center">
  <img src="docs/image/YuanNIC-NH400-A.png" alt="YuanNIC-NH400-A" width="300">
</p>

| 型号 | FPGA 器件 | 网口 | 主机接口 | 配置方式 | 镜像型号段 |
|---|---|---|---|---|---|
| YuanNIC-NH400-A | Agilex 7 I `AGIB027` | 1 × 400G QSFP-112（F-tile 4x112） | PCIe Gen5 x16（R-tile） | Active Serial x4 | `YN400GA7B027A` |

**主要参数**

| 项 | 参数 |
|---|---|
| 形态 | 半高半长（Low Profile），单槽 |
| 尺寸 | 169.5 × 68.9 × 18.5 mm |
| 挡板 | 全高 / 半高可换 |
| 功耗 | 最大 75 W（AOC 光模块）；DAC 直连 < 67 W |
| 散热 | 被动散热，依赖机箱风道 |
| 工作温度 | 0 – 55 ℃ |

RoCE 引擎核心时钟 250 MHz。对端互通验证使用 NVIDIA ConnectX-7。

### 软件环境

| 项 | 版本 | 说明 |
|---|---|---|
| 操作系统 | Ubuntu 22.04 x86_64，内核 `5.15.0` | 上板验证所用环境；驱动模块 vermagic 须与 `uname -r` 一致 |
| RDMA 用户态 | rdma-core v66（随本仓库编译，PABI 65） | provider 与 rdma-core 同源编译，无稳定外部 ABI |
| 系统 RDMA 栈 | DOCA 3.5.0 | 与本栈隔离共存，无需卸载；靠 `env.sh` 切换 `LD_LIBRARY_PATH` |
| CUDA | 12.4 | 仅 NCCL / GPUDirect RDMA 场景需要（T4 = sm_75，`NVCC_GENCODE=compute_75,sm_75`） |
| NCCL | 2.22.3 | 源码编译，与对标产品验证过的 2.19.3–2.22.3 区间对齐 |
| nccl-tests | v2.21.1 | NCCL 2.21/2.22 API 的对应测试集，`all_reduce_perf` 双机 |
| 仿真器 | Verilator 5.032 | 需源码编译（apt 的 4.038 不支持 `--timing`），装到 `/opt/verilator` 并加入 `PATH` |
| 仿真框架 | cocotb 1.9.2 · cocotb-bus 0.3.0 · cocotbext-axi 0.1.28 | 台子按 cocotb 1.9 API 编写，不可随手升 2.x |
| Python | 3.10（Ubuntu 22.04 系统自带） | 仿真台子与报文调试脚本 |
| 编译器 | gcc 11 / g++ 11 | Ubuntu 22.04 默认版本，`5.15` 内核用它编译，`code/kernel` 直接 `make` 即可 |
| 构建工具 | cmake、meson、ninja、make、autoconf/flex/bison | provider 用 cmake，DPDK 用 meson+ninja |
| FPGA 工具链 | Quartus Prime Pro 26.1.1 | 仅用于出固件 |

依赖安装见下文「快速开始」。

## 快速开始

### 1. 准备环境

- Ubuntu 22.04 x86_64，Quartus Prime Pro **26.1.1**（仅编译固件需要）
- 仿真需 Verilator 5.032（源码编译）与 cocotb 1.9.2

### 2. 编译前门禁

```bash
test/sim/rtl_prebuild_gate.sh              # 顶层连线检查 + cocotb 仿真台，任一失败返回非 0
test/sim/rtl_prebuild_gate.sh --lint-only  # 只跑连线检查（秒级）
```

### 3. 编译 FPGA 固件

```bash
cd code/build/YuanNIC-NH400-A
./yuannic_build.sh <VER> <BUILD> 1X400G [all|base|release]
```

产物（`.sof` / `.rpd` / `.jic`）按版本号归档到 `code/build/firmware/`。

### 4. 编译用户态软件包

```bash
cd code/build/fpga_rdma
./yuannic_user_build.sh                    # rdma-core v66 + yuanrdma provider + perftest + 内核模块 + 工具
source YuanNIC_User_Package/env.sh         # 每次使用前执行，设置库与程序路径
```

产物 `YuanNIC_User_Package/`（及 `.tgz`）可直接交付最终用户，不向系统路径安装任何文件。

### 5. 烧写、加载驱动与测试

```bash
./flash_and_init.sh --flash <镜像版本>     # 烧写固件 → PCIe 重枚举 → 加载驱动 → 配网 → 自检
./flash_and_init.sh                        # 不烧写，只重新拉起驱动与网络
ibv_devinfo -d yuanrdma0                   # 应看到 PORT_ACTIVE
./roce_perf_test.sh --label <镜像版本>     # 与 ConnectX-7 双向跑全套 perftest
```

## 路线图

- [x] RoCEv2 RC 引擎，与 ConnectX-7 双向 perftest 互通
- [x] 4 QP 发送方向 350 Gb/s 级吞吐，RoCE 引擎 core 250 MHz
- [x] PFC 按优先级门控
- [x] QP 128 / CQ 64 / MTT 131072，DCQCN 覆盖 128 QP
- [x] UD 传输、RoCE CM（RTL 与驱动完成，仿真与单测通过）
- [ ] UD / RoCE CM 上板验证
- [ ] NCCL（nccl-tests 双机 all_reduce）
- [ ] GPUDirect RDMA 上板验证
- [ ] 400G 线速

## 参与开发

- 提交前跑 `test/sim/rtl_prebuild_gate.sh`；RTL 修改后至少完成综合与时序分析。
- 不提交 Quartus 生成物（`qdb/`、`dni/`、`output_files/`）。
- 文档以中文为主，技术名词保留英文。

## 许可证

`code/github/` 下的第三方开源项目遵循各自的许可证。板卡工程中源自合作方的 RTL 与参考设计受授权约束，保留原有 license 头，不对外分发。其余部分版权归垣易科技（YuanGrid）所有。
