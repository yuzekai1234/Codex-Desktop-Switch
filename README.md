# Codex Desktop Switch (C-Switch)

面向 **Codex Desktop** 的 macOS 菜单栏工具：在多台 Mac 上管理多个 ChatGPT / Codex 账号，查看各账号额度，并通过 SSH 反向代理把本机代理与登录态同步到远程服务器。

应用名称：**C-Switch** · 仓库名：**Codex-Desktop-Switch**

---

## 功能

### 1. 多 Codex 账号管理

- 通过浏览器完成 OpenAI OAuth，将多个账号保存在本机。
- 在菜单栏面板中一键切换当前账号；切换后写入 `~/.codex/auth.json`，并可提示重启 Codex Desktop。
- 若某账号尚未单独保存 token，会在匹配时自动从当前 `~/.codex/auth.json` 导入（可先在本机 Codex 登录，再在 C-Switch 中切换）。

### 2. 多账号额度展示

在 **Manage accounts（管理账号）** 中点击 **Refresh usage**，为已保存 token 的账号拉取用量（需访问 `chatgpt.com`）：


| 信息             | 说明                 |
| -------------- | ------------------ |
| 5 小时 / 7 天滚动用量 | 已用百分比与重置时间         |
| Credits        | 积分余额（若有）           |
| 套餐档位           | 用于更新账号标签上的 plan 信息 |


> 用量接口为 ChatGPT 未公开 API，行为可能随官方变更；无 token 的账号需先 **Add account (browser login)**。

### 3. 远程 SSH 反向代理与 auth 同步

在 **Remote & Tunnel（远程与隧道）** 中可：

- **一键建立 SSH 反向隧道**（等价于 `ssh -N -R <远程端口>:127.0.0.1:<本地代理端口> user@host`），便于在服务器上通过本机代理访问网络。
- **手动将 `~/.codex/auth.json` 同步到服务器**（`scp`），便于在远程使用 Codex Desktop 前更新登录态。

菜单栏标题旁的 **绿点** 表示隧道正在运行。

---

## 环境要求

- macOS 14 或更高
- 已安装 [Codex Desktop](https://openai.com/codex)
- 从源码构建时需 [Swift 6](https://www.swift.org/download/) 工具链
- 使用远程功能时需配置 **SSH 公钥登录**（应用内不输入密码）

---

## 安装与运行

### 方式 A：构建 `.app`（推荐）

```bash
git clone https://github.com/yuzekai1234/Codex-Desktop-Switch.git
cd Codex-Desktop-Switch

# 生成 dist/C-Switch.app
./scripts/package_app.sh

# 构建并启动
./scripts/run_app.sh

# 可选：复制到桌面与「应用程序」文件夹
./scripts/install_app.sh
```

首次打开若提示 **「无法打开」** 或来自未识别开发者：

1. 在 **活动监视器** 中结束残留的 **C-Switch** 进程。
2. 重新执行 `./scripts/package_app.sh`。
3. **右键** `dist/C-Switch.app` → **打开** → 确认（仅首次需要）。

### 方式 B：命令行直接运行

```bash
cd Codex-Desktop-Switch
swift build -c release
.build/arm64-apple-macosx/release/C-Switch
```

---

## 使用指南

### 界面入口

- 点击菜单栏 **⇄** 图标（或 Dock 中的 C-Switch）打开面板。
- 主界面可进入 **Manage accounts**、**Remote & Tunnel**。

### 添加账号并切换

1. 打开菜单栏 **⇄** → **Add account (browser login)**，在浏览器完成登录授权。
2. 在账号列表中点击要使用的账号。
3. 按提示 **重启 Codex Desktop**（若已开启）。

### 查看各账号额度

1. 进入 **Manage accounts**。
2. 点击 **Refresh usage** 批量刷新。
3. 在对应账号行查看 5h / 7d 用量与 credits。

### 配置远程隧道

1. 进入 **Remote & Tunnel**。
2. 填写 **Host**、**Username**（首次使用需自行填写，仓库内不含个人默认服务器）。
3. 确认本机代理（如 Clash）已在 `127.0.0.1:<本地端口>` 监听（默认本地端口 `7890`）。
4. 点击 **Start tunnel**；停止时点击 **Stop tunnel**。

隧道命令预览示例：

```bash
ssh -N -R 18080:127.0.0.1:7890 your-username@your.server.example
```


| 配置项              | 说明                                         |
| ---------------- | ------------------------------------------ |
| Host / Username  | SSH 服务器地址与用户名                              |
| Local proxy port | 本机 HTTP/SOCKS 代理端口（常见 `7890`）              |
| Remote bind port | 在服务器上监听的转发端口（示例 `18080`）                   |
| Remote auth path | 远程 `auth.json` 路径（默认 `~/.codex/auth.json`） |


**Advanced** 中可修改 SSH 端口与远程 auth 路径。

### 服务器端代理环境（一次性配置）

隧道建立后，流量会出现在服务器本机的 **Remote bind port** 上（与 C-Switch 里填写的 **Remote bind port** 一致，按你实际配置为准，下文用 `<REMOTE_PORT>` 表示）。

在**服务器**上把代理环境变量写入 shell 配置（以 `~/.bashrc` 为例；若用 `zsh` 可改为 `~/.zshrc`）：

```bash
# 将 <REMOTE_PORT> 换成你在 C-Switch 中设置的 Remote bind port
REMOTE_PORT=<REMOTE_PORT>

cat >> ~/.bashrc <<EOF

# Proxy for Codex Desktop / Codex CLI (via SSH reverse tunnel from C-Switch)
export HTTPS_PROXY=http://127.0.0.1:${REMOTE_PORT}
export HTTP_PROXY=http://127.0.0.1:${REMOTE_PORT}
export ALL_PROXY=http://127.0.0.1:${REMOTE_PORT}
export https_proxy=\$HTTPS_PROXY
export http_proxy=\$HTTP_PROXY
export all_proxy=\$ALL_PROXY
EOF

source ~/.bashrc
```

示例：若 Remote bind port 为 `18080`，则 `REMOTE_PORT=18080`，代理地址为 `http://127.0.0.1:18080`。

使用前请确认：

1. Mac 上 C-Switch 隧道已 **Start tunnel**，且本机代理在 **Local proxy port** 上正常监听。
2. 在服务器上测试（将端口换成你的 `<REMOTE_PORT>`）：
  ```bash
   curl -I --proxy http://127.0.0.1:<REMOTE_PORT> https://www.google.com
  ```
3. 新开 SSH 会话或 `source ~/.bashrc` 后，再启动 Codex Desktop / Codex CLI，使其走上述代理。

### 同步登录态到服务器

在本地切换好账号后：

1. 确认终端可免密登录：`ssh your-username@your.server.example`
2. 在 **Remote & Tunnel** 中点击 **Sync auth.json to server**。

该操作为 **手动触发**，不会自动上传；适合在远程打开 Codex Desktop 之前更新服务器上的 `auth.json`。

远程相关配置保存在：

`~/Library/Application Support/C-Switch/remote-settings.json`

---

## 数据与安全


| 路径                                                     | 内容                            |
| ------------------------------------------------------ | ----------------------------- |
| `~/Library/Application Support/C-Switch/tokens/`       | 各账号 OAuth token（文件权限 `0600`）  |
| `~/Library/Application Support/C-Switch/accounts.json` | 账号列表元数据                       |
| `~/.codex/auth.json`                                   | Codex Desktop 当前会话（切换时由本应用写入） |
| `~/.codex/auth.json.cswitch.bak`                       | 切换前备份                         |


- 不使用 macOS 钥匙串，避免额外密码弹窗。
- 远程同步调用系统 `/usr/bin/ssh` 与 `/usr/bin/scp`，不在日志中输出 token 内容。
- OAuth 回调地址：`http://localhost:1455/auth/callback`
- **不依赖** `codex` CLI。

---

## 项目结构

```
Codex-Desktop-Switch/
├── Sources/CSwitch/     # Swift 源码
├── Resources/           # 应用图标
├── scripts/             # 构建、打包、安装脚本
├── Package.swift
└── README.md
```

---

## 免责声明

- 本项目为第三方工具，与 OpenAI / ChatGPT 无官方关联。
- 多账号与用量查询依赖 OpenAI 登录与接口，请遵守相关服务条款。
- 远程隧道与 auth 同步涉及你的服务器与网络环境，请自行评估安全风险。

---

## License

尚未指定开源协议；发布前请添加 `LICENSE` 文件。