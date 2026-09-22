# 探境 · App Store 上架清单

盘点日期：2026-09-21（第四轮更新：宣传文本 / 描述 / 关键词 / 审核备注定稿，见第九、十节）

## 一、当前状态

| 审核关注点 | 状态 |
| --- | --- |
| 删除账号（Guideline 5.1.1(v)） | ✅ 已实现并部署，端到端验证过（注册 → 写数据 → 删号 → 再登录失败） |
| 隐私政策 / 用户协议 / 支持页 | ✅ 已发布：`https://zhoubo416.github.io/explorer/legal/privacy.html`（协议 `/terms.html`、支持 `/index.html`） |
| 内容反馈 / 举报渠道 | ✅ 表已建（`explore_feedback`），写入 / 读回 / RLS 均已验证 |
| AI 内容安全底线 | ✅ 已写进三个模式的提示词并部署；陪伴模式有紧急求助提示 |
| 导出合规声明 | ✅ `Info.plist` 已加 `ITSAppUsesNonExemptEncryption = false` |
| 仅支持 iPhone | ✅ `TARGETED_DEVICE_FAMILY = "1"`，构建产物 `UIDeviceFamily = [1]` |
| App 图标 / App 内 Logo | ✅ 已换成无水印版（15 个尺寸 + App 内 logo）；1024 那张由 512 放大，有原图可换更好的 |
| 启动图 | ✅ 品牌圆角 logo（120pt，圆角比例与首页品牌标一致）+ `pageBg` 背景衔接首屏，构建校验无占位警告 |
| 审核用测试账号 | ❌ 需你在 App Store Connect 建（App 强制登录，**最常见的拒审点**） |
| 中国大陆备案 | 你来办（见第五节） |

## 二、本轮做完的改动

**客户端（`mobile/`）**

- 「我的」页新增入口卡：隐私政策 / 用户协议 / 意见反馈·内容举报 / 删除账号（`lib/main.dart` 的 `AccountActionsCard`）。
- 删除账号流程：`AlertDialog` 二次确认 → 调后端 → 清本地缓存 → 登出回登录页（`ExploreStore.deleteAccount`）。网络异常时提示「无法确认删除结果」，不谎报失败。
- 法务阅读面板：直接渲染随包发布的 markdown（`LegalSheet` + `assets/legal/*.md`），不引入新依赖。
- 反馈面板：可切换「意见反馈 / 内容举报」，空内容不发送（`FeedbackSheet`）。
- `AuthService.deleteAccount()` 把后端错误映射成中文提示；`CacheService.clear()` 在删号后清掉本机缓存。
- 测试：新增 4 个用例（入口齐全、二次确认可取消、法务正文可读、空反馈不发），共 35 个用例全过；`flutter analyze` 无问题。

**后端（`supabase/`）**

- 新增 `functions/explore-delete-account`：先用调用者 JWT 确认身份（只允许删自己），再用 service role 调 `auth.admin.deleteUser`；业务数据靠 `explore_` 表的外键 `on delete cascade` 级联清空，不逐表删。**已部署**（2026-09-19）。
- `schema.sql` 追加 `public.explore_feedback`（含 `category` 约束、RLS 本人可读写、索引）。

**发布（`docs/`）**

- `scripts/build-legal.mjs` 从 `mobile/assets/legal/*.md` 生成 `docs/legal/{privacy,terms,support,index}.html`（同一份 markdown 供 App 与网页共用，避免两处维护），加 `docs/.nojekyll`，用 GitHub Pages 发布（源：main 分支 `/docs`）。

## 三、你需要做的（按优先级）

### 1. 建审核测试账号并填进 App Store Connect

App 强制登录，审核员进不去是最常见的拒审。建一个**邮箱已确认、有真实数据**的账号（建议先跑几次对话、建一个目标、生成过画像与周报），填到「App 审核信息 → 演示账号」。字段清单位于 4.4。

### 2. App Store Connect 里建 App、填资料、提审

字段逐项见第四节，提交时的坑见第七节，备注口径见第九节。

### 3. 可选：换一版 1024 图标原图

现在用的是你给的无水印图（512×512），1024 那张是 2× 放大。若能导出 1024 原图，我几秒钟就能重切一遍，边缘更锐利。

### 4. 两处占位待替换（不阻塞提审）

- 隐私政策与用户协议里的联系方式目前用 GitHub Issues（`github.com/zhoubo416/explorer/issues`）——若有支持邮箱，告诉我，我替换并重新生成网页。
- 中国大陆备案若要求隐私政策挂在自有域名下，把 `docs/legal/*.html` 原样搬过去即可（页面自包含、无外链依赖）。

> 注：仓库里还有一张 `docs/ChatGPT Image 2026年8月8日 12_15_42.png`，Pages 发布后也是可公开访问的资源；若是设计稿源文件，建议挪出 `docs/` 或删掉。

## 四、提审要填的资料（App Store Connect 逐项）

### 4.1 App 信息（建 App 时填一次，之后改动需重新审核）

| 字段 | 建议填写 | 说明 |
| --- | --- | --- |
| 名称 | 探境 | 上限 30 字符，**全球唯一**；被占用就用备选「探境 · 个人成长 AI」 |
| 副标题 | 用对话记录成长的个人 Agent | 上限 30 字符，别堆关键词 |
| 主语言 | 简体中文 | |
| Bundle ID | `com.tanjing.exploreMobile` | 已固定，**建 App 后不能再改** |
| SKU | 自定（如 `tanjing-001`） | 仅内部使用，不对外展示 |
| 隐私政策 URL | `https://zhoubo416.github.io/explorer/legal/privacy.html` | **必填**，必须可访问 |
| App Store 分类 | 主：生活；次：健康健美 或 效率 | **不要选「医疗」** |
| 内容版权 | 不含第三方内容 | 图标与配图均为自有素材 |
| 年龄分级 | 按问卷如实填（见第七节） | |
| 许可协议 | 用 Apple 标准 EULA 即可 | |

### 4.2 版本信息（每个版本填一次）

| 字段 | 建议 | 说明 |
| --- | --- | --- |
| 宣传文本 | 定稿见 10.1（68 字符） | 上限 170 字符，可随时改、不用重新审核 |
| 描述 | 定稿见 10.2（735 字符） | 上限 4000 字符 |
| 关键词 | 定稿见 10.3（49 字符） | 上限 100 字符、逗号分隔，别重复 App 名称 |
| 支持 URL | `https://zhoubo416.github.io/explorer/legal/index.html` | **必填** |
| 营销 URL | 可留空 | |
| 版权 | `© 2026 <你的名字或主体>` | |
| 版本号 | `1.0.0` | 与 `pubspec.yaml` 一致；**每次上传构建号必须递增** |
| 截图 | iPhone 6.9"/6.7" 一组 3–5 张：首页 / 对话 / 目标详情 / 我的画像 / 周报详情 | iPhone-only，不需要 iPad 截图；尺寸以后台当前要求为准 |
| 构建版本 | 选 TestFlight 里处理完成的那个 build | |
| 更新说明 | 首个版本可写「首个版本」 | |

### 4.3 App 隐私（App Privacy）

| 数据类型 | 是否收集 | 关联到用户 | 用途 | 用于追踪 |
| --- | --- | --- | --- | --- |
| 联系信息 → 电子邮件地址 | 是 | 是 | App 功能、账号管理 | 否 |
| 用户内容 → 其他用户内容（对话、目标、记忆、成长事件、反馈与举报） | 是 | 是 | App 功能 | 否 |
| 标识符 → 用户 ID | 是 | 是 | App 功能、账号管理 | 否 |
| 设备 ID、使用数据、诊断、位置、健康与健身、财务信息、通讯录 | 否 | — | — | — |

三点注意：

1. **情绪状态标记**建议并入「用户内容」；若审核追问，说明它是用户输入文本的衍生标签、未接入 HealthKit、无医疗用途。拿不准时宁可多声明一项，也不要少声明。
2. **DeepSeek 与阿里云百炼是服务处理方**，不是广告/分析合作方，因此不勾「用于追踪」；但隐私政策必须披露（已披露 ✓）。
3. 填错通常只是「元数据被拒」（2.3.1），改正后重新提交即可，不是硬伤。

### 4.4 App 审核信息

| 字段 | 填什么 |
| --- | --- |
| 联系信息 | 名 / 姓 / 电话 / 邮箱（用能及时查收的邮箱，审核会通过它联系你） |
| 「App 需要登录」 | 是 |
| 演示账号 | 一个**邮箱已确认、有真实数据**的账号（建议提前跑几次对话、建一个目标、生成过画像与周报） |
| 备注 | 第九节已定稿，替换演示账号后整段复制（建议中英文各贴一段） |
| 附件 | 可选：录 30 秒操作视频，被拒时可直接用于申诉 |

### 4.5 价格与销售范围

- **价格**：免费
- **销售范围**：先只勾你准备好的地区（只上海外区就跳过备案；要上大陆区见第五节）
- **协议**：在「协议、税务和银行」里接受**免费 App 协议**，否则 App 无法上架

## 五、中国大陆上架（你自己办）

- **App 备案**：2024 年 3 月起强制，需 ICP 备案主体与备案号；上架大陆区时 App Store Connect 会要求提供备案信息，没有则大陆区不可用（不影响其他地区）。
- **生成式 AI 服务备案**：面向公众提供生成式 AI 对话，按《生成式人工智能服务管理暂行办法》需评估备案义务。
- **数据出境**：用户数据存于 Supabase `us-east-1`，涉个人信息出境需评估并告知同意（隐私政策已写明）。
- 未成年人保护 / 算法推荐相关表述按需补充。

> 以上只为提示，未做法律判断，具体以专业合规意见为准。只上架海外区可跳过本节。

## 六、提交流程

1. 备齐第四节资料，确认第五节事项（若上大陆区）
2. `flutter build ipa --release --dart-define-from-file=.env` → 产物在 `build/ios/ipa/`
3. 用 **Transporter** 上传，或 Xcode → Organizer → Distribute App；首次可能需要先在 Xcode 里登录开发者账号让其自动创建分发证书
4. App Store Connect → **TestFlight**：等构建处理完成（Processing，通常几分钟到半小时），先自己真机装一遍把主要流程走通——这一步能挡掉绝大多数低级问题
5. 选中构建版本，填完 4.1–4.5，提交审核
6. 审核期间保持邮箱与电话畅通；被拒时在 **Resolution Center** 回复

## 七、提交时的注意事项

1. **必须提供可用的审核账号**：强制登录的 App 不给账号或账号进不去，是最常见的拒审（Guideline 2.1）。演示账号要提前确认邮箱已确认、能登录、有内容。
2. **备注里指路删除账号**：「我的 → 删除账号」，并说明会一并清除目标、记忆、对话与反馈（5.1.1(v) 硬性要求）。
3. **别把产品说成心理健康服务**：定位为「个人成长陪伴」，备注里说明不做诊断、不提供医疗建议、有内容安全底线与举报入口。说成心理/医疗服务会触发 1.4.1 更严的审视。
4. **截图必须与实机一致**：不要用未上线的功能，不要出现其他 App 的界面，不要带水印（2.3.3 误导性元数据）。
5. **描述里不要写 Android 版、不要写"即将推出"的功能**（2.3.1 隐藏功能）。
6. **年龄分级如实填**：问卷里有「用户生成内容 / AI 生成内容 / 不受限网络访问」等项，照实回答。
7. **每次上传构建号必须递增**：改 `pubspec.yaml` 的 `version: 1.0.0+2` 即可，重复的构建号会被拒收。
8. **出口合规**：`Info.plist` 已声明 `ITSAppUsesNonExemptEncryption = false`，上传后一般不再逐次询问。
9. **免费 App 也要接受免费协议**，否则构建上传了也无法提审。
10. **被拒怎么办**：先在 Resolution Center 礼貌询问具体条款；能改的直接改并回复说明；争议较大时补一段录屏。首版被拒 1–2 次很常见，不影响后续上架。
11. **审核时长**：首版通常 24–72 小时。加急审核（Expedited Review）只在紧急情况用，滥用会被拒。
12. **提审后仍可改的**：宣传文本、描述、关键词、截图随时可改（改完即生效，不需重新审核）；App 名称、Bundle ID、隐私政策 URL 改动会触发重新审核。

## 八、已知问题

1. ~~**退出登录不清内存中的业务数据**~~（已修，2026-09-19）：`ExploreStore.clearUserData()` 会在退出登录、删除账号、以及每次 `loadRemoteData()` 开头清空内存中的目标 / 记忆 / 对话 / 画像等；`currentGoal` 改为可空，目标详情页等按空态渲染。顺带修好了「换账号后新用户的本地缓存不生效」（此前内存非空会让 `_applyCachedData` 直接跳过）。
2. ~~**AI 内容安全只有举报入口**~~（已修，2026-09-19）：`explore-conversation` 三种模式与 `explore-goal-chat` 的提示词都写入了安全底线（不做诊断与医疗建议、不鼓励极端行为、识别到自伤或伤人倾向时引导联系专业帮助、紧急情况建议拨打当地急救电话），并已部署；陪伴模式在应用内显示紧急求助提示。测试见 `supabase/functions/explore-conversation/prompt.test.ts` 与 `mobile/test/layout_test.dart` 的「低情绪模式显示紧急求助提示」。

## 九、审核备注（定稿）

提审时在 App Review Information 的 Notes 里整段复制，先把 `<邮箱>` / `<密码>` 换成 4.4 的演示账号。审核团队大多在美国，销售范围含英语区时建议中英文各贴一段。

### 中文版

> 探境是一款个人成长记录与陪伴应用，不是医疗或心理服务。核心功能：与 AI 对话梳理目标、自动保存成长记忆、生成每周成长周报与个人画像。
>
> 审核账号：<邮箱> / <密码>（邮箱已确认，可直接登录；账号内已预置目标、记忆、对话、画像与周报，登录后各页面均有内容）。底部导航依次为：首页（今日观察与建议）→ 成长（目标 / 记忆）→ 对话 → 我的（画像、周报、账号操作）。体验路径：在对话页发送任意一句话，即可看到 AI 流式回复与自动保存的记忆（回复为流式生成，等待数秒属正常现象）；「成长 → 创建目标」可与 AI 共创目标，并自动拆出阶段与行动项；「我的 → 成长周报」可查看每周复盘。
>
> 新注册账号需完成邮箱确认后才能登录；演示账号已确认，无需再收验证邮件。
>
> 内容安全：AI 回复的生成规则中已包含安全底线——不做诊断、不提供医疗或心理治疗建议、不鼓励自伤或伤害他人；当用户表达自伤倾向时，AI 会明确表达关心并建议联系专业帮助；「成长陪伴」模式在界面固定显示紧急求助提示。应用内「我的 → 意见反馈 / 内容举报」可随时举报不当回复。
>
> 账号删除：我的 → 删除账号，二次确认后账号与全部数据（目标、记忆、对话、反馈）立即删除、不可恢复，该账号无法再登录。
>
> 隐私：隐私政策 https://zhoubo416.github.io/explorer/legal/privacy.html ，用户协议 https://zhoubo416.github.io/explorer/legal/terms.html ，支持页 https://zhoubo416.github.io/explorer/legal/index.html 。数据存储于 Supabase（美国东部）；对话内容经 DeepSeek 生成回复、记忆文本经阿里云百炼向量化，均已在隐私政策中披露。应用不收集广告标识符，不进行跨应用追踪。

### 英文版（销售范围含英语区时一并贴上）

> Explore (探境) is a personal growth journaling and companion app. It is NOT a medical or psychological service. Core features: chat with AI to clarify goals, automatically save growth memories from conversations, and generate weekly growth reports and a personal profile.
>
> Demo account: <email> / <password> (email already confirmed — sign in directly; the account is pre-populated with goals, memories, conversations, a profile and a weekly report, so every page has content). Bottom navigation: Home (daily observation & suggestions) → Growth (Goals / Memories) → Chat → Me (profile, weekly reports, account actions). Suggested path: send any message in Chat to see a streamed AI reply and automatic memory saving (replies are streamed and take a few seconds — this is normal); in Growth → Create Goal, co-create a goal with AI that is automatically broken down into stages and action items; Me → Weekly Reports shows the weekly review.
>
> New registrations require email confirmation before signing in; the demo account is already confirmed — no verification email needed.
>
> Content safety: AI generation rules include a hard safety baseline — no diagnosis, no medical or psychological treatment advice, no encouragement of self-harm or harming others. When a user expresses self-harm intent, the AI expresses care and directs them to professional help. The low-mood companion mode permanently displays an emergency-help notice. Users can report inappropriate AI replies via Me → Feedback / Content Report.
>
> Account deletion: Me → Delete Account. After a confirmation dialog, the account and ALL data (goals, memories, conversations, feedback) are deleted immediately and cannot be recovered; the account can no longer sign in.
>
> Privacy: Privacy Policy https://zhoubo416.github.io/explorer/legal/privacy.html | Terms https://zhoubo416.github.io/explorer/legal/terms.html | Support https://zhoubo416.github.io/explorer/legal/index.html . Data is stored on Supabase (US East); conversation content is processed by DeepSeek to generate replies, and memory text is embedded by Alibaba Cloud Bailian — both are disclosed in the privacy policy. The app collects no advertising identifiers and performs no cross-app tracking.

## 十、商店文案定稿（直接复制进 App Store Connect）

### 10.1 宣传文本（Promotional Text，上限 170 字符，本文 68 字符；可随时修改，不需重新审核）

一个有长期记忆的 AI 成长伙伴：想做的事聊着聊着就拆成下一步行动，重要的决定与感受自动存为成长记忆；每周一份成长周报，画像越用越懂你。

### 10.2 描述（Description，上限 4000 字符，本文 735 字符）

探境是一个基于长期记忆的 AI 个人成长伙伴。你只管和它聊，它负责记住、整理、提醒和陪伴——把散落在日常里的决定、进展与感受，变成清晰可见的成长轨迹。

【聊着聊着，事情就清楚了】
· 三种对话模式：日常交流、成长陪伴、目标共创，按当下需要切换
· 重要的决定、进展、情绪与思考会被自动识别并存为成长记忆，闲聊不会污染记录
· 它带着记忆回应你：结合你的目标阶段、过往记忆与个人画像，而不是每次从零开始

【目标不只是许愿，而是拆成下一步】
· 和 AI 聊出想做的事，自动拆解为多个阶段与可勾选的行动项
· 勾选行动项，或在对话里汇报进展，目标阶段会自动推进
· 完整的目标状态管理：探索、进行、暂停、受阻、完成、归档
· 想放弃的时候，它会陪你分三层聊清楚：发生了什么、已有的成果、放弃的是方向还是方法，然后给出判断，而不是替你做决定

【成长看得见】
· 首页每天有 AI 今日观察与下一步建议，跟随你的当前主目标
· 每周一份成长周报：本周得分、洞察与建议，历史每一周都可回看
· 个人画像：从你的真实记忆中提炼性格、价值观、兴趣、优势与待提升项，越用越懂你
· 记忆时间线与阶段总结，回望走过的每一段路

【一个会主动关心你的伙伴】
目标停滞时提醒你，情绪低落时陪伴你，取得突破时祝贺你，也会在你安静许久之后邀请一次深度反思。

【你的数据属于你】
· 数据仅自己可见，不同账号完全隔离
· 「我的 → 删除账号」可随时彻底删除账号与全部数据
· 「我的 → 意见反馈 / 内容举报」可随时反馈问题或举报不当内容

【重要说明】
探境是个人成长记录与陪伴工具，不提供医疗诊断或心理治疗服务。如果你正处于情绪困扰中，请及时寻求专业帮助，应用内也提供了求助指引。

### 10.3 关键词（Keywords，上限 100 字符，本文 49 字符）

个人成长,目标管理,AI陪伴,成长记录,周报,记忆,复盘,自我管理,情绪记录,习惯养成,自律,规划

说明：App 搜索只索引「名称 + 副标题 + 关键词」三处，描述不参与索引。副标题「用对话记录成长的个人 Agent」已覆盖「对话 / 记录 / 成长 / 个人」，这些单字不再占用关键词名额；「个人成长」「成长记录」虽与副标题部分重合，但作为整词是品类核心搜索词，宁可浪费几个字符也不能缺席。
