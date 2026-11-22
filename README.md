# Agent2API for fnOS

独立打包仓库：把 Agent2API 官方 Linux 服务端 Release 打包成飞牛 OS 原生
`.fpk` 应用，不维护也不合并上游源码。

## 自动同步

`.github/workflows/sync-upstream.yml` 每小时检查一次
`aimod-cc/Agent2API` 的 beta Release。发现新版本且包含 amd64/arm64 官方
服务端包后，自动：

1. 下载并校验上游 SHA-256。
2. 构建 `agent2api_<version>_x86.fpk` 和 `agent2api_<version>_arm.fpk`。
3. 在容器中执行安装、启动、升级和卸载测试。
4. 生成 `SHA256SUMS`。
5. 创建标签为 `fnos-v<version>` 的 GitHub Release，并上传安装包。

默认跟踪 beta 通道。切换稳定版时，把工作流中的
`UPSTREAM_CHANNEL: beta` 改为 `stable`。

## 自动更新边界

打包仓库每小时检查并构建上游 Release，但飞牛应用本身不会在未获授权的情况下
替换 `/var/apps/agent2api` 下的受管文件。

原因是：

- 飞牛应用中心负责安装、升级、注册表版本和桌面入口，第三方应用直接覆盖文件
  会造成应用中心显示版本与实际运行版本不一致。
- `appcenter-cli install-fpk` 在当前飞牛实现中可能走卸载重装路径，不适合作为
  无人值守的数据保留升级通道。
- Agent2API 自带的 Docker/systemd 自更新要求固定路径或容器环境，不适用于
  fnOS 普通应用目录。

当前安全升级方式是下载新 `.fpk` 后在应用中心覆盖安装，`upgrade_init` /
`upgrade_callback` 会保留应用数据。若后续要启用完全无人值守安装，应增加一个
独立的受信任特权更新器，并通过飞牛应用中心的数据保留更新 RPC 执行，而不是
直接覆盖应用文件。

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
