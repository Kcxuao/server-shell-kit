# Server Shell Kit

面向 Debian / Ubuntu 服务器的新系统初始化、Zsh 美化与高危命令防误操作工具。项目地址：[server-shell-kit](https://github.com/Kcxuao/server-shell-kit)。

## 功能

- 安装并切换到 Zsh
- Starship Prompt
- zsh-autosuggestions
- zsh-syntax-highlighting
- 常用 Git / Docker / Linux Alias
- 交互式高危命令拦截
- 带当前状态、操作前确认和结果提示的菜单式安装、更新、卸载
- 首次修改用户配置时保存 `.server-shell-kit.bak` 备份
- 新服务器初始化：基础、开发、容器三种方案，执行前预览、按步骤记录结果
- 独立的编程环境安装：多选 Java、Python、Node.js、Rust，安装对应管理器及默认稳定版本
- 只读环境体检：检查终端组件、编程环境、Docker、SSH 和 UFW，并引导处理异常项
- 独立安装 Docker 与 Compose，可配置或更新 Docker Hub 镜像加速地址
- 管理员用户、SSH 公钥和 UFW 防火墙单独配置，避免初始化时直接改变远程访问
- 清华/中科大 APT 镜像切换与原源恢复；个人配置与系统清单的迁移备份
- 模块脚本与配置从项目站点下载到同一临时目录后执行

## 仓库结构

```text
server-shell-kit/
├── install.sh
├── menus/
│   ├── terminal.sh
│   ├── programming.sh
│   ├── docker.sh
│   ├── doctor.sh
│   └── system-tools.sh
├── scripts/
│   ├── common.sh
│   ├── install-zsh.sh
│   ├── install-starship.sh
│   ├── install-plugins.sh
│   ├── install-danger-guard.sh
│   ├── install-aliases.sh
│   ├── install-full.sh
│   ├── update-config.sh
│   ├── bootstrap.sh
│   ├── bootstrap-base.sh
│   ├── bootstrap-dev.sh
│   ├── bootstrap-container.sh
│   ├── install-docker.sh
│   ├── configure-docker-mirrors.sh
│   ├── configure-danger-guard.sh
│   ├── configure-rm-backup.sh
│   ├── install-language-manager.sh
│   ├── configure-programming-mirror.py
│   ├── doctor.sh
│   ├── discover.sh
│   ├── snapshot.sh
│   ├── setup-admin-user.sh
│   ├── setup-ssh-key.sh
│   ├── setup-firewall.sh
│   ├── switch-apt-mirror.sh
│   ├── migrate-config.sh
│   ├── backup.sh
│   ├── backup-config.sh
│   ├── backup-secrets.sh
│   ├── backup-files.sh
│   ├── backup-docker.sh
│   ├── backup-postgresql.sh
│   ├── backup-mysql.sh
│   └── uninstall.sh
├── configs/
│   ├── aliases.zsh
│   └── starship.toml
└── plugins/
    └── dangerous-command-guard.plugin.zsh
```

## 使用

执行以下命令启动安装菜单。`install.sh` 从项目站点下载模块脚本和配置文件到临时目录后执行：

```bash
bash <(curl -fsSL https://build.kcxuao.art/install.sh)
```

如果使用镜像站点，可覆盖下载基础地址：

```bash
SERVER_SHELL_KIT_BASE_URL=https://mirror.example.com bash <(curl -fsSL https://mirror.example.com/install.sh)
```

## 新服务器初始化

主菜单选择“新服务器初始化”，可运行以下方案：

| 方案 | 配置内容 |
| --- | --- |
| 基础服务器 | 更新系统软件包、安装常用工具与 OpenSSH、配置自动安全更新和终端环境 |
| 开发服务器 | 基础方案，加 `build-essential` 与 `pkg-config` 通用编译工具 |
| 容器服务器 | 基础方案，加发行版提供的 Docker 包；软件源有 Compose 插件时一并安装，并可配置镜像加速 |

执行前会显示清单并要求输入 `yes`（大小写均可）。时区和语言环境可选，留空时保持系统设置。步骤结果记录在目标用户的 `~/.local/state/server-shell-kit/bootstrap.log`。脚本失败后会停止，可修复问题后重新运行。

菜单中的管理员用户、SSH 公钥和 UFW 防火墙是独立操作。新管理员需要设置密码并提供公钥；脚本会将其加入 sudo 组。配置公钥后，请从另一个会话验证登录；启用防火墙前确认 SSH 端口及其他需要开放的 TCP 端口。脚本不会自动关闭密码登录、修改 SSH 服务端配置或把用户加入 Docker 组。

只预览方案，不修改系统：

```bash
bash scripts/bootstrap.sh --plan base
```

`base` 可替换为 `dev` 或 `container`。该命令适用于本地检出的仓库。

## 编程环境安装

主菜单选择“编程环境”。用 ↑↓ 移动，按 Enter 勾选或取消 Java、Python、Node.js、Rust；选中“下一步”并按 Enter，确认后逐项安装。安装失败不会阻止其他已选项目，结束时会显示每项结果。该菜单需要交互式终端。

Java 使用 SDKMAN 安装最新稳定 JDK 与 Maven；Python 使用 uv 安装托管 Python 并提供默认 `python`、`python3` 命令；Node.js 使用 nvm 安装当前稳定版与 npm；Rust 使用 rustup 安装 stable 工具链（包含 Cargo）。安装后自动设置国内包源：Maven 使用阿里云公共仓库，uv 使用清华 PyPI，npm 使用 npmmirror，Cargo 使用中科大 crates 镜像，无需输入地址。只调整目标用户的配置，首次覆盖现有文件前会保存 `.server-shell-kit.bak` 备份。已有工具会复用，重新选择时会检查或更新默认版本与包源；重新登录后 Zsh 环境设置生效。开发服务器方案只安装通用编译依赖，不自动安装这些语言版本。

## 环境体检

主菜单选择“环境体检”可查看目标用户的终端组件、四种编程环境，以及 Docker、SSH、UFW 和 SSH 公钥状态。进入页面后逐项显示检测进度和结果，无需等待所有项目完成才看到内容。结果区分正常、未安装、异常与无法判断；未安装的可选项不算故障。编程环境会检查默认工具链及新 Zsh 会话中的命令可用性；缺少服务管理器或读取权限时显示“无法判断”。体检只读，不自动修复。

异常项后会显示处理编号。输入编号可进入对应配置菜单；终端组件和编程环境会预勾选该项，服务器服务会在初始化菜单提示相关选项。返回体检页后会重新检查状态。也可单独运行 `bash scripts/doctor.sh` 获取制表符分隔的诊断结果。

## 环境发现与状态快照

在本地检出的仓库运行 `bash scripts/discover.sh`，可向标准输出获取 `schema_version: 1` 的 JSON 状态报告。运行 `bash scripts/snapshot.sh` 会将同一报告保存到 `~/.local/share/server-shell-kit/snapshots/`，文件权限为 `0600`；可用绝对路径环境变量 `SERVER_SHELL_KIT_SNAPSHOT_DIR` 指定其他目录。两者都无需交互，也不会修改系统配置。

报告包含系统、普通用户、网络、systemd 服务、编程工具和 Docker 元数据。数据库部分仅根据 systemd 单元和 Docker 镜像名称判断 PostgreSQL、MySQL、MariaDB、Redis 是否存在或运行，不连接数据库。缺少命令或读取权限时相应字段标记为 `unavailable`。报告不会读取密码、SSH 私钥、环境变量或 Docker 容器环境配置。

## Docker 安装与镜像加速

主菜单的“Docker”可独立安装发行版提供的 Docker 和可用的 Compose 插件，也可只更新现有 Docker 的镜像加速配置。“容器服务器”方案安装 Docker 后同样提供可选的镜像加速设置。输入一个或多个 HTTPS 镜像地址，多个地址用逗号分隔；留空时保持原配置。项目不预设第三方镜像地址。

镜像地址写入 `/etc/docker/daemon.json` 的 `registry-mirrors` 字段，其他字段会保留。脚本先校验新配置，保存原文件备份，再重启 Docker；若重启失败会恢复修改前的配置。未自动把用户加入 `docker` 组，日常使用请运行 `sudo docker`。镜像加速只针对 Docker Hub 拉取；地址是否可用取决于镜像服务本身。

## 软件源切换与迁移备份

“系统工具”菜单提供 APT 软件源切换：清华 TUNA、中科大 USTC、恢复首次切换前的源。切换仅替换 Debian/Ubuntu 官方源地址，展示差异并确认后执行；原文件保存到 `/var/backups/server-shell-kit/apt/original`。脚本运行 `apt-get update` 验证，失败时恢复本次切换前的文件。Debian 安全更新源保持官方地址。Ubuntu 端口架构使用对应的 `ubuntu-ports` 镜像路径。

迁移备份导出选定的 Shell、Git、Vim、Tmux 配置与 SSH `authorized_keys`，并保存系统信息、APT 源、已安装软件包与已启用服务清单。备份目录默认位于目标用户 HOME 下，权限为 `0700`。将整个目录复制到新机器，再在菜单中选择“从备份目录导入”。导入会校验文件、备份已有个人配置，并合并公钥；系统源和软件清单仅供参考，不自动覆盖或批量安装。备份不包含 SSH 私钥、数据库和 Docker 数据。

## 结构化备份

`backup.sh` 提供 `config`（配置）、`data`（数据）和 `full`（两者）三种类型；数据库名和自定义目录必须显式指定。输出目录默认在当前用户 HOME，可用 `--output-dir` 指定其他绝对目录。

```bash
bash scripts/backup.sh config
bash scripts/backup.sh data --path /opt/app --postgres-db appdb --mysql-db appdb
bash scripts/backup.sh full --postgres-source docker:pg --postgres-db appdb --mysql-source docker:mysql --mysql-db appdb
bash scripts/backup.sh full --secrets encrypt --path /opt/app
gpg --decrypt server-shell-kit-backup-YYYYMMDD-HHMMSS-XXXXXXXX.tar.gz.gpg | tar -tzf -
```

数据库默认从系统服务导出；`--postgres-source` 和 `--mysql-source` 可指定 Docker 容器，`--postgres-user`、`--mysql-user` 可指定数据库用户。PostgreSQL 用 `pg_dump` 导出指定数据库，并用 `pg_dumpall --globals-only` 导出全局角色；MySQL/MariaDB 使用 `mysqldump --single-transaction`，适用于事务表。脚本不接收命令行密码，身份验证须由数据库现有配置提供。未指定数据库名时不进行数据库访问；若快照发现该数据库正在运行，则将对应模块记为 `FAILED`。全局角色文件可能包含密码哈希，备份文件应按敏感数据保管。

每次备份均包含 `snapshot.json`、`manifest.json` 和已完成模块的文件。Manifest 记录 `SUCCESS`、`FAILED`、`SKIPPED`，以及文件大小和 SHA-256；单个模块失败不会删除其他模块的结果。备份目录权限为 `0700`，文件权限为 `0600`。备份前按文件名和配置键名列出可能的敏感文件；交互终端可选择跳过、包含或加密，非交互环境默认跳过，也可显式传入 `--secrets skip|include|encrypt`。`include` 会将这些文件明文纳入备份，`encrypt` 会要求在终端输入 GPG 口令，生成整包 AES-256 加密文件并清理临时明文目录。SSH 私钥和 `/etc/shadow` 不允许通过自定义目录自动纳入。Docker 镜像仅保存名称、tag 和 digest 等元数据，不导出镜像层；正在使用或关联数据库容器的 Volume 会跳过并写入 Manifest。Compose 文件仅在可读取且未命中敏感项检查时复制。自定义目录按读取时状态归档，不会冻结运行中的应用。未选择加密时，请按包含敏感业务数据的文件保管备份。

[清华 Ubuntu 镜像说明](https://mirrors.tuna.tsinghua.edu.cn/help/ubuntu/)、[清华 Debian 镜像说明](https://mirrors.tuna.tsinghua.edu.cn/help/debian/)、[中科大镜像说明](https://mirrors.ustc.edu.cn/help/debian.html)。

## 高危命令保护

一级风险需要输入 `yes`（大小写均可），二级风险需要重新输入完整命令。

交互式 Zsh 中执行 `rm -rf` 时，自动备份默认开启：确认后会先将现存目标复制到 `~/.local/share/server-shell-kit/rm-backups/`，并写入原路径清单 `paths.txt`；备份成功后才执行删除。备份失败时取消命令。为确保备份范围准确，开启备份时仅支持独立的 `rm -rf` 命令和明确的字面路径；包含通配符、变量展开或复合命令的删除会被取消。备份目录需有足够空间，删除包含该备份目录的路径也会被取消。可在“终端环境 → 高危命令保护设置”中查看或切换 Danger Guard 和 rm 递归删除备份状态；关闭备份后仍保留高危命令确认。也可在 Zsh 中使用 `dcg-backup-enable`、`dcg-backup-disable` 和 `dcg-backup-status`。

测试：

```bash
dcg-status
dcg-test 'rm -rf /tmp/test'
dcg-test 'rm -rf /opt/test'
dcg-test 'docker volume prune'
dcg-test 'iptables -F'
```

> 该功能用于防止交互式 Zsh 中的手滑误操作，不是系统安全边界。脚本、cron、systemd、程序 exec 等不会经过 ZLE 拦截。


## 更新与卸载

主菜单提供新服务器初始化、终端环境、编程环境、Docker、环境体检、系统工具、更新配置和卸载。终端环境子菜单提供完整安装、自选组件和高危命令保护设置；系统工具子菜单提供 APT 镜像、管理员用户、SSH Key、UFW 和配置迁移。自选组件菜单支持多选：方向键移动、Enter 勾选，选择“下一步”后统一确认并逐项执行，最后显示每项结果；可单独安装或更新组件。菜单中的“更新配置”只更新已经存在的 Starship、Alias 和高危命令保护文件，不安装缺失组件，也不重复安装系统软件。配置文件首次被覆盖前会保存同目录下的 `.server-shell-kit.bak` 备份。卸载仅移除工具文件和它添加到 `.zshrc` 的启动行，不卸载 Zsh、Starship 或系统插件，也不自动覆盖之后的个人修改。
