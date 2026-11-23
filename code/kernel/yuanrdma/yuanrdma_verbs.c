// SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause
/*
 * yuanrdma_verbs.c - ib_device_ops：查询、PD、MR（锁页写 MTT/MPT）、CQ、QP（写 QPC）、mmap。
 * 数据面（post_send/post_recv/poll_cq）全在用户态 provider 里，内核不实现。
 */
#include <linux/etherdevice.h>
#include <linux/inetdevice.h>
#include <linux/version.h>	/* LINUX_VERSION_CODE：dmabuf MR 的 API 分界（见下） */
#include <net/addrconf.h>
#include <rdma/ib_addr.h>
#include <rdma/ib_cache.h>
#include <rdma/uverbs_ioctl.h>
#include <rdma/ib_mad.h>
#include <rdma/iba.h>
/* Ubuntu 5.15.0-198 起 ib_block_iter / rdma_umem_for_each_dma_block 从 ib_umem.h 挪到 iter.h */
#if __has_include(<rdma/iter.h>)
#include <rdma/iter.h>
#endif
/*
 * dma-buf MR（GPUDirect）只在内核 6.2+ 编译。
 *   6.2 引入 ib_umem_dmabuf_get_pinned()（内部做 dma_buf_pin + map_pages + dma_resv 加锁），
 *   在那之前的 API 是 ib_umem_dmabuf_get(..., const struct dma_buf_attach_ops *ops)，
 *   语义完全不同（异步 move_notify、不 pin），不能在同一个函数体里兼容。
 *   5.15（MOFED 那份 ib_core）没有 pinned 版本，这里直接不注册该 op：
 *   用户态 ibv_reg_dmabuf_mr 会得到 -EOPNOTSUPP，与「驱动没实现」同一可见结果，
 *   而且 insmod 不会因为缺符号失败。
 * 检测方式用版本号而不是 __has_include：函数声明在 5.15/6.8 的同一个头文件里都有，
 * __has_include 无法区分「只是声明存在」和「有这个函数」。
 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)
#define YUANRDMA_HAVE_UMEM_DMABUF_PINNED 1
#endif

/*
 * 释放一条 umem：dma-buf MR 必须走 ib_umem_dmabuf_release()（6.2+ 有真实导出符号，
 * 内部做 dma_buf unpin + unmap），普通锁页 MR 走 ib_umem_release()。
 * 不能无条件调用 ib_umem_dmabuf_release()：5.15 里它只是空 inline，modpost 会报
 * 「undefined!」（没有导出符号），而 5.15 本来也不注册 dmabuf op。
 */
static inline void yuanrdma_umem_put(struct ib_umem *umem, struct ib_umem_dmabuf *umem_dmabuf)
{
#ifdef YUANRDMA_HAVE_UMEM_DMABUF_PINNED
	if (umem_dmabuf) {
		ib_umem_dmabuf_release(umem_dmabuf);
		return;
	}
#endif
	ib_umem_release(umem);
}

#include "yuanrdma_driver.h"
#include "yuanrdma_abi_defs.h"

/* ---------------------------------------------------------------- 查询 */
static int yuanrdma_query_device(struct ib_device *ibdev, struct ib_device_attr *attributes,
				 struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibdev);

	if (udata->inlen || udata->outlen)
		return -EINVAL;
	memset(attributes, 0, sizeof(*attributes));
	attributes->fw_ver = yuanrdma_read(dev, YNRDMA_REG_VERSION);
	attributes->sys_image_guid = ibdev->node_guid;
	attributes->max_mr_size = (u64)YNRDMA_MAX_MTT << YNRDMA_PAGE_SHIFT;
	attributes->page_size_cap = SZ_4K;
	attributes->vendor_id = YNRDMA_PCI_VENDOR_ID;
	attributes->vendor_part_id = dev->pdev->device;
	attributes->hw_ver = dev->pdev->revision;
	attributes->max_qp = YNRDMA_MAX_QP;
	attributes->max_qp_wr = min(YUANRDMA_MAX_SQ_DEPTH, YUANRDMA_MAX_RQ_DEPTH) - 1;
	attributes->max_send_sge = YUANRDMA_GSI_MAX_SGE;	/* 用户态 QP 只给 1，内核 QP1 要 2（见 create_qp） */
	attributes->max_recv_sge = YUANRDMA_GSI_MAX_SGE;
	attributes->max_sge_rd = 1;
	attributes->max_cq = YNRDMA_MAX_CQ;
	attributes->max_cqe = YUANRDMA_MAX_CQ_DEPTH - 1;
	attributes->max_mr = YNRDMA_MAX_MR;
	attributes->max_pd = 65535;
	attributes->max_qp_rd_atom = 16;	/* 请求方最多 16 个在途 READ（QPC max_rd 4 bit） */
	attributes->max_qp_init_rd_atom = 16;
	attributes->max_res_rd_atom = 16 * YNRDMA_MAX_QP;
	attributes->atomic_cap = IB_ATOMIC_NONE;
	attributes->local_ca_ack_delay = 16;
	attributes->max_pkeys = 1;
	/*
	 * device_cap_flags：只声明**在代码里找得到落点**的项。这一位是 ULP 用来区分
	 * 「不支持」与「驱动忘了填」的唯一依据（NCCL、rdma_cm 与各家 perftest 都读它），
	 * 恒 0 会让它们全部走最保守的路径，`ibv_devinfo -v` 也看不出设备能做什么。
	 *
	 * 声明：
	 *   CURR_QP_STATE_MOD —— modify_qp 读 IB_QP_CUR_STATE（下面 mask 里的 cur_qp_state），
	 *     以调用方给的当前状态做状态转换校验，而不是一律假定 qp->state。
	 *   RC_RNR_NAK_GEN —— 响应侧硬件真的会生成 RNR NAK：RQ 空时回 AETH_RNR_NAK 并把
	 *     QPC 的 min_rnr_timer 编进 syndrome（roce_resp 的 ACK 分支）；请求侧按
	 *     rnr_retry / min_rnr_timer 起 RNR 定时器重发（roce_req）。两侧都在，不是空声明。
	 *
	 * 不声明（每条都能指出缺什么）：
	 *   RESIZE_MAX_WR —— 队列深度是 create_qp 时协商后回填的，没有 resize 通路。
	 *   BAD_PKEY_CNTR / BAD_QKEY_CNTR —— port_attr 的 bad_pkey_cntr / qkey_viol_cntr 恒 0，
	 *     硬件不做 P_Key / Q_Key 校验，没有计数器可报。
	 *   UD_AV_PORT_ENFORCE —— 只有 1 个端口，这道闸门没有可判的内容。
	 *   N_NOTIFY_CQ —— req_notify_cq 没有可用的完成事件通路：CQ 环在主机内存里，
	 *     内核看不见 producer，硬件也不产生 MSI。见 provider 侧同一条注释。
	 *   SHUTDOWN_PORT / MEM_MGT_EXTENSIONS —— 无对应实现（无 SHUTDOWN 端口操作、无 MW/FRMR）。
	 */
	attributes->device_cap_flags = IB_DEVICE_CURR_QP_STATE_MOD | IB_DEVICE_RC_RNR_NAK_GEN;
	return 0;
}

static int yuanrdma_query_port(struct ib_device *ibdev, u32 port, struct ib_port_attr *attributes)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibdev);
	bool link_up = yuanrdma_read(dev, YNRDMA_REG_STATUS) & 1;

	/* 核心已清零 attributes */
	attributes->state = link_up ? IB_PORT_ACTIVE : IB_PORT_DOWN;
	attributes->phys_state = link_up ? IB_PORT_PHYS_STATE_LINK_UP : IB_PORT_PHYS_STATE_DISABLED;
	attributes->max_mtu = IB_MTU_4096;
	attributes->active_mtu = iboe_get_mtu(dev->netdev->mtu);
	attributes->gid_tbl_len = 16;
	attributes->pkey_tbl_len = 1;
	/*
	 * IB_PORT_CM_SUP 不上报。
	 *
	 * 这一位是「端口支持 RDMA CM」的对外能力位。上报它，rdma_cm 的客户端才会走到
	 * cma_alloc_port 之后；不上报，rdma_create_ep() 直接 EOPNOTSUPP。所以它不是可有
	 * 可无的装饰，而是「CM 能用」的承诺。
	 *
	 * 2026-11-22 B6462 上板实测（enable_cm_sup 打开后）：rping 客户端在
	 * `ibv_create_comp_channel` 失败。三条链路各自独立，缺一条就走不通：
	 *   1) librdmacm 的 ucma_create_cqs() 只要 CQ 有 send/recv 深度就无条件
	 *      ibv_create_comp_channel()——rping、ucmatose、rdma_server/client 全都走这条；
	 *   2) comp channel 是 ib_uverbs 的通用命令，但本驱动的 uverbs_cmd_mask 没有开放
	 *      IB_USER_VERBS_CMD_CREATE_COMP_CHANNEL，5.15 的 uverbs_uapi 把它标成 disabled
	 *      并返回 EOPNOTSUPP（放开这一位只解决第 1 步）；
	 *   3) 真正的缺口是**没有完成事件通路**：CQ 环在主机内存里、硬件直接写 CQE，内核
	 *      看不见 producer，硬件也不产生 MSI，所以 req_notify_cq 只能返回 EOPNOTSUPP，
	 *      即使建出 channel 也永远收不到事件（rdma_get_recv_comp 会卡在
	 *      read(channel->fd)）。
	 *
	 * 第 3 条是硬件能力缺口，不是开关能补的。因此不做模块参数、不留「打开就能用」的
	 * 假入口：`ibv_devinfo -v` 的 port_cap_flags 里不会有这一位，ULP 会按「无 CM」处理，
	 * 这正是当前的真实状态。
	 *
	 * QP1 的 CM MAD 数据通路本身是就绪的（软件 GSI 收发整帧、交付 40 B GRH，
	 * 见 yuanrdma_gsi.c），缺的是完成事件，不涉及 CM 报文语义。
	 *
	 * 恢位条件（写清楚，别靠记忆）：硬件提供 CQ 完成中断（或内核侧能拿到 per-CQ
	 * producer 计数），req_notify_cq 真正投递事件，且 rping、ucmatose 各成功一次。
	 * 届时把这一行改成 IB_PORT_CM_SUP 并附上板日期与镜像版本。
	 */
	attributes->port_cap_flags = 0;
	attributes->max_msg_sz = 0x80000000;
	attributes->bad_pkey_cntr = 0;
	attributes->qkey_viol_cntr = 0;
	attributes->lid = 0;
	attributes->sm_lid = 0;
	attributes->active_width = IB_WIDTH_4X;
	attributes->active_speed = IB_SPEED_NDR;	/* 400GbE 链路（引擎 v1 吞吐约 100 Gb/s） */
	return 0;
}

static int yuanrdma_get_port_immutable(struct ib_device *ibdev, u32 port, struct ib_port_immutable *immutable)
{
	immutable->pkey_tbl_len = 1;
	immutable->gid_tbl_len = 16;
	/* 同时声明 v1 和 v2，GID 索引与 ConnectX 习惯一致（IPv4 的 v2 在 index 3）；引擎只收发 v2 */
	immutable->core_cap_flags = RDMA_CORE_PORT_IBA_ROCE | RDMA_CORE_PORT_IBA_ROCE_UDP_ENCAP;
	immutable->max_mad_size = IB_MGMT_MAD_SIZE;
	return 0;
}

static int yuanrdma_query_pkey(struct ib_device *ibdev, u32 port, u16 index, u16 *pkey)
{
	if (index > 0)
		return -EINVAL;
	*pkey = 0xffff;
	return 0;
}

static enum rdma_link_layer yuanrdma_get_link_layer(struct ib_device *ibdev, u32 port)
{
	return IB_LINK_LAYER_ETHERNET;
}

/* 本端 IPv4 写进引擎（引擎按目的 IP 过滤收包），只支持一个 IPv4 地址。
 * 软件 GSI 的收包挂钩也按这个地址过滤，所以同时记在 dev->ipv4。 */
static int yuanrdma_add_gid(const struct ib_gid_attr *attr, void **context)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(attr->device);
	const u8 *raw = attr->gid.raw;

	if (attr->gid_type == IB_GID_TYPE_ROCE_UDP_ENCAP && ipv6_addr_v4mapped((struct in6_addr *)raw)) {
		yuanrdma_write(dev, YNRDMA_REG_IPV4, raw[12] | (raw[13] << 8) | (raw[14] << 16) | ((u32)raw[15] << 24));
		dev->ipv4 = get_unaligned_be32(&raw[12]);
	}
	return 0;
}

static int yuanrdma_del_gid(const struct ib_gid_attr *attr, void **context)
{
	return 0;
}

/* ---------------------------------------------------------------- ucontext / mmap */
static struct rdma_user_mmap_entry *yuanrdma_insert_mmap(struct yuanrdma_ucontext *context, bool is_doorbell,
							 struct yuanrdma_ring *ring, size_t length)
{
	struct yuanrdma_mmap_entry *entry = kzalloc(sizeof(*entry), GFP_KERNEL);

	if (!entry)
		return NULL;
	entry->is_doorbell = is_doorbell;
	entry->ring = ring;
	if (rdma_user_mmap_entry_insert(&context->ibucontext, &entry->rdma_entry, length)) {
		kfree(entry);
		return NULL;
	}
	return &entry->rdma_entry;
}

static int yuanrdma_alloc_ucontext(struct ib_ucontext *ibcontext, struct ib_udata *udata)
{
	struct yuanrdma_ucontext *context = to_yuanrdma_ucontext(ibcontext);
	struct yuanrdma_alloc_ucontext_resp response = {};
	int ret;

	mutex_init(&context->ring_lock);
	INIT_LIST_HEAD(&context->rings);
	context->doorbell_entry = yuanrdma_insert_mmap(context, true, NULL, PAGE_SIZE);
	if (!context->doorbell_entry)
		return -ENOMEM;
	response.doorbell_mmap_key = rdma_user_mmap_get_offset(context->doorbell_entry);
	response.max_qp = YNRDMA_MAX_QP;
	response.max_cq = YNRDMA_MAX_CQ;
	ret = ib_copy_to_udata(udata, &response, min(udata->outlen, sizeof(response)));
	if (ret)
		rdma_user_mmap_entry_remove(context->doorbell_entry);
	return ret;
}

static void yuanrdma_dealloc_ucontext(struct ib_ucontext *ibcontext)
{
	struct yuanrdma_ucontext *context = to_yuanrdma_ucontext(ibcontext);
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibcontext->device);
	struct yuanrdma_ring *ring, *next;

	rdma_user_mmap_entry_remove(context->doorbell_entry);
	list_for_each_entry_safe(ring, next, &context->rings, node) {
		dma_free_coherent(&dev->pdev->dev, ring->size, ring->cpu_address, ring->dma_address);
		kfree(ring);
	}
}

static int yuanrdma_mmap(struct ib_ucontext *ibcontext, struct vm_area_struct *vma)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibcontext->device);
	struct rdma_user_mmap_entry *rdma_entry;
	struct yuanrdma_mmap_entry *entry;
	int ret;

	rdma_entry = rdma_user_mmap_entry_get(ibcontext, vma);
	if (!rdma_entry)
		return -EINVAL;
	entry = container_of(rdma_entry, struct yuanrdma_mmap_entry, rdma_entry);
	if (entry->is_doorbell) {
		ret = rdma_user_mmap_io(ibcontext, vma, PHYS_PFN(dev->doorbell_phys), PAGE_SIZE,
					pgprot_noncached(vma->vm_page_prot), rdma_entry);
	} else {
		vma->vm_pgoff = 0;
		ret = dma_mmap_coherent(&dev->pdev->dev, vma, entry->ring->cpu_address,
					entry->ring->dma_address, entry->ring->size);
	}
	rdma_user_mmap_entry_put(rdma_entry);
	return ret;
}

static void yuanrdma_mmap_free(struct rdma_user_mmap_entry *rdma_entry)
{
	kfree(container_of(rdma_entry, struct yuanrdma_mmap_entry, rdma_entry));
}

/* 物理连续环；挂在 ucontext 上，ucontext 释放时一起释放 */
static struct yuanrdma_ring *yuanrdma_alloc_ring(struct yuanrdma_dev *dev, struct yuanrdma_ucontext *context,
						 size_t size)
{
	struct yuanrdma_ring *ring = kzalloc(sizeof(*ring), GFP_KERNEL);

	if (!ring)
		return NULL;
	ring->size = PAGE_ALIGN(size);
	ring->cpu_address = dma_alloc_coherent(&dev->pdev->dev, ring->size, &ring->dma_address, GFP_KERNEL);
	if (!ring->cpu_address) {
		kfree(ring);
		return NULL;
	}
	ring->mmap_entry = yuanrdma_insert_mmap(context, false, ring, ring->size);
	if (!ring->mmap_entry) {
		dma_free_coherent(&dev->pdev->dev, ring->size, ring->cpu_address, ring->dma_address);
		kfree(ring);
		return NULL;
	}
	mutex_lock(&context->ring_lock);
	list_add(&ring->node, &context->rings);
	mutex_unlock(&context->ring_lock);
	return ring;
}

static void yuanrdma_release_ring(struct yuanrdma_ring *ring)
{
	if (ring && ring->mmap_entry) {
		rdma_user_mmap_entry_remove(ring->mmap_entry);	/* 不再允许新 mmap；内存在 ucontext 释放时回收 */
		ring->mmap_entry = NULL;
	}
}

static int yuanrdma_alloc_index(struct yuanrdma_dev *dev, unsigned long *bitmap, unsigned int size)
{
	unsigned int index;

	spin_lock(&dev->alloc_lock);
	index = find_first_zero_bit(bitmap, size);
	if (index < size)
		set_bit(index, bitmap);
	spin_unlock(&dev->alloc_lock);
	return index < size ? (int)index : -ENOSPC;
}

static void yuanrdma_free_index(struct yuanrdma_dev *dev, unsigned long *bitmap, unsigned int index)
{
	spin_lock(&dev->alloc_lock);
	clear_bit(index, bitmap);
	spin_unlock(&dev->alloc_lock);
}
/* ---------------------------------------------------------------- PD */
static int yuanrdma_alloc_pd(struct ib_pd *ibpd, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibpd->device);
	int number = yuanrdma_alloc_index(dev, dev->pd_used, 65536);

	if (number < 0)
		return number;
	to_yuanrdma_pd(ibpd)->pd_number = number;
	return 0;
}

static int yuanrdma_dealloc_pd(struct ib_pd *ibpd, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibpd->device);

	yuanrdma_free_index(dev, dev->pd_used, to_yuanrdma_pd(ibpd)->pd_number);
	return 0;
}

/* ---------------------------------------------------------------- MR */
static int yuanrdma_alloc_mtt(struct yuanrdma_dev *dev, u32 count)
{
	unsigned int groups = DIV_ROUND_UP(count, YUANRDMA_MTT_GROUP);
	unsigned int total = YNRDMA_MAX_MTT / YUANRDMA_MTT_GROUP;
	unsigned long first;

	spin_lock(&dev->alloc_lock);
	first = bitmap_find_next_zero_area(dev->mtt_used, total, 0, groups, 0);
	if (first < total)
		bitmap_set(dev->mtt_used, first, groups);
	spin_unlock(&dev->alloc_lock);
	return first < total ? (int)(first * YUANRDMA_MTT_GROUP) : -ENOSPC;
}

static void yuanrdma_free_mtt(struct yuanrdma_dev *dev, u32 base, u32 count)
{
	spin_lock(&dev->alloc_lock);
	bitmap_clear(dev->mtt_used, base / YUANRDMA_MTT_GROUP, DIV_ROUND_UP(count, YUANRDMA_MTT_GROUP));
	spin_unlock(&dev->alloc_lock);
}

static u32 yuanrdma_access_bits(int access_flags)
{
	u32 bits = 0;

	if (access_flags & IB_ACCESS_LOCAL_WRITE)
		bits |= YNRDMA_ACC_LOCAL_WRITE;
	if (access_flags & IB_ACCESS_REMOTE_WRITE)
		bits |= YNRDMA_ACC_REMOTE_WRITE;
	if (access_flags & IB_ACCESS_REMOTE_READ)
		bits |= YNRDMA_ACC_REMOTE_READ;
	if (access_flags & IB_ACCESS_REMOTE_ATOMIC)
		bits |= YNRDMA_ACC_REMOTE_ATOMIC;
	return bits;
}

/* reg_user_mr / reg_user_mr_dmabuf 共同接受的 access 标志 */
static bool yuanrdma_access_supported(int access_flags)
{
	return !(access_flags & ~(IB_ACCESS_LOCAL_WRITE | IB_ACCESS_REMOTE_WRITE |
				  IB_ACCESS_REMOTE_READ | IB_ACCESS_RELAXED_ORDERING));
}

/*
 * 单个 4 KB 块 DMA 地址的可用性判定。
 *
 *   - 地址为 0：sg 项没拿到有效总线地址 —— nvidia-peermem 没加载、BAR/peer 窗口没打通、
 *     或 dma-buf 没 pin/map 成功时的典型表现。MTT 里写 0 不会在注册期报错，
 *     数据面会把读写静默发到物理地址 0，事后极难定位。
 *   - 低 12 位非 0：硬件 MTT 项只存 4 KB 页首地址，非对齐会指向错误的页。
 *
 * 纯函数、无副作用、不依赖 umem，按下面的标记可整段抽出来单独测试。
 */
/* YNRDMA_DMA_CHECK_BEGIN */
static int yuanrdma_check_dma_addr(u64 dma)
{
	if (!dma)
		return -EFAULT;
	if (dma & (SZ_4K - 1))
		return -EINVAL;
	return 0;
}
/* YNRDMA_DMA_CHECK_END */

/*
 * 注册前逐 4 KB 块校验 umem 的 DMA 地址。
 *
 * 调用点只有一个：yuanrdma_register_umem() 的入口。普通 reg_user_mr（ib_umem_get，
 * 含 nvidia-peermem 接管的 GPU 显存）与 reg_user_mr_dmabuf（ib_umem_dmabuf_get_pinned）
 * 最终都汇到那里，新增第三条注册路径也不会漏。此前只有 dmabuf 那条路有这套校验，
 * 而 peermem 走的恰恰是普通 reg_user_mr —— 正是盲区。
 *
 * rdma_umem_for_each_dma_block() 给出的地址已经按 pgsz 掩过码，pgsz=4 KB 时
 * 「非 4 KB 对齐」这一条不会触发，它是防以后把 pgsz 改小的契约检查；
 * 现场真正会命中的是「地址为 0」。
 *
 * 失败打一条 ratelimited 日志：注册失败通常跟着应用层循环重试，普通 dev_err 会刷屏。
 * src 是注册来源（普通路径的用户态地址 / dma-buf 偏移），只出现在日志里。
 */
static int yuanrdma_check_dma_blocks(struct yuanrdma_dev *dev, struct ib_umem *umem,
				     bool is_dmabuf, u64 src, u64 virtual_address)
{
	struct ib_block_iter block;
	size_t total = ib_umem_num_dma_blocks(umem, SZ_4K);
	size_t i = 0;

	rdma_umem_for_each_dma_block(umem, &block, SZ_4K) {
		u64 dma = rdma_block_iter_dma_address(&block);
		int ret = yuanrdma_check_dma_addr(dma);

		if (ret) {
			dev_err_ratelimited(&dev->pdev->dev,
					    "%s MR 第 %zu/%zu 个 4 KB 块 DMA 地址 %#llx 不可用"
					    "（src %#llx va %#llx len %#zx）：%s\n",
					    is_dmabuf ? "dmabuf" : "user", i, total,
					    dma, src, virtual_address, umem->length,
					    ret == -EFAULT ?
					    "地址为 0，nvidia-peermem 未加载或 BAR/peer 窗口未打通？" :
					    "不是 4 KB 页首地址，硬件 MTT 表达不了");
			return ret;
		}
		i++;
	}
	if (!i) {
		dev_err_ratelimited(&dev->pdev->dev,
				    "%s MR（src %#llx va %#llx len %#zx）一个 4 KB DMA 块都没有，"
				    "拒绝注册：MPT 长度非 0 而 MTT 为空，数据面会读到垃圾地址\n",
				    is_dmabuf ? "dmabuf" : "user", src, virtual_address,
				    umem->length);
		return -EINVAL;
	}
	return 0;
}

/*
 * 把 umem 的 DMA 页写成 MTT，返回错误码。
 *
 * 两条注册路径（锁页 ib_umem_get / dma-buf ib_umem_dmabuf_get_pinned）共用：
 *   - 页大小固定 4 KB（硬件 MTT 项 = 4 KB 页首地址，低 12 位必须为 0）；
 *   - 每 8 项凑一条 TBL_MTT 命令（YUANRDMA_MTT_GROUP），最后不满 8 项补 0 再写；
 *   - 写表失败立即返回，调用方按自己的顺序回滚。
 *
 * 地址可用性（非 0、4 KB 对齐）不在这里判：注册入口统一走
 * yuanrdma_check_dma_blocks()，本函数只负责「怎么遍历、怎么分批写」。
 */
static int yuanrdma_write_mtt(struct yuanrdma_dev *dev, struct ib_umem *umem, u32 mtt_base)
{
	struct ib_block_iter block;
	u64 entries[YUANRDMA_MTT_GROUP];
	u32 filled = 0, written = 0;
	int ret;

	rdma_umem_for_each_dma_block(umem, &block, SZ_4K) {
		entries[filled++] = rdma_block_iter_dma_address(&block);
		if (filled == YUANRDMA_MTT_GROUP) {
			ret = yuanrdma_write_table(dev, YNRDMA_CMD_TBL_MTT, mtt_base + written,
						   entries, sizeof(entries));
			if (ret)
				return ret;
			written += filled;
			filled = 0;
		}
	}
	if (filled) {
		memset(&entries[filled], 0, (YUANRDMA_MTT_GROUP - filled) * sizeof(u64));
		ret = yuanrdma_write_table(dev, YNRDMA_CMD_TBL_MTT, mtt_base + written,
					   entries, sizeof(entries));
		if (ret)
			return ret;
	}
	return 0;
}

/*
 * 两条注册路径的公共后半段：校验 DMA 地址、分配 MTT 区与 MR 索引、写 MTT、写 MPT。
 * src 是注册来源（普通路径的用户态地址 / dma-buf 偏移），只用于失败日志。
 * umem 的所有权在这里转移（成功或失败都由本函数或调用方的回滚释放）。
 */
static struct ib_mr *yuanrdma_register_umem(struct ib_pd *ibpd, struct ib_umem *umem,
					    struct ib_umem_dmabuf *umem_dmabuf,
					    u64 src, u64 length, u64 virtual_address,
					    int access_flags)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibpd->device);
	struct yuanrdma_mr *mr;
	struct ynrdma_mpt mpt = {};
	int ret, index;

	if (!yuanrdma_access_supported(access_flags)) {
		ret = -EOPNOTSUPP;
		goto release_umem;
	}
	mr = kzalloc(sizeof(*mr), GFP_KERNEL);
	if (!mr) {
		ret = -ENOMEM;
		goto release_umem;
	}
	mr->umem = umem;
	mr->umem_dmabuf = umem_dmabuf;	/* 非 dmabuf 路径传 NULL */
	/* MTT 第 0 项 = 包含 virtual_address 的那一页（硬件按 (va & ~4K) 计算页号） */
	umem->iova = virtual_address;
	mr->mtt_count = ib_umem_num_dma_blocks(umem, SZ_4K);
	if (mr->mtt_count > YNRDMA_MAX_MTT) {
		ret = -E2BIG;
		goto free_mr;
	}
	/* DMA 地址校验（非 0、4 KB 对齐）放在两处判断之后：
	 *   - 在 MTT 上限判断之后：超限的 MR（peermem 下 512 MB+ 很常见）直接报 -E2BIG，
	 *     不必先白走一遍整表——4 GB 是 100 万项，纯空转；
	 *   - 在 umem->iova = virtual_address 之后：ib_umem_num_dma_blocks() 的 total 才与
	 *     mr->mtt_count 同口径（此前 total 用的是覆盖前的 iova，dmabuf 路径会差 1）。
	 * 仍在 alloc_mtt/alloc_index 之前：失败不留半张表、不占硬件槽。
	 * 剩一次额外遍历（与 yuanrdma_write_mtt 各走一遍）；要省掉得把校验并进写表循环，
	 * 那是改公共路径，留待有实测需要时再做。 */
	ret = yuanrdma_check_dma_blocks(dev, umem, umem_dmabuf != NULL, src, virtual_address);
	if (ret)
		goto free_mr;
	ret = yuanrdma_alloc_mtt(dev, mr->mtt_count);
	if (ret < 0)
		goto free_mr;
	mr->mtt_base = ret;
	index = yuanrdma_alloc_index(dev, dev->mr_used, YNRDMA_MAX_MR);
	if (index < 0) {
		ret = index;
		goto free_mtt;
	}
	mr->mr_index = index;

	ret = yuanrdma_write_mtt(dev, umem, mr->mtt_base);
	if (ret)
		goto free_index;

	mr->ibmr.lkey = mr->ibmr.rkey = (get_random_u32() << 8) | mr->mr_index;
	mpt.dw0 = 1 | (yuanrdma_access_bits(access_flags) << 1) | (to_yuanrdma_pd(ibpd)->pd_number << 16);
	mpt.key = mr->ibmr.lkey;
	mpt.va = virtual_address;
	mpt.len = length;
	mpt.mtt_base = mr->mtt_base;
	ret = yuanrdma_write_table(dev, YNRDMA_CMD_TBL_MPT, mr->mr_index, &mpt, sizeof(mpt));
	if (ret)
		goto free_index;
	return &mr->ibmr;

free_index:
	yuanrdma_free_index(dev, dev->mr_used, mr->mr_index);
free_mtt:
	yuanrdma_free_mtt(dev, mr->mtt_base, mr->mtt_count);
free_mr:
	kfree(mr);
release_umem:
	yuanrdma_umem_put(umem, umem_dmabuf);
	return ERR_PTR(ret);
}

static struct ib_mr *yuanrdma_reg_user_mr(struct ib_pd *ibpd, u64 start, u64 length, u64 virtual_address,
					  int access_flags, struct ib_udata *udata)
{
	struct ib_umem *umem;

	if (!yuanrdma_access_supported(access_flags))
		return ERR_PTR(-EOPNOTSUPP);
	umem = ib_umem_get(ibpd->device, start, length, access_flags);
	if (IS_ERR(umem))
		return ERR_CAST(umem);
	return yuanrdma_register_umem(ibpd, umem, NULL, start, length, virtual_address, access_flags);
}

/*
 * dma-buf（GPUDirect RDMA）导入。
 *
 * 【未上板验证】本机没有 nvidia_peermem，也没有 GPU，这条路径只用编译器验证过。
 * 上板前的判据与已知边界：
 *   1) peermem 缺失时 dma_buf_pin() 由 exporter（nvidia 驱动）拒绝，ib_umem_dmabuf_get_pinned()
 *      返回 -EOPNOTSUPP/-EPERM —— 这里原样把它传上去，不伪造成功，不写 MPT/MTT。
 *   2) DMA 地址校验（非 0、4 KB 对齐）在 yuanrdma_register_umem() 入口做，
 *      与普通 reg_user_mr 共用同一份实现（yuanrdma_check_dma_blocks()），这里不再重复 ——
 *      两条注册路径都绕不过去。地址为 0 返回 -EFAULT（peermem/BAR 没通），
 *      未 4 KB 对齐返回 -EINVAL；宁可注册失败也不发出「DMA 写到错误物理地址」的 MPT。
 *   3) 页大小固定 4 KB；dma-buf 的 offset 必须与虚拟地址在 4 KB 内同余，否则 MTT 第 0 项
 *      对不上硬件算出的页号（硬件按 (va & ~0xfff) 索引）。
 *
 * 与 reg_user_mr 的唯一区别是 umem 的来源；后半段（MTT/MPT）共用 yuanrdma_register_umem()。
 */
#ifdef YUANRDMA_HAVE_UMEM_DMABUF_PINNED
static struct ib_mr *yuanrdma_reg_user_mr_dmabuf(struct ib_pd *ibpd, u64 offset, u64 length,
						 u64 virtual_address, int fd, int access_flags,
						 struct ib_udata *udata)
{
	struct ib_umem_dmabuf *umem_dmabuf;

	if (!yuanrdma_access_supported(access_flags))
		return ERR_PTR(-EOPNOTSUPP);
	/* 非 4 KB 对齐的组合硬件表达不了（MTT 只索引 4 KB 页），在进内核 API 之前就拒掉 */
	if (offset_in_page(offset) != offset_in_page(virtual_address))
		return ERR_PTR(-EINVAL);

	umem_dmabuf = ib_umem_dmabuf_get_pinned(ibpd->device, offset, length, fd, access_flags);
	if (IS_ERR(umem_dmabuf))
		return ERR_CAST(umem_dmabuf);

	/* DMA 地址校验在 register_umem() 入口，与普通 reg_user_mr 共用 */
	return yuanrdma_register_umem(ibpd, &umem_dmabuf->umem, umem_dmabuf, offset, length,
				      virtual_address, access_flags);
}
#endif /* YUANRDMA_HAVE_UMEM_DMABUF_PINNED */

static int yuanrdma_dereg_mr(struct ib_mr *ibmr, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibmr->device);
	struct yuanrdma_mr *mr = to_yuanrdma_mr(ibmr);
	struct ynrdma_mpt mpt = {};		/* valid = 0 */

	if (mr->dma_mr) {			/* get_dma_mr 的哑 MR，不碰硬件 */
		kfree(mr);
		return 0;
	}
	yuanrdma_write_table(dev, YNRDMA_CMD_TBL_MPT, mr->mr_index, &mpt, sizeof(mpt));
	yuanrdma_free_index(dev, dev->mr_used, mr->mr_index);
	yuanrdma_free_mtt(dev, mr->mtt_base, mr->mtt_count);
	yuanrdma_umem_put(mr->umem, mr->umem_dmabuf);
	kfree(mr);
	return 0;
}

/* ---------------------------------------------------------------- CQ */
static int yuanrdma_create_cq(struct ib_cq *ibcq, const struct ib_cq_init_attr *attr, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibcq->device);
	struct yuanrdma_ucontext *context = rdma_udata_to_drv_context(udata, struct yuanrdma_ucontext, ibucontext);
	struct yuanrdma_cq *cq = to_yuanrdma_cq(ibcq);
	struct yuanrdma_create_cq_resp response = {};
	struct ynrdma_cqc cqc = {};
	struct yuanrdma_ring *ring;
	int index, ret;

	if (!udata)
		return yuanrdma_kernel_create_cq(cq, attr);	/* 内核 CQ（MAD 层 QP1）：纯软件，不占硬件槽 */
	if (attr->flags || attr->cqe < 1 || attr->cqe >= YUANRDMA_MAX_CQ_DEPTH)
		return -EINVAL;
	cq->log2_depth = max(order_base_2(attr->cqe + 1), 4);
	index = yuanrdma_alloc_index(dev, dev->cq_used, YNRDMA_MAX_CQ);
	if (index < 0)
		return index;
	cq->cq_index = index;
	ring = yuanrdma_alloc_ring(dev, context, sizeof(struct ynrdma_cqe) << cq->log2_depth);
	if (!ring) {
		ret = -ENOMEM;
		goto free_index;
	}
	cqc.base_lo = lower_32_bits(ring->dma_address);
	cqc.base_hi = upper_32_bits(ring->dma_address);
	cqc.dw2 = 1 | (cq->log2_depth << 1);
	ret = yuanrdma_write_table(dev, YNRDMA_CMD_TBL_CQC, cq->cq_index, &cqc, sizeof(cqc));
	if (ret)
		goto free_ring;
	cq->ring = ring;
	ibcq->cqe = (1 << cq->log2_depth) - 1;
	response.ring_mmap_key = rdma_user_mmap_get_offset(ring->mmap_entry);
	response.cq_index = cq->cq_index;
	response.log2_depth = cq->log2_depth;
	ret = ib_copy_to_udata(udata, &response, min(udata->outlen, sizeof(response)));
	if (ret)
		goto free_ring;
	return 0;

free_ring:
	yuanrdma_release_ring(ring);
free_index:
	yuanrdma_free_index(dev, dev->cq_used, cq->cq_index);
	return ret;
}

static int yuanrdma_destroy_cq(struct ib_cq *ibcq, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibcq->device);
	struct yuanrdma_cq *cq = to_yuanrdma_cq(ibcq);
	struct ynrdma_cqc cqc = {};		/* valid = 0 */

	if (cq->software) {
		yuanrdma_kernel_destroy_cq(cq);
		return 0;
	}
	yuanrdma_write_table(dev, YNRDMA_CMD_TBL_CQC, cq->cq_index, &cqc, sizeof(cqc));
	yuanrdma_release_ring(cq->ring);
	yuanrdma_free_index(dev, dev->cq_used, cq->cq_index);
	return 0;
}
/* ---------------------------------------------------------------- QP */
static int yuanrdma_create_qp(struct ib_qp *ibqp, struct ib_qp_init_attr *init, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibqp->device);
	struct yuanrdma_ucontext *context = rdma_udata_to_drv_context(udata, struct yuanrdma_ucontext, ibucontext);
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibqp);
	struct yuanrdma_create_qp_resp response = {};
	int index, ret;

	/* 内核 QP1（MAD/CM 用）：软件 QP，不占硬件槽 */
	if (!udata) {
		if (init->qp_type != IB_QPT_GSI)
			return -EOPNOTSUPP;
		memset(&qp->context, 0, sizeof(qp->context));
		return yuanrdma_gsi_create_qp(qp, init);
	}
	/* G2.1／UD：RC 与 UD 都支持，没有开关（2026-11-21 起）。
	 *   UD —— 契约见 §76：WQE opcode 5/6、dw9=remote_qpn、dw10=remote_qkey、
	 *         CQE dw4=src_qp / dw0[18]=has_grh。B6458/B6459 比特流已实测可用；
	 *         更老的比特流里 WQE 5/6 没有 case，会静默组出 RC 形态的包，
	 *         那种镜像上不要建 UD QP（见 yuanrdma_driver.h 顶部说明）。
	 *   两者都不支持 SRQ / create_flags。
	 */
	if (init->srq || init->create_flags)
		return -EOPNOTSUPP;
	if (init->qp_type != IB_QPT_RC && init->qp_type != IB_QPT_UD)
		return -EOPNOTSUPP;
	/*
	 * max_recv_sge：UD 与 RC 都只给 1。
	 * 任务书提到「UD 的 max_recv_sge 需要 2（payload + SGID）」，但 IB 语义里 UD 收到的
	 * GRH 是**拼在第一个 SGE 缓冲区的最前面**（RQ WQE 只有一片缓冲，硬件按
	 * ynrdma_rq_wqe.addr/length 写 GRH+payload，CQE 的 has_grh 告诉用户态前 40 B 是 GRH），
	 * 不是写进第二个 SGE。本卡 RQ WQE（yuanrdma_hw.h:238-243）也只有 addr/length/lkey 一组，
	 * 报 2 会让 provider 收 WR 时放行第二个 SGE，而硬件根本没地方写——静默丢数据。
	 * 所以这里对 UD 仍要求 <= 1，环大小检查不变。
	 */
	if (init->cap.max_send_sge > 1 || init->cap.max_recv_sge > 1 || init->cap.max_inline_data > 0 ||
	    init->cap.max_send_wr >= YUANRDMA_MAX_SQ_DEPTH || init->cap.max_recv_wr >= YUANRDMA_MAX_RQ_DEPTH)
		return -EINVAL;
	/* 环里留一个空槽区分满/空，所以深度要 > 请求的 WR 数（perftest 一次挂满 tx_depth 个） */
	qp->sq_log2_depth = max(order_base_2(init->cap.max_send_wr + 1), 2);
	qp->rq_log2_depth = max(order_base_2(init->cap.max_recv_wr + 1), 2);
	index = yuanrdma_alloc_index(dev, dev->qp_used, YNRDMA_MAX_QP);
	if (index < 0)
		return index;
	qp->qp_index = index;
	ibqp->qp_num = YNRDMA_QPN_BASE + qp->qp_index;

	qp->sq_ring = yuanrdma_alloc_ring(dev, context, sizeof(struct ynrdma_sq_wqe) << qp->sq_log2_depth);
	qp->rq_ring = yuanrdma_alloc_ring(dev, context, sizeof(struct ynrdma_rq_wqe) << qp->rq_log2_depth);
	if (!qp->sq_ring || !qp->rq_ring) {
		ret = -ENOMEM;
		goto release;
	}
	memset(&qp->context, 0, sizeof(qp->context));
	qp->qp_type = init->qp_type;
	/* QPC dw0 的 CQ 位段（S6）：send_cq [11:6]、recv_cq [17:12]，各 6 bit。
	 * yuanrdma_alloc_index(..., YNRDMA_MAX_CQ) 分配出的 cq_index 天然落在
	 * 0..YNRDMA_MAX_CQ-1，与 CQ_W=6 一致。位段宽度是 RTL 定的契约，改 CQ 数量必须
	 * 同时改 roce_pkg.sv 的 qpc_scq/qpc_rcq 与 ynrdma_qpc.dw0 注释。 */
	BUILD_BUG_ON(YNRDMA_MAX_CQ > 64);	/* QPC dw0 的 scq/rcq 各 6 bit，超出即静默截断 */
	BUILD_BUG_ON(YNRDMA_MAX_CQ & (YNRDMA_MAX_CQ - 1));	/* 必须是 2 的幂（alloc 位图 + 位段） */
	/* dw0[21] = qp_type（1 = UD）。RTL 的 roce_req 用它校验「WQE opcode 是 UD」与
	 * 「QP 本身是 UD」是否一致；不写这一位时 RC QP 里混进 UD WQE 会直接发出 0x64。 */
	qp->context.dw0 = YNRDMA_QPS_RESET | (to_yuanrdma_cq(init->send_cq)->cq_index << 6) |
			  (to_yuanrdma_cq(init->recv_cq)->cq_index << 12) |
			  ((init->qp_type == IB_QPT_UD) ? (1u << 21) : 0u);
	qp->context.sq_base_lo = lower_32_bits(qp->sq_ring->dma_address);
	qp->context.sq_base_hi = upper_32_bits(qp->sq_ring->dma_address);
	qp->context.rq_base_lo = lower_32_bits(qp->rq_ring->dma_address);
	qp->context.rq_base_hi = upper_32_bits(qp->rq_ring->dma_address);
	qp->context.dw12 = qp->sq_log2_depth | (qp->rq_log2_depth << 4) |
			   (to_yuanrdma_pd(ibqp->pd)->pd_number << 16);
	ret = yuanrdma_write_table(dev, YNRDMA_CMD_TBL_QPC, qp->qp_index, &qp->context, sizeof(qp->context));
	if (ret)
		goto release;
	qp->state = IB_QPS_RESET;

	init->cap.max_send_wr = (1 << qp->sq_log2_depth) - 1;
	init->cap.max_recv_wr = (1 << qp->rq_log2_depth) - 1;
	init->cap.max_send_sge = 1;
	init->cap.max_recv_sge = 1;
	init->cap.max_inline_data = 0;
	response.sq_mmap_key = rdma_user_mmap_get_offset(qp->sq_ring->mmap_entry);
	response.rq_mmap_key = rdma_user_mmap_get_offset(qp->rq_ring->mmap_entry);
	response.qp_index = qp->qp_index;
	response.sq_log2_depth = qp->sq_log2_depth;
	response.rq_log2_depth = qp->rq_log2_depth;
	response.max_inline_data = 0;
	ret = ib_copy_to_udata(udata, &response, min(udata->outlen, sizeof(response)));
	if (ret)
		goto release;
	return 0;

release:
	yuanrdma_release_ring(qp->sq_ring);
	yuanrdma_release_ring(qp->rq_ring);
	yuanrdma_free_index(dev, dev->qp_used, qp->qp_index);
	return ret;
}

static u32 yuanrdma_state_code(enum ib_qp_state state)
{
	switch (state) {
	case IB_QPS_RESET: return YNRDMA_QPS_RESET;
	case IB_QPS_INIT:  return YNRDMA_QPS_INIT;
	case IB_QPS_RTR:   return YNRDMA_QPS_RTR;
	case IB_QPS_RTS:   return YNRDMA_QPS_RTS;
	default:           return YNRDMA_QPS_ERR;
	}
}

static int yuanrdma_modify_qp(struct ib_qp *ibqp, struct ib_qp_attr *attr, int mask, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibqp->device);
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibqp);
	struct ynrdma_qpc *context = &qp->context;
	enum ib_qp_state current_state = (mask & IB_QP_CUR_STATE) ? attr->cur_qp_state : qp->state;
	enum ib_qp_state new_state = (mask & IB_QP_STATE) ? attr->qp_state : current_state;
	u32 tos = (context->dw7 >> 16) & 0xff, ttl = context->dw7 >> 24;

	if (udata && udata->inlen)
		return -EOPNOTSUPP;
	if (qp->gsi)
		return yuanrdma_gsi_modify_qp(qp, attr, mask);
	if (!ib_modify_qp_is_ok(current_state, new_state, ibqp->qp_type, mask))
		return -EINVAL;
	/*
	 * UD 到 RTR/RTS 却没写过 AV：**只告警，不拒绝**。
	 *
	 * 内核的 qp_state_table（verbs.c:1441-1470）把 UD 的 IB_QP_AV 列为可选，
	 * 而 rdma_cm 的 UD 建链路径（cma_ib_init_qp_attr，cma.c:1231-1263）确实**从不**带
	 * IB_QP_AV——它把 AH 通过 event->param.ud.ah_attr 交给应用，由应用在每条 WR 上带。
	 * 所以在这里硬拒会把 ucmatose / rping -U 这类标准用法整个挡死。
	 *
	 * 但本卡的 RTL 是从 QPC 组 Eth/IP/UDP 头的（dst_mac_lo / dw4 / dst_ip，见 roce_tx 的
	 * header_computed），WQE 里只有 remote_qpn 与 qkey（§76 契约）。也就是说：
	 * rdma_cm 这种用法在本卡上会把帧发往 00:00:00:00:00:00 / 0.0.0.0。
	 * 这是一个「协议合法、实现不支持」的组合，正确做法是把它变成**响声**而不是静默：
	 * 建链照常成功（不改行为），dmesg 明确说明后续 SEND 会发到零地址，
	 * 提示改用带 AV 的 modify_qp（perftest -R 之外的自建路径）或等 QPC 支持 per-WR AH。
	 */
	if (ibqp->qp_type == IB_QPT_UD &&
	    (new_state == IB_QPS_RTR || new_state == IB_QPS_RTS) &&
	    !(mask & IB_QP_AV) && !qp->attributes.ah_attr.type)
		dev_warn_ratelimited(&dev->pdev->dev,
				     "UD QP %u 进 RTR/RTS 但从未设置 AV：本卡从 QPC 组 Eth/IP 头，"
				     "此 QP 上发出的 UD SEND 会落到 0.0.0.0/00:00:00:00:00:00（rdma_cm 的 UD 用法）\n",
				     ibqp->qp_num);

	/* QPC 的 pmtu 是 3 bit 的 IB 枚举，RTL 按 128 << code 换成 13 bit 字节数
	 * （roce_pkg.sv qpc_pmtu/pmtu_bytes）：code 6/7 会得到 0 字节、0 只有 128 字节，
	 * 都不是合法 path MTU，挡在这里。IB_MTU_4096 = 5 合法（需两端 netdev MTU >= 4192）。 */
	if ((mask & IB_QP_PATH_MTU) &&
	    (attr->path_mtu < IB_MTU_256 || attr->path_mtu > IB_MTU_4096))
		return -EINVAL;

	/*
	 * UD 到 RTR/RTS 却没带 IB_QP_PATH_MTU：按端口 active_mtu 兜底写 QPC。
	 *
	 * 为什么必须兜这一手（2026-11-18 B6502 实测）：
	 *   rc 路径的 modify_qp 一定带 IB_QP_AV|IB_QP_PATH_MTU，但 **UD 路径不带**——
	 *   perftest 的 perftest_resources.c:3555 只在 connection_type != UD 时才置
	 *   IBV_QP_PATH_MTU；rdma-core 的 ud_pingpong.c 压根不设。而 roce_req 的 UD 长度闸
	 *   （roce_req.sv:799 `wqe_length > pmtu_bytes(qpc_pmtu)`）读的就是 QPC 这一位段，
	 *   留 0 等于把 UD 单包上限钉死在 128 B：64/128 B 通、256 B 起全部
	 *   Local Length Error。用户看到的只是「UD 只能发 128 字节」，而根因在 QPC 没写。
	 *
	 * 选 active_mtu 而不是 max_mtu：active_mtu 来自 netdev MTU（yuanrdma_query_port
	 * 的 iboe_get_mtu），是这条链路真的能过的帧长；用 max_mtu(4096) 会在 netdev 只有
	 * 1500 时让 UD 发出 4 KB 单包，对端按 MTU 丢包——又是「看起来成功、对端收不到」。
	 * 显式给了 IB_QP_PATH_MTU 时一律以调用方为准（上面的合法性校验已挡住 6/7）。
	 */
	if (ibqp->qp_type == IB_QPT_UD &&
	    (new_state == IB_QPS_RTR || new_state == IB_QPS_RTS) &&
	    !(mask & IB_QP_PATH_MTU) && !(context->dw0 & (7u << 3))) {
		enum ib_mtu mtu = iboe_get_mtu(dev->netdev->mtu);

		if (mtu < IB_MTU_256 || mtu > IB_MTU_4096)
			mtu = IB_MTU_1024;	/* netdev 太小/异常时的保守兜底 */
		context->dw0 = (context->dw0 & ~(7u << 3)) | ((mtu & 7) << 3);
	}

	if (mask & IB_QP_ACCESS_FLAGS) {
		/* S6：remote_write/read/atomic 从 [16]/[17]/[18] 挪到 [18]/[19]/[20]
		 * （recv_cq 需要 [17:12] 这 6 位）。RTL 不读这三位——访问权限由 MPT 的
		 * YNRDMA_ACC_* 决定——但它们仍要与 ynrdma_qpc.dw0 的注释一致，
		 * 否则将来谁按位读 QPC 就会读到别人的字段。 */
		context->dw0 &= ~(7u << 18);
		if (attr->qp_access_flags & IB_ACCESS_REMOTE_WRITE)
			context->dw0 |= 1u << 18;
		if (attr->qp_access_flags & IB_ACCESS_REMOTE_READ)
			context->dw0 |= 1u << 19;
		if (attr->qp_access_flags & IB_ACCESS_REMOTE_ATOMIC)
			context->dw0 |= 1u << 20;
	}
	if (mask & IB_QP_PATH_MTU)
		context->dw0 = (context->dw0 & ~(7u << 3)) | ((attr->path_mtu & 7) << 3);
	if (mask & IB_QP_DEST_QPN)
		context->dest_qpn = attr->dest_qp_num & 0xffffff;
	/*
	 * UD 的 Q_Key 不落 QPC：契约规定它随每个 WQE 走（dw10），因为同一个 UD QP 允许
	 * 发往不同 Q_Key（AH 是 per-WR 的），写进 QPC 就把 per-WR 语义抹成 per-QP 了。
	 * 这里只接受并忽略 IB_QP_QKEY，不报错：ib_modify_qp 到 UD 的 RTS 会带这个 mask，
	 * 拒绝它等于让 UD QP 永远起不来。值本身由 provider 在 post_send 里从 AH 取。
	 */
	if (mask & IB_QP_RQ_PSN)
		context->rq_psn = attr->rq_psn & 0xffffff;
	if (mask & IB_QP_SQ_PSN)
		context->sq_psn = attr->sq_psn & 0xffffff;
	if (mask & IB_QP_AV) {
		const struct ib_global_route *route = rdma_ah_read_grh(&attr->ah_attr);
		const u8 *mac = attr->ah_attr.roce.dmac;
		const u8 *gid = route->dgid.raw;
		u32 flow_label = route->flow_label;

		if (!route->sgid_attr || route->sgid_attr->gid_type != IB_GID_TYPE_ROCE_UDP_ENCAP ||
		    !ipv6_addr_v4mapped((struct in6_addr *)gid))
			return -EOPNOTSUPP;		/* 只支持 RoCEv2 + IPv4（perftest 用 -x <v2 IPv4 GID 索引>） */
		context->dst_ip = gid[12] | (gid[13] << 8) | (gid[14] << 16) | ((u32)gid[15] << 24);
		context->dst_mac_lo = mac[0] | (mac[1] << 8) | (mac[2] << 16) | ((u32)mac[3] << 24);
		if (!flow_label)
			flow_label = rdma_calc_flow_label(ibqp->qp_num, context->dest_qpn);
		context->dw4 = mac[4] | (mac[5] << 8) |
			       ((u32)rdma_flow_label_to_udp_sport(flow_label) << 16);
		tos = route->traffic_class;
		ttl = route->hop_limit ? route->hop_limit : 64;
		if ((tos & 3) == 0)
			tos |= 2;			/* 数据包打 ECT(0) */
	}
	if (mask & IB_QP_TIMEOUT)
		context->dw7 = (context->dw7 & ~0x1fu) | (attr->timeout & 0x1f);
	if (mask & IB_QP_RETRY_CNT)
		context->dw7 = (context->dw7 & ~(7u << 5)) | ((attr->retry_cnt & 7) << 5);
	if (mask & IB_QP_RNR_RETRY)
		context->dw7 = (context->dw7 & ~(7u << 8)) | ((attr->rnr_retry & 7) << 8);
	if (mask & IB_QP_MIN_RNR_TIMER)
		context->dw7 = (context->dw7 & ~(0x1fu << 11)) | ((attr->min_rnr_timer & 0x1f) << 11);
	context->dw7 = (context->dw7 & 0xffff) | (tos << 16) | (ttl << 24);
	/* max_rd 字段 = 允许在途 READ 数 - 1 */
	if (mask & IB_QP_MAX_QP_RD_ATOMIC)
		context->dw12 = (context->dw12 & ~(0xfu << 8)) |
				((clamp_t(u32, attr->max_rd_atomic, 1, 16) - 1) << 8);
	if (mask & IB_QP_MAX_DEST_RD_ATOMIC)
		context->dw12 = (context->dw12 & ~(0xfu << 12)) |
				((clamp_t(u32, attr->max_dest_rd_atomic, 1, 16) - 1) << 12);
	context->dw0 = (context->dw0 & ~7u) | yuanrdma_state_code(new_state);

	if (yuanrdma_write_table(dev, YNRDMA_CMD_TBL_QPC, qp->qp_index, context, sizeof(*context)))
		return -EIO;
	qp->state = new_state;
	if (mask & IB_QP_AV)
		qp->attributes.ah_attr = attr->ah_attr;
	qp->attributes.path_mtu = (mask & IB_QP_PATH_MTU) ? attr->path_mtu : qp->attributes.path_mtu;
	qp->attributes.dest_qp_num = context->dest_qpn;
	qp->attributes.rq_psn = context->rq_psn;
	qp->attributes.sq_psn = context->sq_psn;
	qp->attributes.timeout = context->dw7 & 0x1f;
	qp->attributes.retry_cnt = (context->dw7 >> 5) & 7;
	qp->attributes.rnr_retry = (context->dw7 >> 8) & 7;
	qp->attributes.min_rnr_timer = (context->dw7 >> 11) & 0x1f;
	if (mask & IB_QP_ACCESS_FLAGS)
		qp->attributes.qp_access_flags = attr->qp_access_flags;
	if (mask & IB_QP_MAX_QP_RD_ATOMIC)
		qp->attributes.max_rd_atomic = attr->max_rd_atomic;
	if (mask & IB_QP_MAX_DEST_RD_ATOMIC)
		qp->attributes.max_dest_rd_atomic = attr->max_dest_rd_atomic;
	return 0;
}

static int yuanrdma_query_qp(struct ib_qp *ibqp, struct ib_qp_attr *attr, int mask, struct ib_qp_init_attr *init)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibqp->device);
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibqp);
	struct ynrdma_qpc hardware;

	if (qp->gsi)
		return yuanrdma_gsi_query_qp(qp, attr, mask, init);
	*attr = qp->attributes;
	attr->qp_state = qp->state;
	/* 硬件出错时自己把 state 置 ERR */
	if (!yuanrdma_read_table(dev, YNRDMA_CMD_TBL_QPC, qp->qp_index, &hardware, sizeof(hardware)) &&
	    (hardware.dw0 & 7) == YNRDMA_QPS_ERR)
		attr->qp_state = qp->state = IB_QPS_ERR;
	attr->cur_qp_state = attr->qp_state;
	attr->cap.max_send_wr = (1 << qp->sq_log2_depth) - 1;
	attr->cap.max_recv_wr = (1 << qp->rq_log2_depth) - 1;
	attr->cap.max_send_sge = 1;
	attr->cap.max_recv_sge = 1;
	attr->cap.max_inline_data = 0;
	memset(init, 0, sizeof(*init));
	init->qp_type = qp->qp_type;
	init->send_cq = ibqp->send_cq;
	init->recv_cq = ibqp->recv_cq;
	init->cap = attr->cap;
	init->sq_sig_type = IB_SIGNAL_REQ_WR;
	return 0;
}

static int yuanrdma_destroy_qp(struct ib_qp *ibqp, struct ib_udata *udata)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(ibqp->device);
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibqp);

	if (qp->gsi) {
		yuanrdma_gsi_destroy_qp(qp);
		return 0;
	}
	qp->context.dw0 = (qp->context.dw0 & ~7u) | YNRDMA_QPS_RESET;
	yuanrdma_write_table(dev, YNRDMA_CMD_TBL_QPC, qp->qp_index, &qp->context, sizeof(qp->context));
	yuanrdma_release_ring(qp->sq_ring);
	yuanrdma_release_ring(qp->rq_ring);
	yuanrdma_free_index(dev, dev->qp_used, qp->qp_index);
	return 0;
}

/* ---------------------------------------------------------------- ops */
const struct ib_device_ops yuanrdma_device_ops = {
	.owner = THIS_MODULE,
	.driver_id = RDMA_DRIVER_UNKNOWN,
	.uverbs_abi_ver = YUANRDMA_ABI_VERSION,

	.add_gid = yuanrdma_add_gid,
	.alloc_pd = yuanrdma_alloc_pd,
	.alloc_ucontext = yuanrdma_alloc_ucontext,
	.create_ah = yuanrdma_create_ah,
	.create_cq = yuanrdma_create_cq,
	.create_qp = yuanrdma_create_qp,
	.dealloc_pd = yuanrdma_dealloc_pd,
	.dealloc_ucontext = yuanrdma_dealloc_ucontext,
	.del_gid = yuanrdma_del_gid,
	.dereg_mr = yuanrdma_dereg_mr,
	.destroy_ah = yuanrdma_destroy_ah,
	.destroy_cq = yuanrdma_destroy_cq,
	.destroy_qp = yuanrdma_destroy_qp,
	.get_dma_mr = yuanrdma_get_dma_mr,
	.get_link_layer = yuanrdma_get_link_layer,
	.get_port_immutable = yuanrdma_get_port_immutable,
	.mmap = yuanrdma_mmap,
	.mmap_free = yuanrdma_mmap_free,
	.modify_qp = yuanrdma_modify_qp,
	.poll_cq = yuanrdma_poll_cq,
	.post_recv = yuanrdma_post_recv,
	.post_send = yuanrdma_post_send,
	.query_device = yuanrdma_query_device,
	.query_pkey = yuanrdma_query_pkey,
	.query_port = yuanrdma_query_port,
	.query_qp = yuanrdma_query_qp,
	.reg_user_mr = yuanrdma_reg_user_mr,
	/*
	 * dma-buf MR（GPUDirect）。ib_umem_dmabuf_get_pinned() 是 6.2+ 才有的 API；
	 * 5.15（MOFED 5.15 那份 ib_core 没有这个符号）上不注册该 op，
	 * 用户态 ibv_reg_dmabuf_mr 会拿到内核返回的 -EOPNOTSUPP —— 与「驱动没实现」同一个可见结果，
	 * 但不会在 insmod 阶段因为缺符号而加载失败。
	 * 不用 #ifdef 判内核版本宏是刻意的：__has_include 判符号更贴近实际，
	 * 且 rdma/ib_umem.h 在 6.2 之后才有 get_pinned 的声明。
	 */
#ifdef YUANRDMA_HAVE_UMEM_DMABUF_PINNED
	.reg_user_mr_dmabuf = yuanrdma_reg_user_mr_dmabuf,
#endif
	.req_notify_cq = yuanrdma_req_notify_cq,

	INIT_RDMA_OBJ_SIZE(ib_ah, yuanrdma_ah, ibah),
	INIT_RDMA_OBJ_SIZE(ib_cq, yuanrdma_cq, ibcq),
	INIT_RDMA_OBJ_SIZE(ib_pd, yuanrdma_pd, ibpd),
	INIT_RDMA_OBJ_SIZE(ib_qp, yuanrdma_qp, ibqp),
	INIT_RDMA_OBJ_SIZE(ib_ucontext, yuanrdma_ucontext, ibucontext),
};
