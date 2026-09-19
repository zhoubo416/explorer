# 探境 · App Store 上架清单

盘点日期：2026-09-19（第二轮更新：删除账号、法务页、反馈渠道、iOS 配置已补齐）

## 一、当前状态

| 审核关注点 | 状态 |
| --- | --- |
| 删除账号（Guideline 5.1.1(v)） | ✅ 已实现并部署（见第三节） |
| 隐私政策 / 用户协议 / 支持页 | ✅ 已写好并发布（URL 见第三节） |
| 内容反馈 / 举报渠道 | ⚠️ 代码已就绪，**等你跑一次建表 SQL** 才生效 |
| 导出合规声明 | ✅ `Info.plist` 已加 `ITSAppUsesNonExemptEncryption = false` |
| 仅支持 iPhone（You 已定：iPad 先不支持） | ✅ `TARGETED_DEVICE_FAMILY = "1"` |
| App 图标 / App 内 Logo | ❌ **仍带「豆包」水印，等你给无水印原图** |
| 审核用测试账号 | ❌ 需你在 App Store Connect 建（App 强制登录） |
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

## 三、需要你做的（按优先级）

### 1. 跑一次建表 SQL（1 分钟，否则反馈功能报错）

`explore_feedback` 表**尚未创建**（已验证：接口返回 `PGRST205 Could not find the table`）。把 `supabase/schema.sql` 末尾那段「2026-09-19 意见反馈与内容举报」整段贴进 Dashboard 的 SQL Editor 执行即可（幂等，可重复执行）。

### 2. 提供无水印图标原图

1024×1024、无 alpha、不预切圆角。给我之后我负责切 15 个尺寸并替换图标与 `mobile/assets/logo.png`。

> 注：仓库里还躺着一张 `docs/ChatGPT Image 2026年8月8日 12_15_42.png`，Pages 发布后也会变成可访问的网页资源；如果它是设计稿源文件，建议挪出 `docs/` 或删掉。

### 3. App Store Connect 里建 App 与审核账号

见第四节。

### 4. 两处占位待替换（不阻塞提审，但建议换掉）

- 隐私政策与用户协议里的联系方式目前用 GitHub Issues（`github.com/zhoubo416/explorer/issues`）——若有支持邮箱，告诉我，我替换并重新生成网页。
- 中国大陆备案若要求隐私政策挂在自有域名下，把 `docs/legal/*.html` 原样搬过去即可（页面自包含、无外链依赖）。

## 四、App Store Connect 要准备的

- **新建 App**：名称「探境」（全球唯一，可能被占用 → 备选如「探境 · 个人成长 AI」）、主语言简体中文、SKU、Bundle ID 选 `com.tanjing.exploreMobile`
- **分类**：建议「生活」或「健康健美」
- **年龄分级问卷**：会问 AI 生成内容、用户生成内容、不受限网络访问等，如实填
- **隐私营养标签（App Privacy）**：声明收集邮箱、用户内容（对话/记忆）、用户标识；用途含 App 功能与 AI 处理；声明第三方共享（DeepSeek 对话、阿里云百炼向量化）；数据存于境外（Supabase us-east-1）
- **截图**：iPhone 6.9"/6.7" 至少一组（尺寸以后台当前要求为准；现在是 iPhone-only，不需要 iPad 截图）
- **文案**：描述、关键词、宣传文本、更新说明
- **审核信息**：填测试账号（邮箱已确认、有真实数据），备注里写明体验路径与「删除账号在『我的』页」、AI 内容安全做法（安全约束 + 举报入口）
- **协议 / 税务 / 银行**：免费 App 也需接受免费 App 协议

## 五、中国大陆上架（你自己办）

- **App 备案**：2024 年 3 月起强制，需 ICP 备案主体与备案号，否则大陆区无法上架。
- **生成式 AI 服务备案**：面向公众提供生成式 AI 对话，按《生成式人工智能服务管理暂行办法》需评估备案义务。
- **数据出境**：用户数据存于 Supabase `us-east-1`，涉个人信息出境需评估并告知同意（隐私政策已写明）。
- 未成年人保护 / 算法推荐相关表述按需补充。

> 以上只为提示，未做法律判断，具体以专业合规意见为准。只上架海外区可跳过本节。

## 六、提审流程

1. 跑 SQL、换图标、建审核账号
2. `flutter build ipa --release --dart-define-from-file=.env`
3. Transporter 或 Xcode Organizer 上传
4. TestFlight 自测：登录、对话、目标共创、删除账号、反馈
5. 填元数据与审核信息后提审

## 七、已知问题

1. ~~**退出登录不清内存中的业务数据**~~（已修，2026-09-19）：`ExploreStore.clearUserData()` 会在退出登录、删除账号、以及每次 `loadRemoteData()` 开头清空内存中的目标 / 记忆 / 对话 / 画像等；`currentGoal` 改为可空，目标详情页等按空态渲染。顺带修好了「换账号后新用户的本地缓存不生效」（此前内存非空会让 `_applyCachedData` 直接跳过）。
2. **AI 内容安全**：目前只有举报入口，没有自动内容过滤与人工复审流程，提审备注里要讲清现有做法。
