# 外部免登录分享

本地访客实例已经启动：

```text
http://localhost:3001
http://192.168.15.5:3001
```

直接打开“需求文档”模型的链接：

```text
http://192.168.15.5:3001/?models=requirement-docs-kb
```

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

## 注意

访客实例是免登录的，只放允许外部人查看的资料。

不要把管理员实例 `3000` 直接开放给外部人。
