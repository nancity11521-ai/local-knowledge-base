# 部署包总览

当前状态：

```text
服务：已启动
容器：healthy
本机：http://localhost:3000
局域网：http://192.168.15.5:3000
访客免登录：http://192.168.15.5:3001/?models=requirement-docs-kb
模型 API：已配置 DeepSeek
访客模型列表：只显示需求文档
访客顶部菜单：已隐藏多余入口
备份：backups/open-webui-data-20260604-051047.tar.gz
```

核心文件：

```text
docker-compose.yml      Open WebUI 服务定义
.env                    本机真实配置，不要外发
.env.example            配置模板
README.md               完整说明
QUICKSTART.md           最短使用说明
PACKAGE.md              当前部署包总览
PUBLIC-SHARE.md         外部免登录分享说明
```

日常脚本：

```text
doctor.sh               一键体检
status.sh               查看地址、容器和模型配置状态
open.sh                 打开本机网页
start.sh                启动服务
stop.sh                 停止服务
restart.sh              重启服务
logs.sh                 查看日志
show-url.sh             显示本机和局域网访问地址
start-public.sh         启动外部访客免登录实例
status-public.sh        查看访客实例状态
stop-public.sh          停止访客实例
logs-public.sh          查看访客实例日志
```

配置和维护脚本：

```text
configure-api.sh        写入大模型 API 配置
backup.sh               备份 Open WebUI 数据卷
restore.sh              从备份恢复数据
update.sh               备份后更新 Open WebUI 镜像
check.sh                检查 Docker 和 API 配置
sync-public-requirement-model.sh  同步需求文档模型到访客实例
```

第一批资料：

```text
seed-docs/显示器电商详情页文案（15张）.md
```

DeepSeek 已接入：

```bash
./doctor.sh
```
