# 访客隔离、问题统计和省 Token 方案

## 1. 访客聊天互不干扰

外部免登录端口是 `3001`。免登录模式下，Open WebUI 后台会把所有访客视为同一个公共用户，所以第一版采用“公共端无历史”的方式处理：

- 页面已隐藏左侧历史对话、菜单和引用来源。
- `cleanup-public-chats.sh` 会自动删除公共端旧聊天。
- 后台自动同步任务每 60 秒运行一次，也会顺手清理公共端聊天。

默认保留时间在 `.env.public`：

```bash
PUBLIC_CHAT_RETENTION_SECONDS=60
```

如果要做到严格的一人一历史、一人一权限，使用内部登录端：管理员创建账号，按角色分配模型和知识库。敏感知识库不要放在免登录公共端。

## 2. 问题统计

生成访客问题统计：

```bash
./question-analytics.sh
```

输出文件：

```text
analytics/question-analytics.json
analytics/question-analytics.md
```

当前统计内容：

- 高频问题
- 高频型号/机型关键词
- 按小时的问题量
- 原始问题明细

后续如果要做成可视化后台，可以直接读取 `analytics/question-analytics.json`。

## 3. 省 Token 缓存

公共访客端已接入本地缓存代理：

```text
Open WebUI public -> token-cache-proxy -> DeepSeek API
```

如果两个请求的模型、提示词、知识库上下文和问题完全一致，并且缓存还没过期，第二次会直接返回缓存答案，不再请求 DeepSeek。

缓存有效期在 `.env.public`：

```bash
CACHE_TTL_SECONDS=604800
```

查看缓存命中情况：

```bash
./token-cache-stats.sh
```

说明：知识库内容更新后，Open WebUI 发给模型的上下文通常会变化，缓存键也会变化，因此不会错误复用旧知识库答案。

## 4. 其他省 Token 建议

- 把公开知识库拆小：一个模型只绑定需要回答的文档，不把所有资料都塞进去。
- 给高频问题整理 FAQ 文档，让检索更快命中短文本。
- 敏感资料单独建知识库，只分配给登录用户，避免公共端检索到无关内容。
- 如果 Open WebUI 后台有检索参数，降低 Top K 或相似度召回数量。
- 保持文档标题和段落结构清晰，减少模型读到无关段落。
- 外部端关闭引用来源展示，只输出答案。
