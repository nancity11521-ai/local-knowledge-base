# 快速使用

部署目录：

```bash
cd /Users/onegoogle/Desktop/codex/显示器/显示器文档/local-knowledge-base
```

当前访问地址：

```text
本机：http://localhost:3000
局域网：http://192.168.15.5:3000
访客免登录：http://192.168.15.5:3001/?models=requirement-docs-kb
```

如果网络换了，运行：

```bash
./show-url.sh
```

配置大模型 API：

```bash
./configure-api.sh https://api.example.com/v1 sk-your-api-key model_name
./restart.sh
```

日常命令：

```bash
./doctor.sh
./status.sh
./open.sh
./start.sh
./stop.sh
./restart.sh
./logs.sh
./start-public.sh
./status-public.sh
```

数据备份：

```bash
./backup.sh
```

数据恢复：

```bash
./restore.sh backups/open-webui-data-YYYYMMDD-HHMMSS.tar.gz
```

恢复会覆盖当前账号、知识库、上传文件和设置。恢复前先运行一次 `./backup.sh`。

第一批可上传资料：

```text
seed-docs/显示器电商详情页文案（15张）.md
```
