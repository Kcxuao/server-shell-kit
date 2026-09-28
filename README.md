# Server Shell Kit

面向 Debian / Ubuntu 服务器的 Zsh 美化与高危命令防误操作工具。

## 功能

- 安装并切换到 Zsh
- Starship Prompt
- zsh-autosuggestions
- zsh-syntax-highlighting
- 常用 Git / Docker / Linux Alias
- 交互式高危命令拦截
- 菜单式安装、更新、卸载
- 模块脚本全部独立，可单独更新

## 仓库结构

```text
server-shell-kit/
├── install.sh
├── scripts/
│   ├── common.sh
│   ├── install-zsh.sh
│   ├── install-starship.sh
│   ├── install-plugins.sh
│   ├── install-danger-guard.sh
│   ├── install-aliases.sh
│   ├── install-full.sh
│   └── uninstall.sh
├── configs/
│   ├── aliases.zsh
│   └── starship.toml
└── plugins/
    └── dangerous-command-guard.plugin.zsh
```

## 使用

默认仓库地址为 `Kcxuao/server-shell-kit`。把本仓库推送到 GitHub 后执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kcxuao/server-shell-kit/main/install.sh)
```

如果仓库名或用户名不同，可通过环境变量覆盖：

```bash
SERVER_SHELL_KIT_OWNER=yourname SERVER_SHELL_KIT_REPO=yourrepo bash <(curl -fsSL https://raw.githubusercontent.com/yourname/yourrepo/main/install.sh)
```

## 高危命令保护

一级风险需要输入 `YES`，二级风险需要重新输入完整命令。

测试：

```bash
dcg-status
dcg-test 'rm -rf /tmp/test'
dcg-test 'rm -rf /opt/test'
dcg-test 'docker volume prune'
dcg-test 'iptables -F'
```

> 该功能用于防止交互式 Zsh 中的手滑误操作，不是系统安全边界。脚本、cron、systemd、程序 exec 等不会经过 ZLE 拦截。

## 建议

生产服务器建议使用 Git tag 固定版本，例如 `v1.0.0`，避免直接跟随 `main` 的最新修改。
