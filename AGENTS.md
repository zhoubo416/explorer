# 仓库开发约定

探境（Explore）是一个基于长期记忆的个人成长 Agent：Nuxt 3 Web 端 + Flutter 移动端 + Supabase 后端。AI 能力由 DeepSeek（对话与推理）和阿里云百炼 `text-embedding-v4`（1536 维向量化）提供。

## 目录结构与模块划分

- `app/` — Nuxt 3 SPA（`nuxt.config.ts` 中 `srcDir: 'app/'`、`ssr: false`）。入口 `app/app.vue` 按 `ViewId` 切换视图；**全部状态与数据访问集中在 `app/composables/useExplore.ts`**（含 `invokeWithRetry` 重试封装），`app/components/*.vue` 基本是纯展示组件；`app/plugins/supabase.client.ts` 注入 `$supabase`；`app/utils/markdown.ts`（marked + DOMPurify）经 `MarkdownText.vue` 渲染 AI 回复。
- `assets/css/main.css`、`assets/css/auth.css` — 全局样式。组件基本不写 `<style>`（唯一例外是 `GoalDetailView.vue` 的 scoped 块），新样式请加到全局 CSS。
- `mobile/` — Flutter 应用。**`lib/main.dart` 是唯一的大文件（约 4700 行）**，`ExploreStore`（`ChangeNotifier`，承载全部状态与 Supabase 调用）和几乎所有页面、组件都在里面；旁边只有薄封装层 `lib/services/`（supabase / auth / ai / insight）、`lib/repositories/`（conversation / goal / memory）和 `lib/config/supabase_config.dart`。改移动端 UI 或状态时，目标文件几乎总是 `main.dart`。
- `supabase/schema.sql` — 表、索引、触发器、RLS，以及语义检索 RPC `explore_match_memories`；`supabase/cron.sql` — pg_cron + pg_net 定时触发主动消息；`supabase/functions/` — 13 个已部署的 Edge Function。
- `docs/` — 中文的产品、技术、数据库设计文档。`docs/开发完结手册.md` 是功能清单 + 人工验收指南，判断「某功能是否已完成」以它为准。

## 常用命令

Web（仓库根目录）：

- `npm run dev` — 启动 Nuxt 开发服务器。
- `npm run build` / `npm run generate` — 生产构建 / 静态生成。
- `npm run typecheck` — 类型检查，实际执行的是 `nuxt typecheck`。
- `npm test` — 用 Node 内置 `node:test` 直接运行 `supabase/functions/explore-conversation/model-result.test.ts`（Node ≥ 22 可原生执行 TS，无需构建；不是 vitest）。

Mobile（`mobile/`）：

- `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` — 必须注入这两个参数；mock 数据已移除，不配置只会看到空状态。
- `flutter analyze` — 静态分析。
- `flutter test` — 运行 widget 测试。

后端（`supabase/`）：

- `supabase functions deploy <函数名>` — 部署 Edge Function。
- schema 变更以 `alter table ... if not exists` 的形式追加到 `schema.sql` 末尾，并在 Dashboard 的 SQL Editor 手动执行（脚本增量且幂等）。
- `supabase secrets set DEEPSEEK_API_KEY / DEEPSEEK_MODEL / DASHSCOPE_API_KEY / DASHSCOPE_BASE_URL / CRON_SECRET / SUPABASE_SERVICE_ROLE_KEY` — 配置函数密钥。
- 定时任务见 `supabase/cron.sql`，用 `select * from cron.job;` 核对。

## 编码风格与命名

- Web：Vue 3 Composition API + `<script setup lang="ts">`；组件 PascalCase，composable 与文件名 kebab-case。
- Mobile：Dart + `flutter_lints`；类 PascalCase，文件与方法 snake_case，私有成员 `_` 前缀。
- 数据库对象（表、索引、policy、函数）一律 `explore_` 前缀，例如 `explore_growth_goals`。
- 密钥不入库：Web 用 `NUXT_PUBLIC_*`，Flutter 用 `--dart-define`，Edge Function 用 `Deno.env.get`。

## 关键架构约定

1. **对话副作用全部在服务端**：`explore-conversation` 一次调用内完成助手回复、记忆落库、成长事件、向量化、记忆关系、目标阶段与状态更新。客户端（`app/composables/useExplore.ts`、`mobile/lib/main.dart`）只写用户消息并刷新本地状态，不要重复实现这些写入。回复是流式的，但**副作用在结束事件 `{"done":true}` 之前跑完**——客户端收到 `done` 才刷新记忆和目标，提前刷新会与数据库写入竞争。
2. **成长路径是 AI 推理结果**：`explore-profile` 把 `growth_dimensions` / `growth_composition` 写入 `explore_user_profiles`；UI 只读画像，不要用关键词匹配算分。
3. **对话是流式的**：`explore-conversation` 与 `explore-goal-chat` 都返回 SSE（`text/event-stream`），客户端要用原生 HTTP 逐块解析——`supabase.functions.invoke` 不支持流式。Web 端实现见 `useExplore.ts` 的 `consumeConversationStream` 与 `goalChat`，移动端见 `mobile/lib/services/ai_service.dart`。模型返回的是 JSON（`{"reply":...}`），所以服务端要边收边抽 `reply` 字段再下发，不能把原始流直接给用户（见 `explore-conversation/stream-reply.ts`）。
4. **低情绪陪伴是确定性状态机**：`explore_conversation_sessions.mood_stage` 由后端从 0 推进到 3（情绪理解 → 原因探索 → 区分方向/方法 → 给判断），不跳层、不重复。
5. **这是一个共享的 Supabase 项目**：只操作 `explore_` 前缀的对象；不要删除或重命名既有的 `public.tasks`、`public.task_comments`；不要安装 `auth.users` 触发器（用户画像在登录后按需创建）。

## Edge Function 约定

13 个函数各目录独立，**没有 `_shared/` 目录**：`explore-conversation`、`explore-daily-suggestion`、`explore-embed`、`explore-goal-analysis`、`explore-goal-chat`、`explore-goal-plan`、`explore-link-memories`、`explore-memory-search`、`explore-observations`、`explore-proactive`、`explore-profile`、`explore-timeline-summary`、`explore-weekly-report`。

每个 `index.ts` 都遵循同一套模板，新增函数请照抄现有实现，不要另立共享模块：从 `https://esm.sh/@supabase/supabase-js@2` 导入；模块级定义 `corsHeaders` 和 `jsonResponse` 辅助函数；处理 `OPTIONS` 预检；用 `Deno.env.get` 读取密钥；用请求头里的 Authorization 建 client 后调 `supabase.auth.getUser()` 鉴权；靠 RLS 保证只能访问本人数据。

`explore-proactive` 额外支持定时全量模式：`x-cron-secret` 请求头匹配 `CRON_SECRET` 时用 service role 遍历全部用户，否则按当前登录用户触发。

## 测试

- 模型输出解析有单测：`supabase/functions/explore-conversation/model-result.test.ts`（`node:test`，8 个用例）。改动 `model-result.ts` 的解析或归一化逻辑后必须跑 `npm test`。
- Flutter 测试在 `mobile/test/`，文件名以 `_test.dart` 结尾（如 `widget_test.dart`），覆盖首页空状态。
- Web 目前没有自动化测试，改动后最低要求是 `npm run typecheck`。

## 提交与 PR

`main` 分支目前还没有任何 commit（文件都处于暂存状态）。统一采用约定式提交：`feat:` / `fix:` / `docs:` / `chore:` 加短祈使句摘要。PR 保持聚焦，说明改了什么、如何手工验证，UI 改动附截图。
