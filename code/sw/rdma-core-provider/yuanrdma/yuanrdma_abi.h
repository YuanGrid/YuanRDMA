/* SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause */
#ifndef YUANRDMA_PROVIDER_ABI_H
#define YUANRDMA_PROVIDER_ABI_H

#include <infiniband/kern-abi.h>
#include <rdma/yuanrdma-abi.h>
#include <kernel-abi/yuanrdma-abi.h>

DECLARE_DRV_CMD(yuanrdma_alloc_context, IB_USER_VERBS_CMD_GET_CONTEXT, empty, yuanrdma_alloc_ucontext_resp);
DECLARE_DRV_CMD(yuanrdma_create_cq_cmd, IB_USER_VERBS_CMD_CREATE_CQ, empty, yuanrdma_create_cq_resp);
DECLARE_DRV_CMD(yuanrdma_create_qp_cmd, IB_USER_VERBS_CMD_CREATE_QP, empty, yuanrdma_create_qp_resp);

#endif
