# deploy

交付物目录：打包、安装脚本、用户手册、固件镜像、程序等对外交付内容的统一落点。

## 现有内容

| 文件 | 说明 |
|---|---|
| `yuanrdma_install.sh` | 环境一键安装（apt / Python / Verilator / DPDK 依赖 / CUDA），按 `INSTALL.md` 第 2~6 节。`ROOT=$HERE/..` 指向仓库根 |
| `yuannic_user_build.sh` | 用户态栈构建与打包。产物默认出到 `build/user_tools/YuanNIC_User_Package`（`flash_and_init.sh` / `roce_perf_test.sh` 按同级目录定位包，跟着挪会打断上板流程）；要改存放位置用 `YUANNIC_PKG_OUT` 覆盖，并同步改那两个脚本 |

## 约定

- 固件的正式归档位仍是仓库根 `firmware/`（`build/<板卡>/yuannic_build.sh` 自动写入）。
  若在本目录放交付副本，说明哪一份是权威来源。
- 大体积二进制（`.sof` / `.rpd` / `.jic` / 安装包）入库前确认 `.gitignore` 没有排除它们。
