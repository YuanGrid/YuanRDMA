/* SPDX-License-Identifier: ((GPL-2.0 WITH Linux-syscall-note) OR BSD-2-Clause) */
/*
 * yuanrdma-abi.h - yuanrdma 内核驱动与 rdma-core provider 之间的 uverbs 私有数据。
 * 两边共用一份（provider 侧拷贝到 rdma-core 的 kernel-headers/rdma/yuanrdma-abi.h）。
 */
#ifndef YUANRDMA_ABI_USER_H
#define YUANRDMA_ABI_USER_H

#include <linux/types.h>

#define YUANRDMA_ABI_VERSION 1

/* alloc_ucontext 返回：doorbell 页（4 KB，非缓存映射） */
struct yuanrdma_alloc_ucontext_resp {
	__aligned_u64 doorbell_mmap_key;
	__u32 max_qp;
	__u32 max_cq;
};

/* create_cq 返回：CQ 环（物理连续，32 B/项） */
struct yuanrdma_create_cq_resp {
	__aligned_u64 ring_mmap_key;
	__u32 cq_index;
	__u32 log2_depth;
};

/* create_qp 返回：SQ 环（64 B/项）、RQ 环（32 B/项），物理连续 */
struct yuanrdma_create_qp_resp {
	__aligned_u64 sq_mmap_key;
	__aligned_u64 rq_mmap_key;
	__u32 qp_index;
	__u32 sq_log2_depth;
	__u32 rq_log2_depth;
	__u32 max_inline_data;
};

#endif /* YUANRDMA_ABI_USER_H */
