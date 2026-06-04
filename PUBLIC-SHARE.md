# 外部免登录分享

访客隔离、问题统计和省 Token 方案见：[ANALYTICS-AND-TOKEN-SAVING.md](./ANALYTICS-AND-TOKEN-SAVING.md)

本地访客实例已经启动：

```text
http://localhost:3001
http://192.168.15.5:3001
```

直接打开“需求文档”模型的链接：

```text
http://192.168.15.5:3001/?models=requirement-docs-kb
```

指定默认语言可以加 `lang` 参数：

```text
http://192.168.15.5:3001/?models=requirement-docs-kb&lang=en-US
```

访客页面右上角有语言筛选按钮。用户选择语言后：

- 页面常用文字会切换到对应语言
- 后续回答会按所选语言输出
- Open WebUI 原生语言设置入口默认隐藏

部署到服务器后，把域名换成你的服务器域名即可：

```text
https://你的域名/?models=requirement-docs-kb
```

## 当前验证结果

已验证：

```text
免登录：通过
直选模型：通过
模型：需求文档
模型 ID：requirement-docs-kb
知识库：需求文档
知识库外问题拒答：通过
只显示需求文档模型：通过
隐藏访客多余菜单：通过
顶部只保留需求文档模型选择：通过
隐藏引用来源和资料文件名：通过
```

测试问题：

```text
这个产品的价格是多少？
```

返回：

```text
知识库中没有找到相关资料。
```

## 本地访客实例命令

```bash
./start-public.sh
./status-public.sh
./logs-public.sh
./stop-public.sh
```

把主实例里的“需求文档”模型和知识库同步到访客实例：

```bash
./sync-public-requirement-model.sh
```

每次在后台新上传资料后，需要先确认资料已经加入后台的“需求文档”知识库，然后再运行上面的同步脚本。脚本只会同步绑定在“需求文档”知识库里的文件，并会在终端列出本次同步的文件名。

## 自动同步上传内容

分人员、分知识库、敏感资料登录访问方案见：[ACCESS-CONTROL.md](./ACCESS-CONTROL.md)。

如果希望以后上传的内容自动同步到外部访问链接，启动自动同步服务：

```bash
./start-auto-sync.sh
```

在 macOS 上，`./start-auto-sync.sh` 会安装一个 LaunchAgent，让系统每 60 秒自动检查一次。

安全模式下，自动同步只同步已经明确加入“需求文档”公开知识库的文件，不会把所有新上传资料自动公开。

流程：

- 可以公开给外部免登录访问的资料：上传后加入“需求文档”知识库。
- 敏感资料：上传后加入单独的内部知识库，例如“内部资料”或“客户A资料”，不要加入“需求文档”。
- 自动任务会对比管理员后台和访客端的“需求文档”文件列表。
- 自动任务也会检查公开模型名称、提示词、知识库描述、文件内容等公开配置。
- 只有发现访客端落后时，才同步并重启访客端。

查看自动同步状态：

```bash
./status-auto-sync.sh
```

停止自动同步：

```bash
./stop-auto-sync.sh
```

如需调整检查间隔，例如每 30 秒检查一次：

```bash
AUTO_SYNC_INTERVAL_SECONDS=30 ./start-auto-sync.sh
```

## 服务器部署文件

部署到服务器时，需要这些文件：

```text
docker-compose.public.yml
.env.public
public-custom.css
start-public.sh
stop-public.sh
status-public.sh
logs-public.sh
sync-public-requirement-model.sh
attach-all-uploads-to-requirement-knowledge.sh
public-sync-signature.sh
sync-public-once-if-needed.sh
auto-sync-public.sh
standalone-auto-sync-once.sh
start-auto-sync.sh
stop-auto-sync.sh
status-auto-sync.sh
install-auto-sync-launch-agent.sh
uninstall-auto-sync-launch-agent.sh
list-knowledge-files.sh
unpublish-file-from-public.sh
docker-bin.sh
seed-docs/
```

服务器上的 `.env.public` 保持：

```bash
PUBLIC_WEBUI_PORT=3001
WEBUI_AUTH=False
ENABLE_SIGNUP=False
WEBUI_NAME=在线问答
MODEL_PROVIDER_NAME=deepseek
OPENAI_API_BASE_URL=https://api.deepseek.com/v1
OPENAI_API_KEY=你的 DeepSeek Key
OPENAI_MODEL=deepseek-chat
DEFAULT_MODELS=requirement-docs-kb
DEFAULT_PINNED_MODELS=requirement-docs-kb
ENABLE_CUSTOM_MODEL_FALLBACK=True
MODEL_FILTER_LIST=requirement-docs-kb
BYPASS_MODEL_ACCESS_CONTROL=False
RESET_CONFIG_ON_START=true
```

访客实例会把默认用户降级为普通用户，并只给 `requirement-docs-kb` 授权，所以模型下拉里只显示“需求文档”。

访客实例不会展示引用来源和资料文件名，只显示回答正文。

## 注意

访客实例是免登录的，只放允许外部人查看的资料。

不要把管理员实例 `3000` 直接开放给外部人。
