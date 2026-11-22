# Agent2API for fnOS

独立打包仓库：把 Agent2API 官方 Linux 服务端 Release 打包成飞牛 OS 原生
`.fpk` 应用，不维护也不合并上游源码。

## 自动同步

`.github/workflows/sync-upstream.yml` 每 5 分钟检查一次
`aimod-cc/Agent2API` 的 beta Release。发现新版本且包含 amd64/arm64 官方
服务端包后，自动：

1. 下载并校验上游 SHA-256。
2. 构建 `agent2api_<version>_x86.fpk` 和 `agent2api_<version>_arm.fpk`。
3. 在容器中执行安装、启动、升级和卸载测试。
4. 生成 `SHA256SUMS`。
5. 创建标签为 `fnos-v<version>` 的 GitHub Release，并上传安装包。

Release 发布成功后，如果 `Agent2API_FnOS` 仓库配置了
`FNOS_STORE_DISPATCH_TOKEN`（对 `caiyy/fnos-store` 有仓库 Metadata 读取权限即可），
工作流会立即通知商店同步 `apps.json`；未配置时跳过该步骤，由商店的 5 分钟
轮询兜底。

默认跟踪 beta 通道。切换稳定版时，把工作流中的
`UPSTREAM_CHANNEL: beta` 改为 `stable`。

## 自动更新边界

打包仓库每 5 分钟检查并构建上游 Release。已经安装 Cocode Store 并开启
“自动安装更新”的飞牛设备，会每 10 分钟读取更新源，并通过飞牛应用中心的
数据保留升级 RPC 自动安装新 FPK；关闭该选项后只提示可用更新。

原因是：

- 飞牛应用中心负责安装、升级、注册表版本和桌面入口，第三方应用直接覆盖文件
  会造成应用中心显示版本与实际运行版本不一致。
- `appcenter-cli install-fpk` 在当前飞牛实现中可能走卸载重装路径，不适合作为
  无人值守的数据保留升级通道。
- Agent2API 自带的 Docker/systemd 自更新要求固定路径或容器环境，不适用于
  fnOS 普通应用目录。

自动更新由独立特权应用 Cocode Store 执行，不直接覆盖文件。商店会调用飞牛
应用中心的数据保留升级通道，由 `upgrade_init` / `upgrade_callback` 保留应用
数据；如果设备不支持该 RPC，商店会拒绝自动更新。也可以继续在应用中心手动
上传新 `.fpk` 覆盖安装。

GitHub Actions 的定时任务最低间隔为 5 分钟，因此这是该平台能实现的接近实时
轮询上限。要改成真正的事件触发式监控，需要在 `aimod-cc/Agent2API` 仓库配置
Release webhook，或让上游发布流水线主动向本仓库发送 `repository_dispatch`。

## 本地构建

默认使用 `UPSTREAM_VERSION` 中的版本：

```bash
./scripts/build-fnos.sh --arch all
./scripts/verify-fnos.sh dist/agent2api_<version>_x86.fpk
./scripts/verify-fnos.sh dist/agent2api_<version>_arm.fpk
```

构建指定版本：

```bash
./scripts/build-fnos.sh --arch all --version 3.5.0-beta.6
```

需要在不改变上游版本的情况下发布飞牛热修复包时，分别指定两个版本：

```bash
./scripts/build-fnos.sh \
  --upstream-version 3.5.0-beta.6 \
  --package-version 3.5.0-beta.6.1
```

手动触发工作流时也可以填写 `package_version`。这样 FPK 的版本号会递增，
应用中心可以覆盖安装，但二进制仍来自指定的上游 Release。

使用 Docker 跑完整生命周期：

```bash
./scripts/test-fnos-runtime.sh dist/agent2api_<version>_x86.fpk
./scripts/test-fnos-runtime.sh dist/agent2api_<version>_arm.fpk
```

## 安装

在飞牛 OS 应用中心手动上传对应架构的 `.fpk`：

- Intel / AMD：`agent2api_<version>_x86.fpk`
- ARM：`agent2api_<version>_arm.fpk`

安装后从桌面打开 Agent2API，首次访问注册管理员，并在“网关 Key”页面
创建密钥。默认端口为 `3065`。应用数据保存在飞牛应用私有目录，不占用
共享目录；可在应用数据目录的 `agent2api.env` 中调整可选环境变量。

升级时安装新版 `.fpk` 即可，用户数据会保留。

## 目录

```text
packaging/fnos/       fnOS 应用清单、生命周期脚本、图标和桌面入口
scripts/              上游 Release 解析、FPK 构建、校验与运行测试
.github/workflows/    定时同步上游 Release 并发布 fnOS 安装包
UPSTREAM_VERSION      本地默认构建的上游版本
```

安装包内包含上游 AGPL-3.0 许可证和对应源码地址。上游二进制不做修改。
