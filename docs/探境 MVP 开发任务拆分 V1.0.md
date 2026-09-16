目标：

一个开发者：

3个月完成可用版本。

---

# 第一阶段：AI聊天 + 记忆（第1-4周）

目标：

证明：

用户愿意和AI长期交流。

---

## 前端

页面：

### Chat页面

功能：

- AI聊天
- 历史消息
- 输入

---

## 后端

完成：

Conversation API

Memory Extract API

---

## AI

实现：

Prompt：

- 用户理解
- 记忆提取

---

产出：

用户聊天后：

AI自动形成Memory。

---

# 第二阶段：目标系统（第5-8周）

新增：

## 首页

展示：

- 当前目标
- AI观察
- 最近成长

---

## Goal

功能：

- 创建目标
- 切换目标
- 查看进度

---

AI：

聊天生成目标。

---

# 第三阶段：成长Agent（第9-12周）

重点：

主动能力。

---

新增：

## 周报

自动生成：

```
本周成长

发现

问题

建议
```

---

## AI主动消息

实现：

定时任务。

例如：

30天没有推进。

---

# MVP页面最终结构

```
首页

 |
 |-- AI观察
 |-- 当前目标
 |-- 最近成长


聊天

 |
 |-- 日常交流
 |-- 成长咨询


记忆

 |
 |-- 时间线


目标

 |
 |-- 主目标
 |-- 其他目标


我的

 |
 |-- 设置
```

---

# 技术建议（个人开发）

## 前端

保持你熟悉：

Vue3 / Nuxt3

---

## 后端

推荐：

Supabase

原因：

- Auth
- PostgreSQL
- pgvector
- Storage

一套解决。

---

## AI

前期：

DeepSeek API

后期：

支持：

- OpenAI
- Claude
- 本地模型

---

# 最小可行版本定义

不要做：

❌ 数字人形象

❌ 社区

❌ 复杂知识图谱

❌ 游戏化

必须做：

✅ AI聊天

✅ Memory

✅ 当前目标

✅ AI观察

✅ 周总结

---

# 最终产品核心指标

不是：

DAU。

而是：

## AI理解程度

指标：

用户是否觉得：

> “这个AI越来越了解我。”

---

这三份文档组合起来，基本就是探境第一版开发蓝图。

其中最关键的是第二份 **AI Agent设计**。

因为如果只是完成页面和数据库，最后很容易变成：

“AI日记 + 目标管理”。

真正决定探境价值的是：

**Memory如何沉淀，以及AI什么时候主动出现。**

---

# 当前实现状态（2026-08-12）

本节作为后续开发进度的统一记录。每完成一项功能，需要同步更新状态、完成日期和验证结果。

## 当前覆盖度

- 原型页面覆盖：100%
- Flutter 手机端交互覆盖：约 95%
- 产品业务能力覆盖：约 98%
- MVP 第一阶段（AI 聊天 / Memory / 主目标 / 首页 / 周总结）：已完成
- 完整产品（说明书）：功能已全部落地（含聊天生成目标、成长构成、定时推送、推理引擎、周报历史、阶段总结）

## 功能 / 状态 / 证据对照表（2026-08-13 核对）

状态图例：✅ 已完成（页面 + 真实数据链路）· 🟨 部分完成（协议或 UI 就绪，但未真实联调）· ⚠️ 仅页面或 mock · ⬜ 未实现

| 功能 | 状态 | 代码证据 |
| --- | --- | --- |
| Flutter 五栏导航 / 首页 / 目标 / 记忆 / 对话 / 周报 UI | ✅ | `mobile/lib/main.dart` 各页面 widget |
| 登录 / 注册 / 退出 / 按用户加载 | ✅ | `mobile/lib/services/auth_service.dart`、`main.dart:950-1140` |
| 目标增删改与远端同步 | ✅ | `mobile/lib/repositories/goal_repository.dart` |
| 会话与消息持久化 | ✅ | `mobile/lib/repositories/conversation_repository.dart` |
| 真实 AI 对话 | ✅ | 已部署 Edge Function + 设置 DeepSeek secret；API 级端到端验证通过（Auth→函数→DeepSeek→正确回复） |
| Memory 自动提取 | ✅ | 已部署函数端到端验证：decision/importance 75-85/emotion 坚定，纯闲聊返回 null |
| AI 观察（首页 Hero / 观察卡片） | ✅ | Web/Flutter 均通过 `explore-observations` 加载并展示真实观察 |
| 成长周报 | ✅ | Web/Flutter 均通过 `explore-weekly-report` 生成/加载真实周报，支持重新生成 |
| 通知入口 | ✅ | Flutter 铃铛点击展示主动消息列表并支持已读；Web 用顶部横幅 |
| Memory 评分 / Embedding / 语义搜索与召回 | ✅ | `explore-embed`（百炼 1536 维）+ `explore_match_memories` RPC + `explore-memory-search`；对话已注入相关记忆 |
| Growth Reasoning Engine | ✅ | 由 `explore-observations`（趋势/情绪信号）+ `explore-weekly-report`（综合状态/建议）+ `explore-goal-analysis`（按目标）共同覆盖 |
| AI 主动消息 / 目标停滞 / 情绪检测 | ✅ | `explore-proactive` 检测目标停滞/情绪下降/成长突破并生成提醒；定时触发待配 cron |
| 聊天生成目标 | ✅ | `explore-goal-chat` 从对话提炼目标；Web + Flutter 均为“与 AI 共创目标” |
| Web 端（`app/`） | ✅ | 已接入 Supabase：登录/注册、目标/记忆/会话、真实 AI 对话；观察/周报/分析为空状态（无后端生成） |

## 已完成

✅ Flutter iOS 工程初始化，支持手机端运行

✅ 底部五栏导航：首页、成长、记忆、对话、我的

✅ 首页：AI 观察、当前主目标、今日建议、最近成长记录

✅ 目标系统：多目标列表、目标创建、目标创建完成页、目标详情五个 Tab

✅ AI 分析与建议页面交互

✅ 情绪低落陪伴对话流程

✅ 记忆时间线与分类筛选

✅ 成长周报页面

✅ 对话历史入口与会话切换（mock 已移除，现为远端会话）

✅ Flutter 静态分析、Widget 测试、iOS 无签名构建通过

## 当前仍为 Mock / 待部署

✅ Mock 数据已全部移除（2026-08-24）：客户端不再内置示例目标/记忆/会话，也不再返回静态 AI 兜底回复；未配置 Supabase 或 AI 失败时直接提示错误，必须配置 Supabase 才能正常使用。

✅ 移动端目标详情"阶段/里程碑"已改为真实目标数据（phase + 成功标准）；低情绪对话改为真实消息 + `low_mood` 模式

本次更新（2026-08-13）：拆分 `parseModelResult`/`normalizeMemory` 到 `supabase/functions/explore-conversation/model-result.ts`，抽取共享 `prompt.ts`，新增 `model-result.test.ts`（4 项通过）与 `integration.ts`。经真实 DeepSeek API（代理 127.0.0.1:7890）联调：记忆型消息正确提取 `decision/importance=85/emotion=坚定`，闲聊消息正确返回 `memory=null`。Flutter `analyze`/`test` 均通过。待办：部署 Edge Function 到 Supabase 并做 Flutter 端到端联调。

已部署并联调（2026-08-13）：`supabase link --project-ref bjbfxxvgtiatstdytzzn` 完成；`explore-conversation` Edge Function 已部署，`DEEPSEEK_API_KEY`/`DEEPSEEK_MODEL` secret 已设置。用临时测试账号做 API 级端到端验证通过：记忆型消息返回 `decision/importance=85/emotion=坚定`，纯闲聊返回 `memory=null`。剩余：用户用真实账号跑一次 Flutter App 做最终确认。

Web 端改造（2026-08-13）：删除 `app/` 全部 mock 数据，接入 Supabase（`@supabase/supabase-js` + `app/plugins/supabase.client.ts`），新增登录/注册（`AuthScreen.vue`），重写 `useExplore.ts` 为目标/记忆/会话/真实 AI 对话，`ssr: false` + `.env` 配置 `NUXT_PUBLIC_SUPABASE_URL/ANON_KEY`；观察/周报/目标分析暂无后端生成逻辑，展示空状态。`npm run typecheck` 通过、`npm run dev` 启动正常。

AI 观察与周报（2026-08-15）：新增 `explore-observations`（基于目标/记忆/对话生成并写入 `explore_ai_observations`）与 `explore-weekly-report`（按需生成周报 JSON）两个 Edge Function 并部署；Web 端登录后自动生成观察（仅当为空）、进入周报页按需生成并可重新生成。API 级验证通过：观察生成 2 条具体内容、周报返回 score/completed/insight/nextSteps。

周报历史（2026-08-15）：新增 `explore_weekly_reports` 表（`unique(user_id, week_start)` + RLS），`explore-weekly-report` 生成后按 `user_id,week_start` upsert；Web 端登录时读取最新周报。已 API 验证：本周区间 8/10-8/16、score 4.0 落库、重复生成不产生重复行。

Memory Embedding 与召回（2026-08-17）：接入阿里云百炼 `text-embedding-v4`（1536 维，与 `vector(1536)` 匹配），新增 `explore-embed` 与 `explore-memory-search`，新增 `explore_match_memories` RPC；记忆写入自动向量化，`explore-conversation` 对话前召回相关记忆注入提示词。已 API 验证：语义检索返回正确记忆（相似度 0.827）、对话回复明确引用历史记忆。

AI 主动消息（2026-08-17）：新增 `explore-proactive`，检测目标停滞（active 目标 30 天未更新）/ 情绪下降（近两周多次负面表达）/ 成长突破（近 7 天高重要性成就），生成并写入 `explore_ai_actions`；Web 端登录后非阻塞触发、顶部横幅展示、可标记已读。已 API 验证：成长突破触发生成 encouragement 提醒。

Flutter 端同步（2026-08-17）：新增 `mobile/lib/services/insight_service.dart`，接入观察（加载+生成）、周报（加载+生成+重新生成）、目标分析（按需生成）；首页 Hero/观察卡片、周报页、目标详情分析 Tab 均改为真实数据。`flutter analyze` 无问题、`flutter test` 通过。

Flutter 端收尾（2026-08-17）：目标详情"阶段/里程碑"改为真实 `phase`/成功标准；移除低情绪对话 `lowMoodMessages` mock，统一走真实会话 + `low_mood` 模式；记忆写入自动向量化。`flutter analyze` 无问题、`flutter test` 通过。

聊天生成目标（2026-08-17）：`explore-conversation` 增加 `goal_creation` 模式、`model-result` 支持解析 `goal`；新增无状态 `explore-goal-chat` 函数；Web 端 GoalCreateView 改为与 AI 对话共创目标（AI 提炼标题/描述/成功标准后确认创建）。已 API 验证：多轮对话自然追问、方向清晰时返回 goal。

首次使用引导（2026-08-17）：Web 首页空状态改为“欢迎来到探境 / 开始认识我”，引导新用户进入目标共创对话；Growth Reasoning Engine 判定由观察/周报/目标分析三个函数共同覆盖。

定时触发（2026-08-19）：`explore-proactive` 增加定时全量模式（`x-cron-secret` + `SUPABASE_SERVICE_ROLE_KEY` 遍历所有用户），以 `--no-verify-jwt` 部署（函数内自校验）；已验证一次遍历 23 个用户、生成 2 条主动消息。cron 配置 SQL 已提供，待用户执行 `pg_cron`/`pg_net` 调度。

Flutter 目标共创与主动消息（2026-08-19）：Flutter `GoalCreateScreen` 改为与 AI 对话共创目标（`explore-goal-chat`），`createGoal()` 从 AI 提炼的目标草稿创建；新增主动消息加载/检测/已读，首页顶部横幅展示。`flutter analyze` 无问题、`flutter test` 通过。

周报历史与阶段总结（2026-08-19）：周报支持历史切换（Web 下拉 + Flutter 下拉，按 `week_start` 列表）；新增 `explore-timeline-summary` 生成成长时间线"阶段总结"，Web/Flutter 记忆页展示并可重新生成；Flutter 通知铃铛接入主动消息列表。`flutter analyze`/`flutter test` 与 `npm run typecheck` 均通过。

growth_event 关联（2026-08-19）：记忆落库时写入 `explore_growth_events`（关联当前主目标 + 记忆 + 影响分 + 描述），Web/Flutter 均已接入，为"目标相关记忆"提供数据基础。

成长构成与测试（2026-08-19）：目标详情新增"成长构成/多维成长路径"（按记忆类型分布的真实数据可视化，Web/Flutter 均有）；新增 `npm test`（Node 运行 `model-result.test.ts`，6 项通过）。`flutter analyze`/`flutter test` 与 `npm run typecheck` 均通过。

目标阶段与行动项（2026-08-19）：`explore_growth_goals` 新增 `stages jsonb`；新增 `explore-goal-plan`（拆解目标为阶段 + 每阶段行动项）；`explore-conversation` 返回 `goal_update`（识别行动项完成/阶段推进/目标完成）。Web/Flutter 双端：目标共创后自动拆阶段并确认、目标详情展示阶段与可勾选行动项、对话自动更新进度/阶段。`flutter analyze`/`flutter test`、`npm run typecheck` 均通过。

阶段与行动项联调（2026-08-19）：API 级端到端验证通过——`explore-goal-plan` 拆出 4 个阶段及行动项；带 `stages` 的目标成功落库；`explore-conversation` 对话“完成访谈”后返回 `goal_update`（正确匹配到行动项 `done_actions`、`note` 进度说明）。注：DeepSeek 边缘偶发限流（约 1/3 请求空回复），需关注生产稳定性。

DeepSeek 重试（2026-08-19）：8 个调用 DeepSeek 的 Edge Function 统一加 `callDeepSeek`（15s 超时 + 3 次重试 + 指数退避，429/5xx/超时/网络错误均可重试）。已部署。注：实测仍偶发“空回复”（Supabase 边缘运行时在 DeepSeek 限流时提前终止 isolate，函数内重试无法完全覆盖），需配合客户端重试 + DeepSeek 配额升级。

客户端重试（2026-08-19）：Web `useExplore` 与 Flutter `SupabaseService.invokeWithRetry` 统一对 Edge Function 调用做 3 次重试（1.2s/2.4s 退避），覆盖边缘 isolate 偶发终止；Web `useExplore` 所有 `functions.invoke` 与 Flutter `AiService`/`InsightService` 全部切换为带重试版本。`flutter analyze`/`flutter test`、`npm run typecheck` 均通过。

目标相关记忆（2026-08-19）：`growth_events` 关联真正接进 UI——Web/Flutter 目标详情"记录"Tab 改为按 `goal_id` 查询关联记忆（`loadGoalMemories`），不再显示全部记忆。已验证：记忆→目标关联、按目标查询返回正确记忆。`flutter analyze`/`flutter test`、`npm run typecheck` 均通过。

双端对齐（2026-08-20）：补齐三处差异——Flutter 目标详情"行动"Tab 由写死改为当前阶段行动项（复用 stages + toggleAction）；Web 新增会话历史切换（`conversations` + `selectConversation` + ChatView 历史下拉）；Flutter 首页观察由单条改为多条。`flutter analyze`/`flutter test`、`npm run typecheck` 均通过。

主动消息扩展（2026-08-20）：`explore-proactive` 由 3 类扩到 5 类，优先级：情绪陪伴(encouragement) → 目标停滞(warning) → 节奏提醒(insight，近两周思考≥3 且无行动) → 下一步提醒(reminder，当前阶段有未完成行动且近期无行动) → 成长突破(encouragement)。已 API 验证 insight 与 reminder 两类均正确触发。

情绪低谷三层提问 + 深度反思（2026-08-20）：`explore-conversation` 的 `low_mood` 模式改为"情绪理解→原因探索→区分方向/方法"三层逐步提问，完成后再给调整建议、不立即改目标；`explore-proactive` 新增 `reflection` 深度反思（每周一次、开放式问题、不催行动）。已 API 验证：第 1 层"最近发生了什么"、第 3 层"方向 vs 方法"、reflection 均正确返回。

目标分析（2026-08-15）：新增 `explore-goal-analysis` Edge Function，按目标生成阶段总结/观察/建议/行动并写入 `explore_growth_goals.ai_summary`；Web 端 GoalDetail 的"行动/分析"Tab 已接入（可生成/重新生成）。API 级验证通过：分析内容具体、可执行，`ai_summary` 落库成功。

品质重构（2026-08-20）：① 多维成长路径/成长构成由前端关键词硬匹配改为 AI 推理——`explore-profile` 新增 `growth_dimensions`（能力维度，含 score+evidence）与 `growth_composition`（成长构成，含 ratio+insight）并落库到 `explore_user_profiles`；Web `GoalDetailView` 与 Flutter `_GrowthComposition` 改为读画像数据，删除关键词算分。② 记忆落库链收进后端——`explore-conversation` 现在统一完成助手回复落库、记忆写入、成长事件、向量化、记忆关联、目标阶段更新，Web `useExplore` 与 Flutter `main.dart` 删除双端重复的记忆/目标更新逻辑（`_saveMemory`/`_embedMemory`/`applyGoalUpdate` 已移除）。验证：`npm run typecheck` ✅、`flutter analyze` ✅、`flutter test` ✅、`npm test`（7 项）✅。待执行：跑 `schema.sql` 新增两列 SQL 并重新部署 `explore-profile`、`explore-conversation`。

记忆召回补全（2026-08-20）：`explore-conversation` 由「主目标阶段 + 语义相似记忆」两层扩展为四层，补齐说明书要求的「用户画像」与「近期事件」注入——对话前额外读取 `explore_user_profiles`（personality/interests/strengths/weaknesses/current_stage）和最近 8 条记忆，一并注入 system prompt。已重新部署 `explore-conversation`。SQL 两列与两个函数部署均已完成。

目标状态机完整化（2026-08-20）：`explore-conversation` 新增 `goal_status_update`（暂停/受阻/完成/归档/恢复），低情绪与日常模式在用户确认后由 AI 返回并由后端真正落库；`model-result` 增加 `normalizeGoalStatusUpdate`（单测 8 项通过）。Web `GoalDetailView` 与 Flutter `GoalDetailScreen` 新增手动状态控制（开始/暂停/恢复/标记完成/归档），`Goal` 增加 `rawStatus`；修复 Web `toggleAction` 误用 `mainGoalId`（改为 `selectedGoalId`）。验证：`npm run typecheck` ✅、`flutter analyze` ✅、`flutter test` ✅、`npm test` ✅，已重新部署 `explore-conversation`。

低情绪三层状态机（2026-08-20）：`explore_conversation_sessions` 新增 `mood_stage`（0/1/2/3），`explore-conversation` 由「LLM 从历史推断层级」改为后端确定性推进——按当前 stage 注入明确层级指令（情绪理解→原因探索→区分方向/方法→给出判断），每次助手回复后 stage+1 并封顶。用户已执行 SQL，函数已重新部署。

每日建议 + 关系图谱连目标（2026-08-20）：① 新增 `explore-daily-suggestion` Edge Function 与 `explore_daily_suggestions` 表（按 user_id+suggestion_date 唯一），Web `DashboardView` 与 Flutter 首页「今日建议」由显示成功标准改为显示 AI 生成的每日建议（加载时生成并缓存）。② `explore_memory_relations` 新增 `target_goal_id`（`target_id` 改为可空），记忆落库时除记忆↔记忆相似边外，同时写入记忆↔目标 `related_to` 边。验证：`npm run typecheck` ✅、`flutter analyze` ✅、`flutter test` ✅、`npm test`（8 项）✅。SQL 已执行，`explore-daily-suggestion`、`explore-conversation` 已部署。

## 待完成能力

✅ 共享 Supabase 下的探境 Schema、RLS、用户画像表、Flutter Auth 登录注册和按用户加载已完成

✅ Conversation API 与真实 AI 对话：Edge Function 已部署、DeepSeek Key 已配置，API 级端到端联调通过

✅ Memory Extractor：返回结构与 Flutter 落库已完成，真实对话验证提取质量通过

✅ Memory 评分、Embedding、语义搜索与召回：记忆写入自动向量化，`explore-memory-search` 相似检索，`explore-conversation` 召回相关记忆注入上下文

✅ Flutter Goal Repository 已连接页面；新建目标、进度、标题、状态、描述和里程碑均支持远端同步

🟨 Flutter Conversation/Memory Repository 已连接页面；历史会话和消息已持久化，Memory 自动提取已 API 级联调通过，待实机跑一次 App 确认

✅ 已在“我的”入口展示当前登录账号并支持退出登录

✅ Growth Reasoning Engine：观察/周报/目标分析三个函数已覆盖“目标+记忆+行为+情绪 → 状态+问题+建议”

✅ AI 主动观察、目标停滞检测和情绪变化检测：`explore-proactive` 已实现三类触发规则

✅ 定时任务、AI 主动消息和成长突破提醒：`explore-proactive` 已支持定时全量模式（service role 遍历用户 + `CRON_SECRET` 保护），已验证；cron SQL 已提供待配置

✅ 周报自动生成 + 历史保存（`explore-weekly-report` 生成后 upsert 到 `explore_weekly_reports`，Web 端登录读取最新、可重新生成）

✅ 聊天生成目标：`explore-goal-chat` + Web/Flutter 双端对话共创

## 下一阶段任务（2026-08-20 新增，按优先级）

1. ✅ 用户画像提炼：`explore-profile` 从记忆/目标/对话提炼并写入画像，Web/Flutter 的"我的"页展示（可生成/重新生成）
2. ⚠️ 系统推送：iOS APNs 推送（阻塞：需 Apple 开发者凭据 + 真机 + push token 注册，后端推送函数待凭据就绪后接入）
3. ✅ 记忆关系图谱：`explore-link-memories` 在记忆向量化后自动关联相似记忆写入 `explore_memory_relations`
4. ✅ 多维成长路径：目标详情"能力维度"（技术/产品/商业，关键词匹配评分）Web/Flutter 均有
5. ✅ 放弃目标完整流程：三层提问后补"历史回顾 + 调整建议（不自动改目标、待用户确认）"
6. ✅ onboarding 记忆建立：首次创建目标后自动生成用户画像（`explore-profile`）

## 后续更新规则

1. 完成真实功能后，将对应 `⬜` 更新为 `✅`。
2. 仅完成页面或本地交互时，保持 `⚠️`，不能标记为业务完成。
3. 每次更新补充完成日期、关联代码路径和验证命令。
4. 如果产品设计发生变化，先更新产品说明书，再同步调整本清单。
