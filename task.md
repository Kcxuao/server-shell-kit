# server-shell-kit 下一阶段开发执行计划

## 一、目标

将 server-shell-kit 从“服务器初始化 + Shell 环境配置工具”逐步升级为：

**服务器初始化、环境发现、状态快照、备份恢复、服务器迁移和迁移后验证工具。**

整体生命周期：

Discover → Snapshot → Backup → Plan → Apply → Restore → Verify

本阶段不追求一次实现全部能力，按照可独立验证的小阶段逐步开发。

核心原则：

1. 不破坏现有功能。
2. 保持 Debian / Ubuntu 兼容。
3. 所有修改系统状态的操作尽量支持预览、确认、验证和失败回滚。
4. 所有安装逻辑必须尽量幂等。
5. 相同功能只能存在一套底层实现，可以存在多个调用入口。
6. 不为了架构而过度抽象，保持 Bash 脚本简单可读。
7. 数据备份必须考虑一致性，数据库不能直接粗暴复制数据目录。
8. Secrets 与普通配置分开处理。
9. 每个阶段完成后必须通过语法检查和基本回归检查后才能进入下一阶段。

---

# Phase 1：整理现有架构

目标：先解决当前职责重复问题，为后续功能扩展建立稳定基础。

## 1.1 Docker 安装逻辑统一

新增：

`scripts/install-docker.sh`

统一负责：

- Docker 安装检测
- Docker 安装
- Docker Compose Plugin 安装
- Docker 服务启用
- Docker 服务启动
- 安装结果验证

调整：

`bootstrap-container.sh`

只负责：

base bootstrap
→ install-docker.sh
→ 可选 configure-docker-mirrors.sh

主菜单 Docker 功能同样调用 install-docker.sh。

禁止 bootstrap-container.sh 和 install.sh 自己维护另一套 Docker 安装命令。

## 1.2 主菜单整理

主菜单调整为：

1. 新服务器初始化
2. 终端环境
3. 编程环境
4. Docker
5. 环境体检
6. 系统工具
7. 更新配置
8. 卸载
0. 退出

终端环境：

- 完整安装
- 自选组件
- 高危命令保护设置

系统工具：

- APT 镜像
- 管理员用户
- SSH Key
- UFW
- 配置迁移

将 `rm -rf 自动备份设置` 移入“高危命令保护设置”。

## Phase 1 验收

必须检查：

- 所有现有功能仍有菜单入口
- Docker 安装只有一套底层实现
- Doctor 修复跳转没有失效
- 所有 Shell/Zsh 文件语法检查通过
- 不改变现有危险命令保护行为

---

# Phase 2：服务器 Discover 与 Snapshot

目标：能够回答“这台服务器现在是什么状态”。

新增：

`scripts/discover.sh`
`scripts/snapshot.sh`

建议增加：

`lib/system-info.sh`

## 2.1 Discover

自动检测：

### System

- Distribution
- Distribution Version
- Kernel
- Architecture
- Hostname
- Timezone
- Locale
- Uptime
- CPU
- Memory
- Swap
- Disk

### Users

记录：

- 普通用户
- sudo 用户
- 用户 shell
- HOME

不要记录：

- `/etc/shadow`
- 用户密码
- SSH 私钥

### Network

记录：

- IP 信息
- DNS
- 默认网关
- 当前监听端口

### Services

检测：

- systemd enabled services
- systemd running services

### Development

检测：

- Git
- Java
- Maven
- Python
- uv
- Node
- npm
- Rust
- Cargo

### Docker

检测：

- Docker Version
- Compose Version
- Containers
- Images
- Volumes
- Networks

### Database

检测：

- PostgreSQL
- MySQL
- MariaDB
- Redis

需要同时识别：

- systemd 安装
- Docker 容器运行

## 2.2 Snapshot

将 Discover 结果保存为机器可读取的 JSON。

例如：

`~/.local/share/server-shell-kit/snapshots/20260929-120000.json`

基本结构：

{
  "schema_version": 1,
  "created_at": "...",
  "system": {},
  "users": [],
  "network": {},
  "services": {},
  "development": {},
  "docker": {},
  "databases": {}
}

Snapshot 必须设置 `schema_version`，为以后格式升级预留兼容能力。

## Phase 2 验收

执行：

`snapshot.sh`

必须：

- 不修改系统
- 不需要用户交互
- 生成合法 JSON
- 不保存密码、Token、SSH 私钥等 Secrets
- Docker 不存在时正常运行
- 数据库不存在时正常运行
- 普通用户权限不足时记录 unavailable，而不是整个脚本失败

---

# Phase 3：备份系统

目标：实现配置与核心业务数据的结构化备份。

不要继续把所有逻辑堆进现有 migrate-config.sh。

建议新增：

`scripts/backup.sh`

并拆分：

`scripts/backup-config.sh`
`scripts/backup-docker.sh`
`scripts/backup-postgresql.sh`
`scripts/backup-mysql.sh`
`scripts/backup-files.sh`

## 3.1 备份类型

提供：

1. 环境配置备份
2. 核心数据备份
3. 完整备份

## 3.2 配置备份

包含现有：

- Shell
- Starship
- Alias
- Git
- Vim
- Tmux
- authorized_keys
- APT Sources
- package list
- systemd service information

## 3.3 Docker

默认备份：

- 容器清单
- Image 名称/tag/digest 清单
- Volume 数据
- Network 信息
- Compose 文件

默认不要导出所有 Docker Image。

镜像应该优先通过：

image:tag
image digest

记录，然后在新服务器重新 pull。

## 3.4 PostgreSQL

使用数据库原生工具：

- pg_dump
- pg_dumpall

禁止在线运行时直接 tar PostgreSQL data directory。

需要支持：

- 系统 PostgreSQL
- Docker PostgreSQL

## 3.5 MySQL / MariaDB

使用：

- mysqldump

同样支持：

- systemd
- Docker

## 3.6 自定义目录

允许用户指定：

`/opt/app`
`/srv/data`
`/www`

等需要迁移的目录。

## 3.7 Manifest

每次备份必须产生：

`manifest.json`

记录：

- backup schema version
- server hostname
- OS
- 创建时间
- server-shell-kit version
- 包含哪些模块
- 每个模块状态
- 文件大小
- checksum

备份结果建议：

server-shell-kit-backup-YYYYMMDD-HHMMSS/
  manifest.json
  snapshot.json
  system/
  configs/
  docker/
  databases/
  files/

## Phase 3 验收

必须测试：

- 没有 Docker
- 有 Docker
- 没有数据库
- Docker PostgreSQL
- 系统 PostgreSQL
- 部分模块备份失败

单个模块失败不能导致已经完成的备份丢失。

最终必须明确显示：

SUCCESS
FAILED
SKIPPED

---

# Phase 4：Secrets 与备份安全

目标：避免完整备份本身成为安全风险。

扫描：

- `.env`
- private key
- TLS key
- database credential
- Docker registry credential
- API key 配置文件

不要尝试分析 Secret 的实际值。

只需要识别可能包含敏感数据的文件。

备份前显示：

发现可能的敏感文件：

.env
server.key
docker config.json

让用户决定：

- 跳过
- 包含
- 加密备份

完整备份建议支持加密。

默认禁止自动包含：

- SSH private key
- `/etc/shadow`

## Phase 4 验收

确保：

- 默认备份不会静默收集 SSH 私钥
- 敏感文件必须明确提示
- 临时明文文件必须清理
- 中断时也需要清理临时目录

---

# Phase 5：Migration Plan / Dry Run

目标：恢复之前先告诉用户“将会发生什么”。

新增：

`scripts/plan.sh`

输入：

- backup manifest
- source snapshot
- target snapshot

输出：

Migration Plan

例如：

[INSTALL] docker
[INSTALL] java 21
[CREATE] deploy
[RESTORE] shell config
[RESTORE] PostgreSQL:gitea
[RESTORE] docker-volume:gitea_data
[OPEN] 80/tcp
[OPEN] 443/tcp

并检测冲突：

[CONFLICT] target PostgreSQL already contains database gitea
[WARNING] Ubuntu 22.04 -> Ubuntu 24.04
[WARNING] target disk space may be insufficient

支持：

`--dry-run`

Dry Run 禁止修改系统。

## Phase 5 验收

同一个备份在不同目标服务器上生成不同 Plan。

Dry Run 必须做到零系统修改。

---

# Phase 6：Restore

目标：根据 Manifest 和 Migration Plan 恢复服务器。

新增：

`scripts/restore.sh`

恢复顺序：

1. Preflight
2. 系统基础环境
3. 用户
4. 软件依赖
5. Docker
6. 配置
7. Docker Volumes
8. Database
9. 自定义文件
10. 服务启动
11. Verify

恢复之前必须检查：

- OS compatibility
- disk space
- required commands
- port conflicts
- existing database
- existing Docker volumes
- existing files

遇到目标数据已存在时禁止静默覆盖。

必须要求明确选择：

- skip
- backup existing + replace
- abort

## Phase 6 验收

恢复操作必须尽量幂等。

同一份备份重复执行不能：

- 重复创建用户
- 重复添加 UFW rule
- 破坏已有配置
- 无提示覆盖数据库

---

# Phase 7：Verify

目标：迁移完成后自动验证。

新增：

`scripts/verify.sh`

检查：

### System

- disk
- memory
- DNS
- timezone

### Services

- systemd service
- Docker container

### Network

- required ports listening

### Database

- PostgreSQL connectivity
- MySQL connectivity

### Development

- Java
- Python
- Node
- Rust

### Docker

- Docker daemon
- container status
- volume existence

最终输出：

Migration Verification

System        PASS
Docker        PASS
PostgreSQL    PASS
Services      PASS
Ports         PASS
Development   PASS

Passed: 38
Warning: 2
Failed: 0

Verify 必须是只读操作。

---

# Phase 8：Diff

目标：比较旧服务器和新服务器状态。

新增：

`scripts/diff.sh`

比较：

Source → Target

包括：

- OS
- timezone
- users
- software versions
- Docker
- services
- ports
- databases
- development environment

状态：

SAME
CHANGED
MISSING
EXTRA

用于迁移完成后的人工确认。

---

# Phase 9：任务状态与断点续跑

最后再实现，不要提前增加复杂度。

建立：

`~/.local/state/server-shell-kit/jobs/`

每次迁移生成 Job ID。

记录：

- 当前阶段
- 每个步骤状态
- 开始时间
- 完成时间
- 错误原因

状态：

PENDING
RUNNING
SUCCESS
FAILED
SKIPPED

支持：

`resume`

已经 SUCCESS 的步骤默认不重复执行。

---

# 开发顺序

严格按照：

Phase 1
→ Phase 2
→ Phase 3
→ Phase 4
→ Phase 5
→ Phase 6
→ Phase 7
→ Phase 8
→ Phase 9

不要一次性实现全部 Phase。

每完成一个 Phase：

1. 检查代码。
2. 执行 Shell/Zsh 语法检查。
3. 检查现有功能回归。
4. 输出修改文件。
5. 输出测试结果。
6. 提交当前阶段结果后再开始下一阶段。

---

# 当前优先执行

现在只执行：

**Phase 1：现有架构整理**

不要提前实现 Phase 2-9。

Phase 1 完成后停止，并报告：

1. 修改文件列表
2. Docker 重构前后的调用关系
3. 新菜单结构
4. 是否存在其他重复实现
5. Bash/Zsh 语法检查结果
6. 发现但暂未处理的问题

等待确认后再开始 Phase 2。