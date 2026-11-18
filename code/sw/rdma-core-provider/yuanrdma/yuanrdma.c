// SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause
/* yuanrdma provider：设备匹配、context（映射 doorbell 页）。 */
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "yuanrdma.h"
#include "yuanrdma_abi.h"

static const struct verbs_context_ops yuanrdma_context_ops = {
	.alloc_pd = yuanrdma_alloc_pd,
	/* create_ah/destroy_ah 显式注册：ibv_create_ah 拿到 NULL 且 errno 明确，比留空时
	 * libibverbs 的 _compat 桩（ENOSYS/EINVAL）更容易定位。G2.1 Step 2 起是真实现
	 * （RoCEv2 v4-mapped AH → dgid/sgid_index），但能否真发 UD 还取决于内核
	 * create_qp 是否放行 IB_QPT_UD，见 yuanrdma_verbs.c 的注释。
	 * req_notify_cq 不注册（未实现，且没有中断通路），理由见那边。 */
	.create_ah = yuanrdma_create_ah,
	.destroy_ah = yuanrdma_destroy_ah,
	.create_cq = yuanrdma_create_cq,
	.create_qp = yuanrdma_create_qp,
	.dealloc_pd = yuanrdma_dealloc_pd,
	.dereg_mr = yuanrdma_dereg_mr,
	.destroy_cq = yuanrdma_destroy_cq,
	.destroy_qp = yuanrdma_destroy_qp,
	.modify_qp = yuanrdma_modify_qp,
	.poll_cq = yuanrdma_poll_cq,
	.post_recv = yuanrdma_post_recv,
	.post_send = yuanrdma_post_send,
	.query_device_ex = yuanrdma_query_device,
	.query_port = yuanrdma_query_port,
	.query_qp = yuanrdma_query_qp,
	/* dmabuf MR（G2.1）：转发 uverbs 的 REG_DMABUF_MR，内核侧由 yuanrdma_reg_user_mr_dmabuf
	 * 接（仅内核 6.2+ 编译，见 yuanrdma_verbs.c 的版本门控）。不注册时 ibv_reg_dmabuf_mr
	 * 落 dummy_ops 的 EOPNOTSUPP 桩，NCCL/GDR 这类走 dmabuf 的 ULP 看不出是
	 * 「provider 没做」还是「内核太老」。 */
	.reg_dmabuf_mr = yuanrdma_reg_dmabuf_mr,
	.reg_mr = yuanrdma_reg_mr,
};

static void yuanrdma_free_context(struct ibv_context *ibv_context)
{
	struct yuanrdma_context *context = to_yuanrdma_context(ibv_context);

	munmap(context->doorbell_page, 4096);
	verbs_uninit_context(&context->ibv_context);
	free(context);
}

static const struct verbs_context_ops yuanrdma_context_free_ops = {
	.free_context = yuanrdma_free_context,
};

static struct verbs_context *yuanrdma_alloc_context(struct ibv_device *device, int command_fd, void *private_data)
{
	struct yuanrdma_alloc_context_resp response = {};
	struct ibv_get_context command = {};
	struct yuanrdma_context *context;
	void *doorbell;

	context = verbs_init_and_alloc_context(device, command_fd, context, ibv_context, RDMA_DRIVER_UNKNOWN);
	if (!context)
		return NULL;
	pthread_mutex_init(&context->qp_table_lock, NULL);
	if (ibv_cmd_get_context(&context->ibv_context, &command, sizeof(command), NULL,
				&response.ibv_resp, sizeof(response)))
		goto fail;
	doorbell = mmap(NULL, 4096, PROT_WRITE, MAP_SHARED, command_fd, response.doorbell_mmap_key);
	if (doorbell == MAP_FAILED)
		goto fail;
	context->doorbell_page = doorbell;
	verbs_set_ops(&context->ibv_context, &yuanrdma_context_ops);
	verbs_set_ops(&context->ibv_context, &yuanrdma_context_free_ops);
	return &context->ibv_context;

fail:
	verbs_uninit_context(&context->ibv_context);
	free(context);
	return NULL;
}

static struct verbs_device *yuanrdma_device_alloc(struct verbs_sysfs_dev *sysfs_device)
{
	struct yuanrdma_device *device = calloc(1, sizeof(*device));

	return device ? &device->ibv_device : NULL;
}

static void yuanrdma_device_free(struct verbs_device *verbs_device)
{
	free(container_of(verbs_device, struct yuanrdma_device, ibv_device));
}

static const struct verbs_match_ent yuanrdma_match_table[] = {
	VERBS_NAME_MATCH("yuanrdma", NULL),
	VERBS_PCI_MATCH(YNRDMA_PCI_VENDOR_ID, 0x0000, NULL),
	{},
};

static const struct verbs_device_ops yuanrdma_device_ops = {
	.name = "yuanrdma",
	.match_min_abi_version = YUANRDMA_ABI_VERSION,
	.match_max_abi_version = YUANRDMA_ABI_VERSION,
	.match_table = yuanrdma_match_table,
	.alloc_device = yuanrdma_device_alloc,
	.uninit_device = yuanrdma_device_free,
	.alloc_context = yuanrdma_alloc_context,
};

PROVIDER_DRIVER(yuanrdma, yuanrdma_device_ops);
