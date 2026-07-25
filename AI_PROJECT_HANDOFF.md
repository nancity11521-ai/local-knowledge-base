# GMKtec 本地 AI 知识库项目交接文档

更新时间：2026-07-25  
适用对象：接手本项目的 AI、开发者、运维人员

> 重要约定：每次回复用户前，先回复「南城。」

## 1. 项目目标

本项目是 GMKtec 本地 AI 客服知识库系统，目标是：

- 管理员在后台上传、管理知识库资料。
- 外部用户无需登录即可访问公开问答页面。
- 公开端只能使用指定公开模型和指定公开知识库回答。
- 敏感资料只留在管理员后台或私有知识库，不同步到公开端。
- 支持中文、英文、日文、韩文、西班牙文、法文、德文、阿拉伯文。
- 用户选择语言后，公开端界面和 AI 回复都应使用该语言。
- 后台提供访问统计、问题分析、热门问题、型号统计、语言咨询统计。
- 使用 DeepSeek 兼容 OpenAI API，并通过缓存减少重复问题的 Token 消耗。

## 2. 仓库与目录

GitHub 仓库：

```text
https://github.com/nancity11521-ai/local-knowledge-base.git
```

Ubuntu 部署目录：

```bash
~/local-knowledge-base
```

Mac 本机当前项目目录：

```text
/Users/onegoogle/Desktop/codex/05_知识库与资料库/本地知识库/本地知识库/local-knowledge-base
```

每次修改后通常需要：

```bash
git status --short
git add <相关文件>
git commit -m "说明"
git push origin main
```

禁止提交：

- `.env`
- `.env.public`
- `*.bak`
- API Key
- FRP Token
- 管理员账号密码

## 3. 系统架构

| 入口 | 云端转发 | 本地服务 | 说明 |
|---|---|---|---|
| `https://qa-admin.gmktec.cn` | 宝塔 Nginx → FRP 12700 | Ubuntu 3000 | 管理员 Open WebUI |
| `https://qa.gmktec.cn` | 宝塔 Nginx → FRP 12701 | Ubuntu 3001 | 公开问答 Open WebUI |
| `https://qa.gmktec.cn/analytics-api/` | 宝塔 Nginx → FRP 12702 | Ubuntu 3002 | 缓存与统计 API |

阿里云公网 IP：

```text
47.112.136.23
```

## 4. Docker 服务

Ubuntu 上核心容器：

| 容器 | 端口 | 作用 |
|---|---:|---|
| `local-knowledge-base` | 3000 | 管理员 Open WebUI |
| `local-knowledge-base-public` | 3001 | 公开端 Open WebUI |
| `local-knowledge-base-token-cache` | 3002 | Token 缓存与统计服务 |

注意：如果 Docker Compose 使用项目名前缀，公开端容器名称可能不是固定的 `local-knowledge-base-public`。脚本已通过 `public-container.sh` 自动解析真实容器，避免 “No such container” 或容器名冲突。

常用检查：

```bash
cd ~/local-knowledge-base
docker ps --filter name=local-knowledge-base
curl -I --max-time 10 http://127.0.0.1:3000
curl -I --max-time 15 http://127.0.0.1:3001
curl --max-time 10 http://127.0.0.1:3002/analytics/stats
```

## 5. 核心文件说明

| 文件 | 作用 |
|---|---|
| `docker-compose.yml` | 管理员后台服务配置 |
| `docker-compose.public.yml` | 公开端与统计缓存服务配置 |
| `public-loader.js` | 公开端前端增强脚本：语言、隐藏后台功能、隐藏来源、隐私处理 |
| `public-custom.css` | 公开端样式覆盖 |
| `inject-public-assets.sh` | 将公开端 JS/CSS 注入 Open WebUI 静态页面 |
| `token-cache-proxy.py` | DeepSeek/OpenAI 兼容代理、Token 缓存、统计 API、语言约束 |
| `sync-public-requirement-model.sh` | 从管理员端同步公开知识库、模型、文件、向量库、RAG 配置 |
| `sync-public-once-if-needed.sh` | 根据签名判断是否需要同步 |
| `auto-sync-public.sh` | systemd 循环同步服务，每 60 秒检查一次 |
| `public-sync-signature.sh` | 生成管理员端/公开端一致性签名 |
| `sync-public-api-config.sh` | 同步管理员后台 API Key / Base URL / 模型配置到公开端 |
| `public-container.sh` | 自动定位公开端真实容器 |
| `cleanup-public-chats.sh` | 清理公开端访客历史会话，避免用户互相看到问题 |
| `analytics-dashboard.sh` | 生成问题分析后台页面 |
| `analytics/` | 访问统计与问题分析静态后台页面 |

## 6. 公开端知识库同步逻辑

默认公开知识库名称：

```text
g3问题库
```

公开模型 ID：

```text
requirement-docs-kb
```

公开端不是直接读取管理员数据库，而是独立 Open WebUI 实例。同步脚本会复制：

- 指定公开知识库集合
- 已绑定到公开知识库的文档
- 上传文件
- 向量数据库
- 模型配置
- 模型绑定的知识库
- RAG 检索配置
- API 连接配置

关键原则：

- 只有绑定到 `g3问题库` 的文件才会同步到公开端。
- 管理员后台模型配置是唯一来源。
- 公开端只附加语言要求，不应额外改变知识库规则。
- 同步后会清理公开端过期回答缓存，避免旧答案继续显示。

手动同步：

```bash
cd ~/local-knowledge-base
KNOWLEDGE_NAME='g3问题库' MODEL_ID='requirement-docs-kb' ./sync-public-requirement-model.sh
./inject-public-assets.sh
```

自动同步服务：

```bash
sudo systemctl status local-knowledge-base-public-sync
sudo systemctl restart local-knowledge-base-public-sync
```

## 7. 已修复/必须保持的关键行为

### 7.1 管理员后台与公开端答案一致

设计目标：同一个问题，在同一语言下，事实、知识范围和结论必须一致。

实现要点：

- 公开端模型从管理员端模型重建。
- 温度等生成参数保持同步。
- RAG 检索配置保持同步，避免 top_k、阈值不同。
- 公开端只附加“回复语言”要求。
- 中文场景不额外注入公开端语言系统提示，减少与后台差异。
- 同步后清理公开端过期回答缓存。

验证：

```bash
cd ~/local-knowledge-base
KNOWLEDGE_NAME='g3问题库' MODEL_ID='requirement-docs-kb' ./public-sync-signature.sh main
KNOWLEDGE_NAME='g3问题库' MODEL_ID='requirement-docs-kb' ./public-sync-signature.sh public
```

两个输出的签名应一致。

### 7.2 多语言回复

公开端通过 `public-loader.js` 和 `token-cache-proxy.py` 双层保证：

- 用户选择英文，回复只能英文。
- 用户选择日文，回复只能日文。
- 用户选择韩文，回复只能韩文。
- 中文模式下尽量保持与后台中文回答一致。

如果切换语言后仍回复中文：

```bash
cd ~/local-knowledge-base
./inject-public-assets.sh
docker compose --env-file .env.public -f docker-compose.public.yml up -d token-cache-proxy open-webui-public
```

然后浏览器强制刷新：`Ctrl + Shift + R`。

### 7.3 公开端不能显示来源

公开端必须隐藏：

- 正文中的来源标签
- 文件名小灰块
- 底部“引用来源”列表
- `query_knowledge_files` 等工具检索明细
- 可展开的来源/索引信息

实现位置：

- `public-loader.js`
- `public-custom.css`
- `inject-public-assets.sh`

如果公开端仍显示来源，优先执行：

```bash
cd ~/local-knowledge-base
git -c http.version=HTTP/1.1 pull --ff-only origin main
./inject-public-assets.sh
```

然后用无痕窗口重新测试。

### 7.4 公开端不能看到其他用户的问题

公开端必须是临时会话，不应共享历史问题。实现要点：

- `docker-compose.public.yml` 中强制临时聊天。
- `public-loader.js` 隐藏历史、搜索、用户菜单等后台功能。
- `cleanup-public-chats.sh` 清理公开端历史聊天。

如果又出现用户互相看到问题：

```bash
cd ~/local-knowledge-base
./cleanup-public-chats.sh
./inject-public-assets.sh
```

### 7.5 后台更换 API Key 后自动同步

管理员后台更换 API Key 后，不应每次手动进 Ubuntu 同步。当前自动同步服务会定时执行：

- `sync-public-api-config.sh`
- `sync-public-once-if-needed.sh`
- `analytics-dashboard.sh`

默认检查间隔 60 秒。更换 Key 后等 1-2 分钟，或重启：

```bash
sudo systemctl restart local-knowledge-base-public-sync
```

## 8. FRP 与宝塔 Nginx

FRP 服务端端口：

```text
7000
```

Ubuntu `frpc.toml` 必须包含三个代理：

```toml
serverAddr = "47.112.136.23"
serverPort = 7000

[auth]
method = "token"
token = "从安全位置读取，不写入代码仓库"

[[proxies]]
name = "kb-public"
type = "tcp"
localIP = "127.0.0.1"
localPort = 3001
remotePort = 12701

[[proxies]]
name = "kb-admin"
type = "tcp"
localIP = "127.0.0.1"
localPort = 3000
remotePort = 12700

[[proxies]]
name = "kb-analytics"
type = "tcp"
localIP = "127.0.0.1"
localPort = 3002
remotePort = 12702
```

重要：不要同时手动 `nohup ./frpc` 和 systemd `frpc.service` 启动多个 FRP，否则会出现：

```text
proxy [kb-public] already exists
```

推荐使用 systemd：

```bash
sudo systemctl status frpc
sudo systemctl restart frpc
journalctl -u frpc -n 80 --no-pager
```

宝塔 Nginx 中，`qa.gmktec.cn` 需要有：

```nginx
location ^~ /analytics-api/ {
  proxy_pass http://127.0.0.1:12702/;
  proxy_http_version 1.1;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_read_timeout 60s;
}
```

并确保：

- `qa.gmktec.cn` 反代到 `127.0.0.1:12701`
- `qa-admin.gmktec.cn` 反代到 `127.0.0.1:12700`
- 两个域名启用 HTTPS
- 阿里云安全组允许 80、443、7000

## 9. 部署步骤

Mac 本地修改后：

```bash
cd "/Users/onegoogle/Desktop/codex/05_知识库与资料库/本地知识库/本地知识库/local-knowledge-base"
git status --short
git add <相关文件>
git commit -m "说明"
git push origin main
```

Ubuntu 更新：

```bash
cd ~/local-knowledge-base
for i in 1 2 3 4 5; do
  timeout 45 git -c http.version=HTTP/1.1 pull --ff-only origin main && break
  sleep 10
done
```

启动/更新公开服务：

```bash
docker compose --env-file .env.public -f docker-compose.public.yml up -d token-cache-proxy open-webui-public
./inject-public-assets.sh
KNOWLEDGE_NAME='g3问题库' MODEL_ID='requirement-docs-kb' ./sync-public-requirement-model.sh
curl -I --max-time 15 http://127.0.0.1:3001
```

如需恢复自动同步：

```bash
sudo systemctl restart local-knowledge-base-public-sync
sudo systemctl status local-knowledge-base-public-sync
```

## 10. 常见问题排查

### 10.1 公开网页 502

502 通常是阿里云 Nginx 能访问 FRP，但 FRP 连不到 Ubuntu 本地 3001。

按顺序检查：

```bash
cd ~/local-knowledge-base
docker ps --filter name=local-knowledge-base
curl -I --max-time 15 http://127.0.0.1:3001
sudo systemctl status frpc
journalctl -u frpc -n 80 --no-pager
```

常见原因：

- 公开端容器正在重启。
- 自动同步每分钟重建公开容器。
- 容器名冲突。
- FRP 启动了多个实例。
- 公开端容器启动失败或 3001 未监听。

### 10.2 管理员后台与公开端答案不一致

检查：

```bash
cd ~/local-knowledge-base
KNOWLEDGE_NAME='g3问题库' MODEL_ID='requirement-docs-kb' ./public-sync-signature.sh main
KNOWLEDGE_NAME='g3问题库' MODEL_ID='requirement-docs-kb' ./public-sync-signature.sh public
```

修复：

```bash
KNOWLEDGE_NAME='g3问题库' MODEL_ID='requirement-docs-kb' ./sync-public-requirement-model.sh
./inject-public-assets.sh
```

同时确认公开 URL 使用：

```text
models=requirement-docs-kb
model=requirement-docs-kb
```

### 10.3 来源信息仍显示

执行：

```bash
cd ~/local-knowledge-base
git -c http.version=HTTP/1.1 pull --ff-only origin main
./inject-public-assets.sh
```

然后：

- 无痕窗口重新打开 `https://qa.gmktec.cn`
- 不要沿用旧聊天，创建新临时对话
- 浏览器强制刷新 `Ctrl + Shift + R`

### 10.4 问题分析后台不更新

检查统计 API：

```bash
curl --max-time 10 http://127.0.0.1:3002/analytics/stats
curl -I --max-time 10 https://qa.gmktec.cn/analytics-api/analytics/stats
```

重新生成后台：

```bash
cd ~/local-knowledge-base
./analytics-dashboard.sh
./inject-admin-assets.sh
```

访问：

```text
https://qa-admin.gmktec.cn/static/analytics/question-analytics-dashboard.html
https://qa-admin.gmktec.cn/static/analytics/access-analytics-dashboard.html
```

### 10.5 GitHub 拉取失败

如果出现：

```text
GnuTLS recv error (-110)
SSL connection timeout
```

使用：

```bash
cd ~/local-knowledge-base
for i in 1 2 3 4 5; do
  timeout 45 git -c http.version=HTTP/1.1 pull --ff-only origin main && break
  sleep 10
done
```

如果提示“不是 git 仓库”，说明当前目录不对，先：

```bash
cd ~/local-knowledge-base
```

## 11. 上线前验证清单

每次改动后至少验证：

- `git status --short` 没有误提交 `.env`、Key、Token。
- `docker ps` 三个服务运行正常。
- `curl -I http://127.0.0.1:3001` 返回 `200 OK`。
- `https://qa.gmktec.cn` 可以打开。
- 公开端不显示模型选择、历史对话、用户菜单、搜索、笔记等后台功能。
- 公开端不能看到其他用户问题。
- 公开端切换英文/日文/韩文后，AI 用对应语言回复。
- 公开端不显示来源文件名、引用来源、检索工具明细。
- 管理员后台和公开端对同一中文问题的事实与结论一致。
- 访问统计接口返回 JSON。

## 12. 接手 AI 的工作建议

1. 先读本文档，再读 `README.md`、`PUBLIC-SHARE.md`、`ANALYTICS-AND-TOKEN-SAVING.md`。
2. 修改前先 `git status --short`，确认已有改动是否属于用户。
3. 小范围修改，避免重构 Open WebUI 本体。
4. 公开端 UI 问题优先看 `public-loader.js`、`public-custom.css`、`inject-public-assets.sh`。
5. 同步和答案一致性问题优先看 `sync-public-requirement-model.sh`、`public-sync-signature.sh`、`token-cache-proxy.py`。
6. 502 优先查公开端容器、FRP 单实例、宝塔反代。
7. 所有密钥只在 Ubuntu `.env` / `.env.public` 或后台配置里维护，不写入仓库。

