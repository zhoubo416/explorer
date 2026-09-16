# 1. 数据库设计原则

探境的数据核心不是：

用户 → 任务

而是：

```
用户
 |
 | 
人生方向
 |
成长目标
 |
成长事件
 |
个人记忆
 |
AI理解
 |
主动反馈
```

数据库需要支持：

- 长期记忆
- 语义搜索
- 用户画像演化
- AI主动行为

---

# 2. 数据库整体结构

```
User

 ├── Growth Goal

 ├── Memory Item

 ├── Growth Event

 ├── AI Observation

 ├── AI Action

 ├── Conversation

 └── User Profile
```

---

# 3. 用户表 user

```
create table users (

 id uuid primary key,

 nickname varchar(50),

 avatar text,

 created_at timestamp,

 updated_at timestamp

);
```

---

# 4. 用户画像 user_profile

作用：

存储AI对用户长期理解。

```
create table user_profiles (

 id uuid primary key,

 user_id uuid,


 personality jsonb,

 values jsonb,

 interests jsonb,

 strengths jsonb,

 weaknesses jsonb,


 current_stage varchar(50),


 ai_summary text,


 updated_at timestamp

);
```

示例：

```
{
 "interests":[
   "AI",
   "产品开发"
 ],

 "strengths":[
   "技术能力",
   "学习能力"
 ],

 "weaknesses":[
   "商业验证"
 ]
}
```

---

# 5. 成长目标 growth_goal

核心表。

```
create table growth_goals (

 id uuid primary key,


 user_id uuid,


 title varchar(200),


 description text,


 type varchar(50),


 status varchar(30),


 priority int,


 is_main_goal boolean,


 progress int,


 start_date date,


 target_date date,


 success_definition text,


 ai_summary text,


 created_at timestamp

);
```

状态：

```
exploring

active

blocked

paused

completed

archived
```

---

# 6. 对话记录 conversation

所有成长输入入口。

```
create table conversations (

 id uuid primary key,


 user_id uuid,


 role varchar(20),


 content text,


 created_at timestamp

);
```

role：

```
user

assistant

system
```

---

# 7. Memory核心表

## memory_item

```
create table memory_items (

 id uuid primary key,


 user_id uuid,


 type varchar(30),


 content text,


 summary text,


 importance int,


 emotion varchar(30),


 embedding vector(1536),


 source_conversation_id uuid,


 created_at timestamp

);
```

type:

```
event

decision

reflection

achievement

failure

emotion

thought
```

---

# 8. 成长事件 growth_event

用于连接目标。

```
create table growth_events (

 id uuid primary key,


 user_id uuid,


 goal_id uuid,


 memory_id uuid,


 impact_score int,


 description text,


 created_at timestamp

);
```

---

# 9. AI观察 ai_observation

AI主动发现。

例如：

“你的兴趣正在转向AI产品。”

```
create table ai_observations (

 id uuid primary key,


 user_id uuid,


 content text,


 confidence int,


 source_memories jsonb,


 status varchar(20),


 created_at timestamp

);
```

---

# 10. AI主动行为 ai_action

```
create table ai_actions (

 id uuid primary key,


 user_id uuid,


 type varchar(50),


 content text,


 trigger_reason text,


 status varchar(20),


 created_at timestamp

);
```

type:

```
reminder

insight

encouragement

reflection

warning
```

---

# 11. 关系图谱 memory_relation

未来支持数字人。

```
create table memory_relations (

 id uuid primary key,


 user_id uuid,


 source_id uuid,


 target_id uuid,


 relation_type varchar(50)

);
```

例如：

```
AI学习

   related_to

独立开发目标
```

---

# 12. 索引设计

## Memory搜索

```
create index idx_memory_embedding

on memory_items

using ivfflat(embedding vector_cosine_ops);
```

---

## 用户查询

```
create index idx_memory_user

on memory_items(user_id);
```