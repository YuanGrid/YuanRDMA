// SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause
/*
 * yuanrdma_main.c - 模块加载：找到 yuanmcdma 已经接管的 YuanNIC-NH400-C（0x1172:0x0000）及其 netdev，
 * 映射 BAR2 中的 RoCE CSR 窗口，初始化引擎并注册 ib_device。
 */
#include <linux/module.h>
#include <linux/delay.h>
#include <linux/etherdevice.h>
#include <linux/rtnetlink.h>
#include <net/addrconf.h>

#include "yuanrdma_driver.h"

MODULE_AUTHOR("YuanGrid");
MODULE_DESCRIPTION("YuanNIC-NH400-C RoCEv2 RDMA driver");
MODULE_LICENSE("Dual BSD/GPL");

static ushort pci_device_id = 0x0000;
module_param(pci_device_id, ushort, 0444);
MODULE_PARM_DESC(pci_device_id, "PCI device id of the YuanNIC-NH400-C function (vendor 0x1172)");

static struct yuanrdma_dev *yuanrdma_device;

u32 yuanrdma_read(struct yuanrdma_dev *dev, u32 offset)
{
	/* offset 是 AVMM 字节偏移；PCIe5 下 BAR2 偏移 = AVMM 地址 << 1 */
	return readl(dev->csr + ((u32)offset << YNRDMA_ADDR_SHIFT));
}

void yuanrdma_write(struct yuanrdma_dev *dev, u32 offset, u32 value)
{
	writel(value, dev->csr + ((u32)offset << YNRDMA_ADDR_SHIFT));
}

/* CSR 表命令：写 CMD_DATA[0..15] 后写 CMD，轮询 CMD_STATUS.busy */
static int yuanrdma_table_command(struct yuanrdma_dev *dev, u32 command)
{
	unsigned long deadline = jiffies + msecs_to_jiffies(100);
	u32 status;

	yuanrdma_write(dev, YNRDMA_REG_CMD, command);
	do {
		status = yuanrdma_read(dev, YNRDMA_REG_CMD_STATUS);
		if (!(status & 1))
			return (status & 2) ? -EINVAL : 0;
		udelay(1);
	} while (time_before(jiffies, deadline));
	return -ETIMEDOUT;
}

int yuanrdma_write_table(struct yuanrdma_dev *dev, u32 table, u32 index, const void *entry, size_t size)
{
	u32 words[16] = {};
	int word, ret;

	if (size > sizeof(words))
		return -EINVAL;
	memcpy(words, entry, size);
	mutex_lock(&dev->table_lock);
	for (word = 0; word < 16; word++)
		yuanrdma_write(dev, YNRDMA_REG_CMD_DATA(word), words[word]);
	ret = yuanrdma_table_command(dev, YNRDMA_CMD_OP_WRITE | (table << YNRDMA_CMD_TBL_SHIFT) |
					   (index & YNRDMA_CMD_IDX_MASK));
	mutex_unlock(&dev->table_lock);
	return ret;
}

int yuanrdma_read_table(struct yuanrdma_dev *dev, u32 table, u32 index, void *entry, size_t size)
{
	u32 words[16];
	int word, ret;

	if (size > sizeof(words))
		return -EINVAL;
	mutex_lock(&dev->table_lock);
	ret = yuanrdma_table_command(dev, (table << YNRDMA_CMD_TBL_SHIFT) | (index & YNRDMA_CMD_IDX_MASK));
	if (!ret)
		for (word = 0; word < 16; word++)
			words[word] = yuanrdma_read(dev, YNRDMA_REG_CMD_DATA(word));
	mutex_unlock(&dev->table_lock);
	if (!ret)
		memcpy(entry, words, size);
	return ret;
}

/* yuanmcdma 的 netdev 的 parent 是同一个 pci_dev */
static struct net_device *yuanrdma_find_netdev(struct pci_dev *pdev)
{
	struct net_device *netdev, *found = NULL;

	rtnl_lock();
	for_each_netdev(&init_net, netdev) {
		if (netdev->dev.parent == &pdev->dev) {
			dev_hold(netdev);
			found = netdev;
			break;
		}
	}
	rtnl_unlock();
	return found;
}

static void yuanrdma_set_mac(struct yuanrdma_dev *dev)
{
	const u8 *mac = dev->netdev->dev_addr;

	yuanrdma_write(dev, YNRDMA_REG_MAC_LO, mac[0] | (mac[1] << 8) | (mac[2] << 16) | ((u32)mac[3] << 24));
	yuanrdma_write(dev, YNRDMA_REG_MAC_HI, mac[4] | (mac[5] << 8));
}

/*
 * 加载时把拥塞控制相关的当前值打到 dmesg（**只读**）。
 *
 * 默认值来自 RTL 复位分支，在比特流配置 FPGA 时就位；驱动刻意不重写这些寄存器，
 * 否则每次 rmmod/insmod 都会把 yuancli 调好的参数冲回默认。代价是「当前值到底是多少」
 * 只能现场查——所以这里在 probe 里读一遍，日志里留下当时的快照。
 * 三个窗口各自有 ID magic；老镜像缺某个窗口时读回 0xdeadbeef，跳过该段。
 */
static void yuanrdma_dump_cc_params(struct yuanrdma_dev *dev)
{
	u32 pfc_id = yuanrdma_read(dev, YNRDMA_PFC_ID);
	u32 cnp_id = yuanrdma_read(dev, YNRDMA_CNP_ID);
	u32 dcq_id = yuanrdma_read(dev, YNRDMA_DCQCN_ID);
	const char *line = "                    ";   /* 12 空格；子项版本在上面单独打 */

	if (pfc_id == 0x50464301u) {
		u32 warn = yuanrdma_read(dev, YNRDMA_PFC_WD_WARN_US);

		dev_info(&dev->pdev->dev,
			 "%sPFC   CTRL=0x%x CTRL2=0x%x HOLD=%u WD_TX=%u WD_RX=%u WD_WARN=%s\n",
			 line,
			 yuanrdma_read(dev, YNRDMA_PFC_CTRL), yuanrdma_read(dev, YNRDMA_PFC_CTRL2),
			 yuanrdma_read(dev, YNRDMA_PFC_HOLD_US),
			 yuanrdma_read(dev, YNRDMA_PFC_WD_TX_US),
			 yuanrdma_read(dev, YNRDMA_PFC_WD_RX_US),
			 (warn == 0xdeadbeefu) ? "n/a(B6434+)" : "set");
		if (warn != 0xdeadbeefu)
			dev_info(&dev->pdev->dev, "%s      WD_WARN=%u µs（只告警不关 PFC，0 = 关）\n",
				 line, warn);
	}
	if (cnp_id == 0x434e5001u) {
		u32 tos = yuanrdma_read(dev, YNRDMA_CNP_TOS);
		u32 bth = yuanrdma_read(dev, YNRDMA_CNP_BTH);

		dev_info(&dev->pdev->dev,
			 "%sECN   CTRL=0x%x CNP_TOS=0x%x(DSCP %u ECN %u) BTH=%s min_us=%u\n",
			 line,
			 yuanrdma_read(dev, YNRDMA_CNP_CTRL), tos, tos >> 2, tos & 3,
			 (bth == 0xdeadbeefu) ? "n/a(B6434+)" : (bth & 1) ? "BECN=1 FECN=0" : "BECN=0",
			 yuanrdma_read(dev, YNRDMA_CNP_MIN_US));
	}
	if (dcq_id == 0x44435101u) {
		u32 ctrl = yuanrdma_read(dev, YNRDMA_DCQCN_CTRL);
		u32 alpha = yuanrdma_read(dev, YNRDMA_DCQCN_INIT_ALPHA);
		u32 g = yuanrdma_read(dev, YNRDMA_DCQCN_G);

		dev_info(&dev->pdev->dev,
			 "%sDCQCN CTRL=0x%x(EN %u HAI_EN %u CLAMP %u) AI=%u HAI=%u F=%u "
			 "alpha=%s g=%s\n",
			 line, ctrl, ctrl & 1, (ctrl >> 1) & 1, (ctrl >> 2) & 1,
			 yuanrdma_read(dev, YNRDMA_DCQCN_AI),
			 yuanrdma_read(dev, YNRDMA_DCQCN_HAI),
			 yuanrdma_read(dev, YNRDMA_DCQCN_THRESH),
			 (alpha == 0xdeadbeefu) ? "n/a(B6434+)" : "set",
			 (g == 0xdeadbeefu) ? "n/a(B6434+)" : "set");
		if (alpha != 0xdeadbeefu) {
			dev_info(&dev->pdev->dev,
				 "%s      init_alpha=%u g=%u/1024 max_hai_factor=%u "
				 "tcp_rtt=%uµs red=%uµs reset=%uµs bytes=%u min_rate=%u line=%u\n",
				 line, alpha, g, yuanrdma_read(dev, YNRDMA_DCQCN_MAX_HAI_F),
				 yuanrdma_read(dev, YNRDMA_DCQCN_ALPHA_US),
				 yuanrdma_read(dev, YNRDMA_DCQCN_RED_US),
				 yuanrdma_read(dev, YNRDMA_DCQCN_INC_US),
				 yuanrdma_read(dev, YNRDMA_DCQCN_INC_BYTES),
				 yuanrdma_read(dev, YNRDMA_DCQCN_MIN_RATE),
				 yuanrdma_read(dev, YNRDMA_DCQCN_LINE));
		}
	}
}

static int __init yuanrdma_init(void)
{
	struct yuanrdma_dev *dev;
	struct pci_dev *pdev;
	resource_size_t bar_start, bar_length;
	u32 magic;
	int ret;

	pdev = pci_get_device(YNRDMA_PCI_VENDOR_ID, pci_device_id, NULL);
	if (!pdev) {
		pr_err("yuanrdma: no PCI device %04x:%04x\n", YNRDMA_PCI_VENDOR_ID, pci_device_id);
		return -ENODEV;
	}
	bar_start = pci_resource_start(pdev, YUANRDMA_BAR);
	bar_length = pci_resource_len(pdev, YUANRDMA_BAR);
	if (bar_length < YNRDMA_BAR2_BASE + YNRDMA_WINDOW_SIZE) {
		pci_err(pdev, "yuanrdma: BAR%d too small (%pa)\n", YUANRDMA_BAR, &bar_length);
		ret = -ENODEV;
		goto put_pci;
	}

	dev = ib_alloc_device(yuanrdma_dev, ibdev);
	if (!dev) {
		ret = -ENOMEM;
		goto put_pci;
	}
	dev->pdev = pdev;
	mutex_init(&dev->table_lock);
	spin_lock_init(&dev->alloc_lock);
	set_bit(0, dev->pd_used);			/* PD 0 保留 */

	dev->netdev = yuanrdma_find_netdev(pdev);
	if (!dev->netdev) {
		pci_err(pdev, "yuanrdma: netdev not found, load yuanmcdma.ko first\n");
		ret = -ENODEV;
		goto free_device;
	}
	dev->csr = ioremap(bar_start + YNRDMA_BAR2_BASE, YNRDMA_WINDOW_SIZE);
	if (!dev->csr) {
		ret = -ENOMEM;
		goto put_netdev;
	}
	/* doorbell 页的 AVMM 地址是 base + DB_PAGE，PCIe5 下同样左移一位 */
	dev->doorbell_phys = bar_start + YNRDMA_BAR2_BASE + ((phys_addr_t)YNRDMA_DB_PAGE << YNRDMA_ADDR_SHIFT);

	magic = yuanrdma_read(dev, YNRDMA_REG_ID);
	if (magic != YNRDMA_ID_MAGIC) {
		pci_err(pdev, "yuanrdma: RoCE engine not present (ID %08x), wrong FPGA image?\n", magic);
		ret = -ENODEV;
		goto unmap;
	}
	pci_info(pdev, "yuanrdma: engine version %08x caps %08x, netdev %s\n",
		 yuanrdma_read(dev, YNRDMA_REG_VERSION), yuanrdma_read(dev, YNRDMA_REG_CAPS), dev->netdev->name);
	yuanrdma_set_mac(dev);
	yuanrdma_write(dev, YNRDMA_REG_CTRL, YNRDMA_CTRL_ENABLE);
	yuanrdma_dump_cc_params(dev);

	ib_set_device_ops(&dev->ibdev, &yuanrdma_device_ops);
	dev->ibdev.node_type = RDMA_NODE_IB_CA;
	dev->ibdev.phys_port_cnt = 1;
	dev->ibdev.num_comp_vectors = 1;
	dev->ibdev.dev.parent = &pdev->dev;
	/* legacy write 命令掩码必须显式列出。
	 * "6.x 起由核心按已实现的 ops 自动开放" 只对 6.8+ 成立；5.15（含 OFED 那份
	 * ib_core）的 uverbs_uapi.c 仍按 !(uverbs_cmd_mask & BIT(cmd)) 把方法标记为
	 * disabled 并从 radix tree 删除，运行期落到 notsupp_method -> -EOPNOTSUPP。
	 * 症状：ibv_devinfo 正常（走 provider 自己的 query_device），但 ibv_alloc_pd
	 * 失败、perftest 报 "Failed to query device attributes"。
	 * 6.x 忽略该字段，所以这里在两种内核上都安全。 */
	dev->ibdev.uverbs_cmd_mask =
		BIT_ULL(IB_USER_VERBS_CMD_GET_CONTEXT) |
		BIT_ULL(IB_USER_VERBS_CMD_QUERY_DEVICE) |
		BIT_ULL(IB_USER_VERBS_CMD_QUERY_PORT) |
		BIT_ULL(IB_USER_VERBS_CMD_ALLOC_PD) |
		BIT_ULL(IB_USER_VERBS_CMD_DEALLOC_PD) |
		BIT_ULL(IB_USER_VERBS_CMD_CREATE_CQ) |
		BIT_ULL(IB_USER_VERBS_CMD_DESTROY_CQ) |
		/* 完成事件链：comp channel + req_notify_cq（yuanrdma_cq_event.c）。ib_core 的默认掩码里
		 * 本来就有这两条，但上面是整体赋值，不列出来就被覆盖掉，ibv_create_comp_channel 会 EOPNOTSUPP。 */
		BIT_ULL(IB_USER_VERBS_CMD_CREATE_COMP_CHANNEL) |
		BIT_ULL(IB_USER_VERBS_CMD_REQ_NOTIFY_CQ) |
		BIT_ULL(IB_USER_VERBS_CMD_CREATE_QP) |
		BIT_ULL(IB_USER_VERBS_CMD_DESTROY_QP) |
		BIT_ULL(IB_USER_VERBS_CMD_MODIFY_QP) |
		BIT_ULL(IB_USER_VERBS_CMD_QUERY_QP) |
		BIT_ULL(IB_USER_VERBS_CMD_REG_MR) |
		BIT_ULL(IB_USER_VERBS_CMD_DEREG_MR);
	strscpy(dev->ibdev.node_desc, "YuanNIC-NH400-C", sizeof(dev->ibdev.node_desc));
	addrconf_addr_eui48((u8 *)&dev->ibdev.node_guid, dev->netdev->dev_addr);
	ret = ib_device_set_netdev(&dev->ibdev, dev->netdev, 1);
	if (ret)
		goto disable;
	/* 软件 GSI（QP1）：eth0 收包挂钩 + 发包 workqueue。必须在 ib_register_device 之前就位，
	 * 因为 mad 客户端在注册过程中就会创建 QP1 并立即开始收包。 */
	yuanrdma_cq_event_init(dev);
	ret = yuanrdma_gsi_init(dev);
	if (ret)
		goto disable;
	ret = ib_register_device(&dev->ibdev, "yuanrdma%d", &pdev->dev);
	if (ret) {
		yuanrdma_gsi_cleanup(dev);
		yuanrdma_cq_event_cleanup(dev);
		goto disable;
	}
	yuanrdma_device = dev;
	return 0;

disable:
	yuanrdma_write(dev, YNRDMA_REG_CTRL, 0);
unmap:
	iounmap(dev->csr);
put_netdev:
	dev_put(dev->netdev);
free_device:
	ib_dealloc_device(&dev->ibdev);
put_pci:
	pci_dev_put(pdev);
	return ret;
}

static void __exit yuanrdma_exit(void)
{
	struct yuanrdma_dev *dev = yuanrdma_device;
	struct pci_dev *pdev;
	struct net_device *netdev;
	void __iomem *csr;

	if (!dev)
		return;
	pdev = dev->pdev;
	netdev = dev->netdev;
	csr = dev->csr;
	ib_unregister_device(&dev->ibdev);
	yuanrdma_gsi_cleanup(dev);		/* QP1 已随 ib_unregister_device 销毁，这里摘 rx_handler 与 wq */
	yuanrdma_cq_event_cleanup(dev);		/* CQ 已全部销毁，确保轮询定时器停止 */
	yuanrdma_write(dev, YNRDMA_REG_CTRL, 0);	/* 必须走 yuanrdma_write：PCIe5 下要 <<1 */
	iounmap(csr);
	dev_put(netdev);
	ib_dealloc_device(&dev->ibdev);
	pci_dev_put(pdev);
}

module_init(yuanrdma_init);
module_exit(yuanrdma_exit);
