# 垣易科技 YuanGrid / YuanRDMA

简体中文 | [English](README.en.md)

<p align="center">
  <img src="docs/logo/YuanRDMA.png" alt="YuanRDMA" width="880">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ARCH-X86__64%20%7C%20ARM__64-612B9B?style=flat-square&labelColor=B48B2E" alt="ARCH X86_64 | ARM64">
  <img src="https://img.shields.io/badge/ETHERNET-400G-612B9B?style=flat-square&labelColor=B48B2E" alt="ETHERNET 400G">
  <img src="https://img.shields.io/badge/PORT-1x400G%20%7C%20200G%20%7C%20100G%20%7C%2040G-612B9B?style=flat-square&labelColor=B48B2E" alt="PORT 1x400G | 200G | 100G | 40G">
  <img src="https://img.shields.io/badge/PCIE-GEN5%20X16-612B9B?style=flat-square&labelColor=B48B2E" alt="PCIE GEN5 X16">
  <img src="https://img.shields.io/badge/FPGA-AGILEX%207%20I-612B9B?style=flat-square&labelColor=B48B2E" alt="FPGA AGILEX 7 I">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/RDMA-ROCEv2%20RC%20%7C%20UD-612B9B?style=flat-square&labelColor=B48B2E" alt="RDMA RoCEv2 RC | UD">
  <img src="https://img.shields.io/badge/UBUNTU-22.04-612B9B?style=flat-square&labelColor=B48B2E" alt="UBUNTU 22.04">
  <img src="https://img.shields.io/badge/RDMA--CORE-v66-612B9B?style=flat-square&labelColor=B48B2E" alt="RDMA-CORE v66">
  <img src="https://img.shields.io/badge/DPDK-25.11.2-612B9B?style=flat-square&labelColor=B48B2E" alt="DPDK 25.11.2">
  <img src="https://img.shields.io/badge/CUDA-12.4-612B9B?style=flat-square&labelColor=B48B2E" alt="CUDA 12.4">
  <img src="https://img.shields.io/badge/NCCL-2.22.3-612B9B?style=flat-square&labelColor=B48B2E" alt="NCCL 2.22.3">
  <img src="https://img.shields.io/badge/QUARTUS%20PRIME-26.1.1-612B9B?style=flat-square&labelColor=B48B2E" alt="QUARTUS PRIME 26.1.1">
</p>

YuanRDMA 是[垣易科技](http://www.yuangrid.com)（[YuanGrid](http://www.yuangrid.com)）研发的基于 FPGA 的 400G RoCEv2 RDMA 智能网卡，产品型号为 **YuanNIC**。RDMA 传输引擎在 FPGA 中原生实现，对主机呈现为标准以太网网卡加标准 RDMA 设备：网口侧走标准以太网协议，RDMA 侧经标准 `libibverbs` / `rdma-core` provider 接入，原版 perftest 不改代码即可运行，并与 NVIDIA ConnectX-7 在同一网络内双向互通。

软件栈同时覆盖两种收包路径。**内核路径**下，`yuannic.ko` 把网口注册为标准以太网设备，`yuanrdma.ko` 接入 `ib_core`，应用经 rdma-core 直接使用 verbs；**用户态路径**下，`net_mcdma` 是 DPDK Poll Mode Driver，报文绕过内核直接在用户态收送，适合高吞吐转发与协议测试。两条路径共用同一套硬件队列与 DMA 通道，可在同一块卡上按业务并存。

在硬件层，YuanNIC 具备面向高速互联的链路时序优化与协议卸载能力：线速报文处理、超低传输时延、400G 高速光口、可编程协议卸载、PFC 无损网络与 DCQCN 拥塞控制。400G 端口可配置为 1x400G / 1x200G / 1x100G / 1x40G，同一块卡既能插入全速骨干，也能降速接入既有网络或测试环境。

主机侧同时支持 **X86_64** 与 **ARM_64** 两种架构，从 RTL、固件构建、内核驱动、用户态 provider 与 DPDK PMD 到仿真验证与上板测试工具链，构成一套完整的软硬件栈。

> 本仓库是 YuanNIC 的开源工程，以 Apache-2.0 协议开放 RTL、驱动与工具源码。

## 目录

- [1 合作生态](#1-合作生态)
- [2 应用场景与客户](#2-应用场景与客户)
- [3 系统架构](#3-系统架构)
  - [3.1 板内数据通路](#31-板内数据通路)
  - [3.2 通信控制路径](#32-通信控制路径)
- [4 主要特性](#4-主要特性)
  - [4.1 RDMA 线速传输](#41-rdma-线速传输)
  - [4.2 DPDK 线速转发](#42-dpdk-线速转发)
  - [4.3 智能加速](#43-智能加速)
  - [4.4 网络安全](#44-网络安全)
  - [4.5 持续迭代](#45-持续迭代)
  - [4.6 接口软件](#46-接口软件)
- [5 资源规模](#5-资源规模)
- [6 性能](#6-性能)
- [7 支持的硬件](#7-支持的硬件)
- [8 软件环境](#8-软件环境)
- [9 快速开始](#9-快速开始)
- [10 路线图](#10-路线图)
- [11 参与开发](#11-参与开发)
- [12 许可证](#12-许可证)

## 1 合作生态

YuanRDMA 以开源方式推进，也希望以共建方式生长。科研院所、高等院校、设备厂商、智算中心与测评机构都在我们的合作范围内：需要硬件时我们提供板卡与测试环境，需要真实负载时由参与方带来场景一起调优。协议扩展与新机制验证、拥塞控制与无损以太调优、驱动与用户态软件栈完善、互通性测试与故障复现、文档与教学材料建设，都是可以共同投入的方向——发现的问题、提出的需求、跑出的数据，最终都回到这条开源主线上。

有意参与的单位或个人，欢迎通过邮件 hfli@yuangrid.com 或电话 / 微信 18362630238 与我们联系。

## 2 应用场景与客户

1. **自建智算集群的行业用户 → 训练与推理集群的互联层 → 标准 verbs 接口 + 可编程拥塞控制。** 大模型训练的多机通信（AllReduce / AllGather / ReduceScatter）本质是 GPU 显存之间的大批量数据搬运，也是决定集群有效算力的关键变量。YuanNIC 走标准 verbs，NCCL 自带的 IB verbs 插件零改造即可运行；多 QP 并行下发把发送方向推到线速的 88%，配合 PFC 无损与 DCQCN 拥塞控制，在共享以太交换网上守住 collective 带宽的确定性。集群越过百卡、通信在迭代时间里的占比越来越大之后，拥塞参数与重传策略必须随规模调整——可编程性让网络从"不可控的瓶颈"变成"可规划的算力延伸"。

2. **分布式存储与对象存储厂商 → NVMe-oF 前端与 KV / 对象存储数据面 → 低时延 + MR 规格。** RDMA Read / Write 绕过内核协议栈，单次写时延约 2.2 µs；128 个 QP、单 MR 最大 512 MiB，足以承载 NVMe-oF 前端与分布式 KV / 对象存储的数据面。KVCache 卸载、参数服务器这类"一块大 buffer 反复写远端"的负载，正是 Write with Immediate 加完成队列异步流水的最优形态。存储与计算的边界由此重划——远端内存的访问代价被压到接近本地。

3. **推理服务厂商 → P/D 分离架构下的 KV Cache 跨节点搬运 → 显存直连，免中转拷贝。** GPUDirect RDMA（dma-buf MR 注册）让数据不经主机内存直达显存，KV Cache 跨节点搬运省掉两次拷贝；IBGDA 让 GPU 自己写门铃发起请求，把 CPU 从每次通信的提交路径上摘除。两项均已实现，上板验证进行中——通信从"CPU 代劳"走向"设备自主"，这是万卡级推理集群的前置条件。

4. **网络通信设备厂商与测试仪表厂商 → 400G 对端网卡与互通用例 → 无损以太参数全可配。** 400GbE 单口、PFC 按优先级门控、ECN + DCQCN 全寄存器可配，既能作为交换机在 PFC / ECN 场景下的对端网卡复现真实行为，也能顶上 400G 测试仪表的端口位；端口降速到 200G / 100G / 40G 即可直接对接既有环境。超大规模智算网络的稳定性最终取决于无损以太链路上每一个参数的确定性——参数可读可改，才谈得上验证这份确定性。

5. **科研院所与高校 → 协议研究与教学平台 → 软硬件栈全开源，改动可先离线验证。** RTL、驱动、provider、仿真台全部在本仓库，改协议字段、改拥塞算法、改重传策略只需重编固件，不必从零搭一套网卡工程；cocotb 仿真台与编译前门禁让改动能先离线验证再上板。硬件不再是一次性固化的黑盒，而是可持续演进的协议载体——RDMA、拥塞控制与 FPGA 网络加速的研究，正需要这样一块随时可改的基座。

## 3 系统架构

### 3.1 板内数据通路

主机侧只有 WQE 提交与 CQE 收取穿过 PCIe；数据面报文从 F-tile MAC 进出，在引擎内完成组包与解析，不经过主机软件栈。

![YuanNIC 板内数据通路](docs/image/on-card-datapath.png)

自下而上：400G QSFP-112 经 F-tile Ethernet Hard IP（MAC + PCS + RS-FEC）进出；流量管理做优先级队列、PFC 门控与 RX 分类（RoCE UDP 4791 走引擎，其余交 netdev）；RoCEv2 传输引擎负责 TX 组包与 RX 解析、PSN 与重传、ICRC 生成校验，以及 DCQCN 的 RP 限速与 CNP 生成；主机接口维护 doorbell、QPC / CQC 表、MR / MTT 翻译缓存与 CQ / EQ；DMA 层用 AXI MCDMA 的 BAM（CSR / doorbell）、BAS（引擎主动取 WQE、写 CQE）与 MCDMA（netdev）把两侧接起来。端口速率只影响 MAC 与链路层配置，引擎与软件栈不随速率变化。

### 3.2 通信控制路径

一次 RDMA 操作从应用提交到对端可用的完整路径如下。三条控制路径并存，共用同一套 verbs 语义与完成队列，应用侧无需区分：常规 verbs（CPU 构建并提交 WQE）、IBGDA（GPU 自己写门铃发起）、GPUDirect RDMA（GPU 显存与网卡之间直接搬运，不经 CPU 中转）。

![YuanNIC 控制路径与数据路径](docs/image/control-path.png)

1. 应用调用 `ibv_post_send`，在主机内存构建 WQE，写入 SQ 并敲 doorbell（BAR2 UAR 页，WC 映射）。
2. 网卡 DMA 取 WQE，按 QPC 校验 `lkey / rkey`，经 MTT 翻译成物理地址。
3. 引擎组包：BTH / RETH / AETH / DETH + payload + ICRC，按 PFC 门控与 DCQCN 令牌桶放行。
4. 报文经 400GbE（或 200 / 100 / 40GbE）发往对端；对端按 PSN 排序、落内存，硬件回 ACK / NAK；拥塞时交换机打 ECN，对端回 CNP。
5. 完成后网卡把 CQE 写回主机内存，应用轮询 CQ 取完成，按 `wr_id` 归还缓冲。
6. RDMA Write 的对端内存由网卡直接写入，对端 CPU 不参与；Send 由网卡写入 RQ 缓冲后才产生 CQE。
7. GPU 场景：显存做 `dma-buf` MR 注册后数据直达显存；IBGDA 由 GPU 侧写门铃，把 CPU 从提交路径上摘掉。

## 4 主要特性

### 4.1 RDMA 线速传输

- **协议栈原生**：RoCEv2 RC / UD 在 RTL 中实现，组包与解析在网卡内完成，数据面不过主机软件栈。
- **RC 语义**：Write / Write with Immediate / Read / Send / Send with Immediate；PSN、ACK / NAK、Go-back-N 重传与超时、ICRC 全部硬件完成。
- **UD 语义**：Send / Send with Immediate（带 DETH），CQE 回报源 QPN。
- **多 QP 并行**：单 QP 受组包开销限制在线速 36%，4 QP 达 88%（352.1 Gb/s）；`QP_NUM` 默认 128，可扩至 4096。
- **建链两种**：RoCE CM（QP1 / GSI 交换 CM MAD，标准 `rdma_cm` 路径），或 TCP 交互建链信息（NCCL、perftest 经 verbs 自行交换，不依赖 CM）。
- **QPN 窗口**：QPN 落在基址对齐的连续窗口内，`FORCE_MAX_QP` / `FORCE_QPN_BASE` 软硬件同步。
- **PFC 无损**：IEEE 802.1Qbb 按优先级发送准入，PFC 帧由 F-tile 硬核 MAC 收发。
- **DCQCN**：RP / NP / CNP 完整实现，覆盖全部 QP，参数全寄存器可配。
- **在线可调**：PFC 优先级、DSCP、ECN 门限、DCQCN 速率与计时器在线读写，无需重编固件。
- **多速率端口**：1x400G / 1x200G / 1x100G / 1x40G 由固件配置选定，上层软件栈与 verbs 接口不变。

### 4.2 DPDK 线速转发

- `net_mcdma` 在用户态直接收送，不进内核协议栈，省掉中断、上下文切换与内存拷贝。
- 队列直连 AXI MCDMA 硬件队列，大页内存作缓冲，400GbE 线速报文可按需取用与改写。
- 与 RDMA 路径共用一块卡，转发、镜像、协议测试与损伤仿真各走各的软件栈。
- 基于 DPDK 25.11.2，随仓库源码构建。

### 4.3 智能加速

- **卸载点**：MAC 分类与时间戳、流量管理整形、RoCE 组包与重传、DMA 搬运与写回，均可下移硬件。
- **协议卸载**：TCP / UDP / RoCEv2 组包解析、ICRC 校验、checksum 计算由硬件完成。
- **安全卸载**：加解密在硬件流水线完成，报文不落主机内存，密钥与算法由配置面下发。
- **策略分流**：按五元组、DSCP、VLAN 或自定义字段分类，送 RDMA 引擎、netdev、DPDK 队列或丢弃。
- **拥塞与可靠性卸载**：PFC 门控、ECN 标记、DCQCN 限速、丢包检测与重传，不依赖内核定时器。
- **可编程**：协议字段、拥塞算法、重传策略、整形参数在 RTL 与寄存器层开放，改策略只重编固件。
- **可观测**：`yuancli` 管 PFC / DSCP / ECN / DCQCN 参数、寄存器计数器与卡死快照；`ynictrl` 管网卡管理。

### 4.4 网络安全

YuanSec 以 FPGA 并行计算加 DPDK 转发为数据面，把检测与密码运算搬到硬件，形成「收发 → 解析 → 检测 → 处置」闭环。

- **线速解析**：多维字段分类、时间戳与流表匹配由硬件完成，覆盖 1 / 10 / 25 / 100 / 400 GE。
- **快速转发**：多队列、零拷贝与负载分发，检测面与转发面同卡，命中后可在用户态丢弃、镜像或改写。
- **检测与审计**：异常识别、规则过滤与旁路分析，实时拦截并留痕。
- **密码与协议卸载**：国密、PQC、AES / RSA 与专用协议解析封装在硬件完成，报文不回主机内存。
- **策略可配**：匹配字段、动作与规则表按业务裁剪，与网络策略同配置面管理。

交付形态包括安全网关 / 防火墙、流量审计平台、DDoS 防护清洗与密码加速系统，覆盖政企、工业控制、数据中心与高速通信。

### 4.5 持续迭代

- **固件在线升级**：镜像经板载 Active Serial x4 写入配置器件（产物 `.sof` / `.rpd` / `.jic`）；升级后 PCIe 重枚举、驱动重新加载，主机操作系统不重启，一条脚本串起烧写 → 重枚举 → 加载驱动 → 配网 → 自检。
- **版本可回退**：镜像以版本号标识（网卡型号 `YN400GA7B027A` / C），多版本并存，回退即烧回旧镜像；升级只动配置器件，不向主机系统安装任何文件。
- **分层独立升级**：固件、内核驱动（随 `uname -r` 编译）、用户态 provider 与 PMD 各自独立演进，改一层不必动另两层；加上参数在线读写，调参不重编固件、升级不重装系统。
- **问题可定位**：`yuancli` 与 `ynictrl` 读取寄存器与计数器、导出卡死现场快照，配合 perftest、`roce_perf_test.sh` 回归与硬件侧镜像抓包，故障可从现象追到寄存器状态，不必靠猜。
- **与上层软件联动**：对内保持 `rdma_cm`、NCCL 与 perftest 的既有路径；对外经 `yuancli` / `ynictrl` 与配置面开放读写与操控，监控与策略可纳入既有运维体系。
- **改动可验证**：RTL、驱动、provider、仿真台同仓；协议字段、拥塞算法、重传策略与队列整形的改动，从改代码、离线验证（cocotb 仿真台与编译前门禁）、出固件到上板回归是一条完整链路。

### 4.6 接口软件

- **主机接口**：PCIe Gen5 x16（R-tile）+ AXI MCDMA，doorbell、WQE 取指与 CQE 写回全硬件完成。
- **内核驱动**：`yuannic.ko` 提供 netdev，`yuanrdma.ko` 接入 `ib_core` 提供 RDMA 设备。
- **provider**：`libyuanrdma` 与 rdma-core v66 同源编译，与系统 DOCA 栈隔离共存。
- **PMD**：`net_mcdma` 与内核路径共用硬件队列，可在同一块卡上并存。

## 5 资源规模

队列、表项与内存翻译合并如下；规格由 `QP_NUM` 等参数化配置决定，可随固件调整。

<table width="100%" style="width:100%;border:0;border-collapse:collapse">
<tr><td style="border:0;padding:0">

<table width="100%" style="width:100%">
<tr><th style="width:48%">项</th><th style="width:52%">规格</th></tr>
<tr><td style="width:48%">QP 数量</td><td style="width:52%">默认 128，可扩展至 4096（<code>QP_NUM</code> 参数化）</td></tr>
<tr><td style="width:48%">CQ 数量</td><td style="width:52%">64</td></tr>
<tr><td style="width:48%">SQ / RQ 深度</td><td style="width:52%">4096</td></tr>
<tr><td style="width:48%">CQ 深度</td><td style="width:52%">最高 32768</td></tr>
<tr><td style="width:48%">建链资源</td><td style="width:52%">QP1 / GSI 承载 CM MAD</td></tr>
<tr><td style="width:48%">MTT 表项</td><td style="width:52%">131072</td></tr>
<tr><td style="width:48%">单个 MR 上限</td><td style="width:52%">512 MiB</td></tr>
<tr><td style="width:48%">校验与翻译</td><td style="width:52%"><code>lkey / rkey</code> 校验与地址翻译缓存在硬件完成</td></tr>
<tr><td style="width:48%">GPU 显存访问</td><td style="width:52%"><code>dma-buf</code> MR 注册（<code>ibv_reg_dmabuf_mr</code>，内核 ≥ 6.2），软件栈完成、上板验证进行中</td></tr>
</table>

</td></tr>
</table>

## 6 性能

测试条件：YuanNIC-NH400-A，对端 NVIDIA ConnectX-7，400GbE 直连，原版 perftest。带宽用例消息 1 MiB、每项 30 s；延迟用例消息 2 B、每项 30 s，表中取 perftest 的典型值（typical，中位）。数据取自镜像 `R26.12.17-B6462-20261121-1X400G`。

<table width="100%" style="width:100%;border:0;border-collapse:collapse">
<tr><td style="border:0;padding:0">

<table width="100%" style="width:100%">
<tr><th style="width:26%">用例</th><th style="width:37%">YuanNIC 作客户端</th><th style="width:37%">YuanNIC 作服务端</th></tr>
<tr><td style="width:26%"><code>ib_write_bw</code>（1 QP）</td><td style="width:37%"><strong>219.3 Gb/s（54.8%）</strong></td><td style="width:37%">100.0 Gb/s（25.0%）</td></tr>
<tr><td style="width:26%"><code>ib_read_bw</code>（1 QP）</td><td style="width:37%">77.2 Gb/s（19.3%）</td><td style="width:37%">89.8 Gb/s（22.5%）</td></tr>
<tr><td style="width:26%"><code>ib_send_bw</code>（1 QP）</td><td style="width:37%"><strong>219.3 Gb/s（54.8%）</strong></td><td style="width:37%">97.7 Gb/s（24.4%）</td></tr>
<tr><td style="width:26%"><code>ib_write_bw</code>（4 QP）</td><td style="width:37%"><strong>351.9 Gb/s（88.0%）</strong></td><td style="width:37%">96.9 Gb/s（24.2%）</td></tr>
<tr><td style="width:26%"><code>ib_read_bw</code>（4 QP）</td><td style="width:37%">99.6 Gb/s（24.9%）</td><td style="width:37%"><strong>328.2 Gb/s（82.1%）</strong></td></tr>
</table>

</td></tr>
</table>

括号内为占 400 Gb/s 线速的比例。多 QP 并发时发送方向达 88%、接收方向 82%；单 QP 发送已达 54.8%（B6462 起，此前 35.7%），多 QP 仍用于进一步逼近线速。

时延（2 B 消息，单向，typical / p99）：

<table width="100%" style="width:100%;border:0;border-collapse:collapse">
<tr><td style="border:0;padding:0">

<table width="100%" style="width:100%">
<tr><th style="width:26%">用例</th><th style="width:37%">YuanNIC 作客户端</th><th style="width:37%">YuanNIC 作服务端</th></tr>
<tr><td style="width:26%"><code>ib_write_lat</code></td><td style="width:37%"><strong>2.44 / 2.67 µs</strong></td><td style="width:37%"><strong>2.40 / 2.58 µs</strong></td></tr>
<tr><td style="width:26%"><code>ib_read_lat</code></td><td style="width:37%">4.23 / 4.61 µs</td><td style="width:37%">2.85 / 3.19 µs</td></tr>
<tr><td style="width:26%"><code>ib_send_lat</code></td><td style="width:37%">2.75 / 2.92 µs</td><td style="width:37%">2.44 / 2.59 µs</td></tr>
</table>

</td></tr>
</table>

写时延两端都在 2.4 µs 附近，与消息长度基本无关；读时延在客户端方向上偏高到 4.2 µs，是响应数据在接收侧串行搬运的代价。p99 与 typical 相差 0.1–0.4 µs，主要来自主机侧中断与调度抖动，评估跨版本回归时以 typical 为准。

## 7 支持的硬件

<table width="100%" style="width:100%;border:0;border-collapse:collapse">
<tr>
<td width="62%" valign="top" style="border:0;padding:0">

<table width="100%" style="width:100%">
<tr><th style="width:48%">项</th><th style="width:52%">规格</th></tr>
<tr><td style="width:48%">型号</td><td style="width:52%">YuanNIC-NH400-A</td></tr>
<tr><td style="width:48%">FPGA 器件</td><td style="width:52%">Agilex 7 I <code>AGIB027</code></td></tr>
<tr><td style="width:48%">网口</td><td style="width:52%">1 × 400G QSFP-112（F-tile 4x112）</td></tr>
<tr><td style="width:48%">端口模式</td><td style="width:52%">1x400G / 1x200G / 1x100G / 1x40G（同一 400G 笼口，按固件配置）</td></tr>
<tr><td style="width:48%">主机接口</td><td style="width:52%">PCIe Gen5 x16（R-tile）</td></tr>
<tr><td style="width:48%">核心时钟</td><td style="width:52%">RoCE 引擎 250 MHz</td></tr>
<tr><td style="width:48%">配置方式</td><td style="width:52%">Active Serial x4</td></tr>
<tr><td style="width:48%">网卡型号</td><td style="width:52%"><code>YN400GA7B027A</code> / C</td></tr>
<tr><td style="width:48%">形态</td><td style="width:52%">单槽半高半长（配全高挡片）</td></tr>
<tr><td style="width:48%">尺寸</td><td style="width:52%">169.5 × 68.9 × 18.5 mm</td></tr>
<tr><td style="width:48%">功耗</td><td style="width:52%">最大 75 W</td></tr>
<tr><td style="width:48%">散热</td><td style="width:52%">被动散热，依赖机箱风道</td></tr>
<tr><td style="width:48%">工作温度</td><td style="width:52%">0 – 55 ℃</td></tr>
</table>

</td>
<td width="38%" valign="middle" align="center" style="border:0;padding:0">
  <img src="docs/image/YuanNIC-NH400-A.png" alt="YuanNIC-NH400-A" width="300">
</td>
</tr>
</table>

端口模式随固件编译选定，上板后按链路协商生效；速率切换只改 MAC 与链路层配置，verbs 接口与上层软件栈保持不变。互通性以 NVIDIA ConnectX-7 为对端验证。PCIe Gen5 x16 的主机侧带宽与 400GbE 线速基本对等，避免主机接口先成为瓶颈。

## 8 软件环境

<table width="100%" style="width:100%;border:0;border-collapse:collapse">
<tr><td style="border:0;padding:0">

<table width="100%" style="width:100%">
<tr><th style="width:22%"><strong>项</strong></th><th style="width:18%"><strong>版本</strong></th><th style="width:60%"><strong>说明</strong></th></tr>
<tr><td style="width:22%">操作系统</td><td style="width:18%">Ubuntu 22.04，内核 <code>5.15.0-203-generic</code></td><td style="width:60%">X86_64 / ARM_64 双架构；上板验证环境为 X86_64，驱动 vermagic 须与 <code>uname -r</code> 一致</td></tr>
<tr><td style="width:22%">主机架构</td><td style="width:18%">X86_64、ARM_64</td><td style="width:60%">驱动、provider、DPDK PMD 与工具链均在两种架构上提供构建路径</td></tr>
<tr><td style="width:22%">RDMA 用户态</td><td style="width:18%">rdma-core v66（随本仓库编译，PABI 65）</td><td style="width:60%">provider 与 rdma-core 同源编译，无稳定外部 ABI，须随架构重编</td></tr>
<tr><td style="width:22%">系统 RDMA 栈</td><td style="width:18%">DOCA 3.5.0</td><td style="width:60%">与本栈隔离共存，无需卸载</td></tr>
<tr><td style="width:22%">DPDK</td><td style="width:18%">25.11.2</td><td style="width:60%">用户态收包路径，PMD 为 <code>net_mcdma</code>；meson + ninja 构建</td></tr>
<tr><td style="width:22%">CUDA</td><td style="width:18%">12.4</td><td style="width:60%">仅 NCCL / GPUDirect RDMA 场景需要（T4 = sm_75，<code>NVCC_GENCODE=compute_75,sm_75</code>）</td></tr>
<tr><td style="width:22%">NCCL</td><td style="width:18%">2.22.3</td><td style="width:60%">源码编译，已验证兼容 2.19.3–2.22.3 区间</td></tr>
<tr><td style="width:22%">nccl-tests</td><td style="width:18%">v2.21.1</td><td style="width:60%">NCCL 2.21 / 2.22 API 对应的测试集，<code>all_reduce_perf</code> 双机</td></tr>
<tr><td style="width:22%">仿真器</td><td style="width:18%">Verilator 5.032</td><td style="width:60%">需源码编译（apt 的 4.038 不支持 <code>--timing</code>），装到 <code>/opt/verilator</code> 并加入 <code>PATH</code></td></tr>
<tr><td style="width:22%">仿真框架</td><td style="width:18%">cocotb 1.9.2 · cocotb-bus 0.3.0 · cocotbext-axi 0.1.28</td><td style="width:60%">台子按 cocotb 1.9 API 编写，不可随手升 2.x</td></tr>
<tr><td style="width:22%">Python</td><td style="width:18%">3.10（Ubuntu 22.04 系统自带）</td><td style="width:60%">仿真台子与报文调试脚本</td></tr>
<tr><td style="width:22%">编译器</td><td style="width:18%">gcc 11 / g++ 11</td><td style="width:60%">Ubuntu 22.04 默认版本，<code>5.15</code> 内核用它编译，<code>code/kernel</code> 直接 <code>make</code></td></tr>
<tr><td style="width:22%">构建工具</td><td style="width:18%">cmake、meson、ninja、make、autoconf/flex/bison</td><td style="width:60%">provider 用 cmake，DPDK 用 meson + ninja</td></tr>
<tr><td style="width:22%">FPGA 工具链</td><td style="width:18%">Quartus Prime Pro 26.1.1</td><td style="width:60%">仅出固件时需要</td></tr>
</table>

</td></tr>
</table>

## 9 快速开始

### 9.1 准备环境

- Ubuntu 22.04，X86_64 或 ARM_64 主机；Quartus Prime Pro **26.1.1**（仅编译固件需要）
- 仿真需 Verilator 5.032（源码编译）与 cocotb 1.9.2

### 9.2 编译前门禁

```bash
test/sim/rtl_prebuild_gate.sh              # 顶层连线检查 + cocotb 仿真台，任一失败返回非 0
test/sim/rtl_prebuild_gate.sh --lint-only  # 只跑连线检查（秒级）
```

### 9.3 编译 FPGA 固件

```bash
cd build/YuanNIC-NH400-A
./yuannic_build.sh <VER> <BUILD> <PORT_MODE> [all|boot|active]
./yuannic_build.sh 1 1 1X400G boot        # 400G 单口
./yuannic_build.sh 2 1 1X200G active      # 降到 200G
```

`<PORT_MODE>` 取 `1X400G` / `1X200G` / `1X100G` / `1X40G`；产物（`.sof` / `.rpd` / `.jic`）按版本号归档到 `build/firmware/`。

### 9.4 烧写、加载驱动与测试

```bash
./flash_and_init.sh --flash <镜像版本>     # 烧写固件 → PCIe 重枚举 → 加载驱动 → 配网 → 自检
./flash_and_init.sh                        # 不烧写，只重新拉起驱动与网络
ibv_devinfo -d yuanrdma0                   # 应看到 PORT_ACTIVE
./roce_perf_test.sh --label <镜像版本>     # 与 ConnectX-7 双向跑全套 perftest
```

## 10 路线图

已完成：

- [x] RoCEv2 RC 引擎，与 ConnectX-7 双向 perftest 互通
- [x] PFC 按优先级门控
- [x] QP 128 / CQ 64 / MTT 131072，DCQCN 覆盖 128 QP
- [x] UD 传输、RoCE CM（RTL 与驱动完成，仿真与单测通过）
- [x] 1x400G / 1x200G / 1x100G / 1x40G 端口模式，X86_64 与 ARM_64 双架构软件栈
- [x] GPUDirect RDMA 与 NCCL 接入（软件栈完成，上板验证进行中）

进行中与后续，三条主线：

### 10.1 400G 性能优化与集合通信库

单 QP 受每包组包开销限制只跑到线速的 36%，多 QP 并发目前 88%。下一步是优化组包与流控路径向线速逼近，并把多 QP 下发的调度、拥塞反馈与重传收敛成可复用的通信原语，在其上构建面向集合通信（AllReduce / AllGather / ReduceScatter）的通信库，让上层无需自己管理 QP 并行度。

### 10.2 扩大适配场景

在已验证的 GPUDirect RDMA 与 NCCL 基础上覆盖更多实际负载形态：P/D 分离推理中的 KV Cache 跨节点搬运、训练侧的混合并行通信模式，以及多厂商网卡与交换机的互通矩阵。

### 10.3 800G（2027 年目标）

面向下一代互联的架构预研与实现：链路层带宽翻倍的时序收敛、更大 QP 规模下的缓存与调度开销，以及配套软件栈的适配。

## 11 参与开发

YuanRDMA 旨在成为可开源、可学习、可扩展的 RDMA 网卡平台：RTL、驱动、provider、仿真台与测试工具全部在仓库内，改动可以离线验证再上板。我们希望降低高性能网络的研究与工程门槛，让协议机制、拥塞控制、传输可靠性这些问题能在真实的 400G 硬件上被验证，而不是停留在仿真或纸面。

有意参与的单位或个人，欢迎通过邮件 [hfli@yuangrid.com](mailto:hfli@yuangrid.com) 或电话 / 微信 18362630238 与我们联系。

提交前跑 `test/sim/rtl_prebuild_gate.sh`；RTL 修改后至少完成综合与时序分析。不提交 Quartus 生成物（`qdb/`、`dni/`、`output_files/`）。文档以中文为主，技术名词保留英文。

## 12 许可证

`code/github/` 下的第三方开源项目遵循各自的许可证。板卡工程中源自合作方的 RTL 与参考设计受授权约束，保留原有 license 头，不对外分发。其余部分版权归垣易科技（YuanGrid）所有。
