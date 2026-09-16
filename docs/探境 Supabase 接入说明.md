# 探境 Supabase 接入说明

## 1. 创建数据库

在 Supabase Dashboard 的 SQL Editor 中执行：

```text
supabase/schema.sql
```

该脚本只新增 `explore_` 前缀的探境表，不修改共享项目已有的 `public.tasks` 和 `public.task_comments`。

执行前建议先确认当前项目中没有同名的 `explore_` 表；脚本使用 `if not exists`，重复执行不会重复创建表，但仍应先在测试分支验证 RLS。

该脚本包含：

- 用户画像
- 对话会话和消息
- 成长目标
- Memory
- 成长事件
- AI Observation
- AI Action
- Memory Relation
- 索引、更新时间触发器和 RLS

主要表名为：

- `public.explore_user_profiles`
- `public.explore_conversation_sessions`
- `public.explore_conversations`
- `public.explore_growth_goals`
- `public.explore_memory_items`
- `public.explore_growth_events`
- `public.explore_ai_observations`
- `public.explore_ai_actions`
- `public.explore_memory_relations`

## 2. 配置 Flutter

不要把 Supabase 密钥写入 Dart 源码。运行时通过 `--dart-define` 注入：

```bash
cd mobile
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

当前没有配置这两个参数时，App 不再使用 mock 数据，页面显示空状态；配置并登录后才能正常使用（mock 已于 2026-08-24 移除）。

## 3. 已接入的代码层

- `lib/config/supabase_config.dart`：运行时配置
- `lib/services/supabase_service.dart`：Supabase 初始化
- `lib/services/auth_service.dart`：注册、登录、登出和认证状态
- `lib/repositories/conversation_repository.dart`：会话和消息
- `lib/repositories/goal_repository.dart`：目标
- `lib/repositories/memory_repository.dart`：Memory

## 4. 当前边界

当前 Flutter 已接入：

- 配置 Supabase 后显示登录/注册页；未配置时显示空状态页面（mock 已移除）。
- 登录后按用户加载目标、Memory、历史会话和消息。
- 新建目标、发送消息会写入对应的 `explore_` 表。

AI 对话函数和 Memory 返回/落库协议已经写入代码，仍需部署 Edge Function、配置 DeepSeek Key 并进行真实账号联调。尚未完成 AI 目标生成和主动消息任务。远端为空时页面显示空状态（mock 初始内容已于 2026-08-24 移除）。

## 5. 部署 AI 对话函数

Flutter 不直接保存 DeepSeek Key。真实 AI 回复通过 Supabase Edge Function：

```bash
supabase functions deploy explore-conversation
supabase secrets set DEEPSEEK_API_KEY=your-key DEEPSEEK_MODEL=deepseek-chat
```

函数会校验登录用户只能访问自己的会话，读取最近 20 条消息，调用 DeepSeek，并返回回复和可选 Memory。函数未部署或调用失败时，Flutter 暂时回退为本地演示回复。

## 6. 共享项目安全说明

- 不要执行删除或重命名 `tasks`、`task_comments` 的 SQL。
- 不要删除共享项目已有的 `auth.users` 触发器。
- 探境不安装 `auth.users` 触发器，用户画像在登录后按需创建。
- 探境自己的函数、索引和 RLS policy 均使用 `explore_` 前缀。
