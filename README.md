# 本地知识库部署包

最快使用方式见：[QUICKSTART.md](./QUICKSTART.md)

部署包文件说明见：[PACKAGE.md](./PACKAGE.md)

外部免登录分享见：[PUBLIC-SHARE.md](./PUBLIC-SHARE.md)

这个部署包用于搭建一个本地网页知识库：

- 文档存放在本机 Docker 数据卷中
- 浏览器访问，不需要给每台电脑安装客户端
- 使用 OpenAI 兼容的大模型 API 做总结和问答
- 支持多人账号
- 第一版适合局域网使用，后续可加域名和外网访问

## 1. 安装 Docker Desktop

先安装 Docker Desktop，并确认终端里能运行：

```bash
docker --version
docker compose version
```

如果这两个命令能正常显示版本，就可以继续。

## 2. 配置大模型 API

进入本目录：

```bash
cd /Users/onegoogle/Desktop/codex/显示器/显示器文档/local-knowledge-base
```

复制配置文件：

```bash
cp .env.example .env
```

打开 `.env`，把下面几行换成你要接入的大模型 API 信息：

```bash
MODEL_PROVIDER_NAME=your-model-provider
OPENAI_API_BASE_URL=https://your-provider.example.com/v1
OPENAI_API_KEY=sk-your-model-api-key
OPENAI_MODEL=your-model-name
```

只要这个 API 兼容 OpenAI 格式，一般就可以直接接入。比如 DeepSeek 可以这样写：

```bash
MODEL_PROVIDER_NAME=deepseek
OPENAI_API_BASE_URL=https://api.deepseek.com/v1
OPENAI_API_KEY=你的 DeepSeek Key
OPENAI_MODEL=deepseek-chat
```

如果你用的是另一个大模型，把它提供的 `base_url`、`api_key`、`model` 填进去即可。

也可以用脚本写入，避免手动改错：

```bash
./configure-api.sh https://your-provider.example.com/v1 sk-your-api-key model_name
```

不带参数运行 `./configure-api.sh` 时，会逐项提示你输入。

如果想记录供应商名，也可以用四参数写法：

```bash
./configure-api.sh provider_name https://your-provider.example.com/v1 sk-your-api-key model_name
```

## 3. 启动

启动前可以先检查配置：

```bash
./check.sh
```

```bash
./start.sh
```

启动后浏览器打开：

```text
http://localhost:3000
```

也可以运行：

```bash
./show-url.sh
```

它会打印本机和局域网访问地址。

第一次注册的用户会成为管理员。

常用命令：

```bash
./doctor.sh
./status.sh
./open.sh
./restart.sh
./stop.sh
./backup.sh
./restore.sh --help
./logs.sh
./update.sh
```

## 4. 上传知识库文件

登录后，在 Open WebUI 里进入知识库/文档相关页面，上传你的资料。

第一批资料已经放在：

```text
seed-docs/
```

你当前文件夹里这些内容也可以作为后续资料：

- `显示器电商详情页文案（15张）.md`
- `产品图/`
- `详情页生成图/`
- `参考图/`

建议先上传 Markdown、PDF、Word、TXT 等文本资料。图片类资料如果需要总结，需要额外配置 OCR 或先转成文字。

## 5. 局域网多人访问

在这台电脑上查看本机 IP：

```bash
ipconfig getifaddr en0
```

假设显示为 `192.168.1.50`，同一 Wi-Fi/局域网的人可以访问：

```text
http://192.168.1.50:3000
```

如果网络切换，这个地址会变化，以 `./show-url.sh` 的输出为准。

## 6. 外部人员访问

外部人员访问不要直接裸露端口。建议第二阶段再配置：

- 域名，例如 `kb.yourdomain.com`
- HTTPS
- Cloudflare Tunnel 或 Nginx/Caddy
- 强密码/账号权限
- 必要时限制外部人员只能访问指定知识库

## 7. 停止服务

```bash
./stop.sh
```

## 8. 数据位置

知识库和系统数据保存在 Docker volume：`open-webui-data`。

备份数据：

```bash
./backup.sh
```

备份文件会保存到：

```text
backups/
```

从备份恢复数据：

```bash
./restore.sh backups/open-webui-data-YYYYMMDD-HHMMSS.tar.gz
```

恢复会覆盖当前账号、知识库、上传文件和设置。执行前建议先跑一次 `./backup.sh`。

## 9. 常见问题

### 查看运行日志

```bash
./logs.sh
```

持续查看日志：

```bash
./logs.sh --follow
```

### 更新 Open WebUI

```bash
./update.sh
```

更新脚本会先运行 `./backup.sh`，再拉取新镜像并重启服务。

### 终端提示 `docker: command not found`

说明 Docker Desktop 还没有安装，或者安装后终端还没识别到 Docker。安装 Docker Desktop，打开一次 Docker Desktop，等它显示运行中，再重新打开终端测试：

```bash
docker --version
docker compose version
```

本部署包的脚本也会自动尝试使用 Docker Desktop 自带的 CLI：

```text
/Applications/Docker.app/Contents/Resources/bin/docker
```

### 局域网其他电脑打不开

先确认本机能打开 `http://localhost:3000`。然后确认两台电脑在同一网络，并查看本机 IP：

```bash
ipconfig getifaddr en0
```

如果是有线网络，也可以试：

```bash
ipconfig getifaddr en1
```

### 修改 `.env` 后没有生效

Open WebUI 的部分配置首次启动后会写入内部数据库。已经启动过的情况下，优先在 Admin Panel 里修改模型连接；如果只是测试环境，也可以删除 Docker volume 后重新初始化，但这会清空账号和知识库数据。
