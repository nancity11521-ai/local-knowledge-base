# 管理员分配模型和自定义角色

Open WebUI 的基础账号角色通常是：

- `admin`
- `user`
- `pending`

业务上的角色类型建议用“用户组”实现，例如：

- 内部员工
- 售后人员
- 客户A
- 供应商B

这样管理员可以增加、删除角色，也可以给角色分配模型和知识库。

## 创建登录用户

```bash
./create-login-user.sh user@example.com 张三 'Temp@123456' user
```

创建后，用户从内部登录入口访问：

```text
http://localhost:3000
http://192.168.15.7:3000
```

## 创建角色

```bash
./role-access.sh create-role 内部员工 "内部敏感资料访问"
./role-access.sh create-role 客户A "客户A专属资料访问"
```

## 用户加入角色

```bash
./role-access.sh add-user 内部员工 user@example.com
```

移除用户：

```bash
./role-access.sh remove-user 内部员工 user@example.com
```

## 给角色分配模型

先查看模型：

```bash
./role-access.sh list-models
```

授权某个角色访问模型：

```bash
./role-access.sh grant-model 内部员工 requirement-docs-kb
```

取消授权：

```bash
./role-access.sh revoke-model 内部员工 requirement-docs-kb
```

## 给角色分配知识库

先查看知识库：

```bash
./role-access.sh list-knowledge
```

授权某个角色访问知识库：

```bash
./role-access.sh grant-knowledge 内部员工 内部资料
```

取消授权：

```bash
./role-access.sh revoke-knowledge 内部员工 内部资料
```

## 查看当前权限

```bash
./role-access.sh list-users
./role-access.sh list-roles
./role-access.sh list-access
```

## 推荐权限结构

公开免登录：

- 入口：`3001`
- 模型：`智能问答`
- 知识库：`需求文档`
- 内容：不敏感、可公开资料

内部登录：

- 入口：`3000`
- 账号：管理员创建
- 角色：用用户组管理
- 模型：按角色授权
- 知识库：按角色授权

## 注意

不要把敏感资料加入外部公开知识库“需求文档”。

如需隐藏某个公开文件：

```bash
./unpublish-file-from-public.sh 文件名关键词
```
