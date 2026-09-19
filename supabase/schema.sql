create extension if not exists pgcrypto;
create extension if not exists vector;

-- This migration is additive and isolated for the Explore app.
-- It does not alter the existing public.tasks or public.task_comments tables.

create table if not exists public.explore_user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname varchar(50),
  avatar text,
  personality jsonb not null default '{}'::jsonb,
  values jsonb not null default '{}'::jsonb,
  interests jsonb not null default '[]'::jsonb,
  strengths jsonb not null default '[]'::jsonb,
  weaknesses jsonb not null default '[]'::jsonb,
  current_stage varchar(50),
  ai_summary text,
  growth_dimensions jsonb not null default '[]'::jsonb,
  growth_composition jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.explore_conversation_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title varchar(200) not null default '新的对话',
  preview text,
  mode varchar(30) not null default 'normal' check (mode in ('normal', 'low_mood', 'goal_creation')),
  mood_stage integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.explore_conversations (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.explore_conversation_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role varchar(20) not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.explore_growth_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title varchar(200) not null,
  description text,
  type varchar(50),
  status varchar(30) not null default 'exploring' check (status in ('exploring', 'active', 'blocked', 'paused', 'completed', 'archived')),
  priority integer not null default 0,
  is_main_goal boolean not null default false,
  progress integer not null default 0 check (progress between 0 and 100),
  start_date date,
  target_date date,
  success_definition text,
  ai_summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.explore_memory_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type varchar(30) not null check (type in ('event', 'decision', 'reflection', 'achievement', 'failure', 'emotion', 'thought')),
  content text not null,
  summary text,
  importance integer not null default 0 check (importance between 0 and 100),
  emotion varchar(30),
  embedding vector(1536),
  source_conversation_id uuid references public.explore_conversations(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.explore_growth_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references public.explore_growth_goals(id) on delete set null,
  memory_id uuid references public.explore_memory_items(id) on delete set null,
  impact_score integer not null default 0 check (impact_score between 0 and 100),
  description text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.explore_ai_observations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  confidence integer not null default 0 check (confidence between 0 and 100),
  source_memories jsonb not null default '[]'::jsonb,
  status varchar(20) not null default 'new' check (status in ('new', 'read', 'dismissed')),
  created_at timestamptz not null default now()
);

create table if not exists public.explore_ai_actions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type varchar(50) not null check (type in ('reminder', 'insight', 'encouragement', 'reflection', 'warning')),
  content text not null,
  trigger_reason text,
  status varchar(20) not null default 'pending' check (status in ('pending', 'sent', 'read', 'dismissed')),
  created_at timestamptz not null default now()
);

create table if not exists public.explore_memory_relations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_id uuid not null references public.explore_memory_items(id) on delete cascade,
  target_id uuid not null references public.explore_memory_items(id) on delete cascade,
  relation_type varchar(50) not null,
  unique (source_id, target_id, relation_type)
);

create index if not exists idx_explore_sessions_user_updated on public.explore_conversation_sessions(user_id, updated_at desc);
create index if not exists idx_explore_conversations_session_created on public.explore_conversations(session_id, created_at);
create index if not exists idx_explore_conversations_user_created on public.explore_conversations(user_id, created_at desc);
create index if not exists idx_explore_goals_user_status on public.explore_growth_goals(user_id, status);
create unique index if not exists idx_explore_one_main_goal_per_user on public.explore_growth_goals(user_id) where is_main_goal = true and status <> 'archived';
create index if not exists idx_explore_memories_user_created on public.explore_memory_items(user_id, created_at desc);
create index if not exists idx_explore_events_user_created on public.explore_growth_events(user_id, created_at desc);
create index if not exists idx_explore_observations_user_status on public.explore_ai_observations(user_id, status, created_at desc);
create index if not exists idx_explore_actions_user_status on public.explore_ai_actions(user_id, status, created_at desc);
create index if not exists idx_explore_memory_embedding on public.explore_memory_items using ivfflat (embedding vector_cosine_ops) with (lists = 100);

create or replace function public.explore_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists explore_user_profiles_updated_at on public.explore_user_profiles;
create trigger explore_user_profiles_updated_at before update on public.explore_user_profiles for each row execute function public.explore_set_updated_at();
drop trigger if exists explore_sessions_updated_at on public.explore_conversation_sessions;
create trigger explore_sessions_updated_at before update on public.explore_conversation_sessions for each row execute function public.explore_set_updated_at();
drop trigger if exists explore_goals_updated_at on public.explore_growth_goals;
create trigger explore_goals_updated_at before update on public.explore_growth_goals for each row execute function public.explore_set_updated_at();

-- No auth.users trigger is installed here because this database is shared.
-- Explore creates the profile after the user has an authenticated session.

alter table public.explore_user_profiles enable row level security;
alter table public.explore_conversation_sessions enable row level security;
alter table public.explore_conversations enable row level security;
alter table public.explore_growth_goals enable row level security;
alter table public.explore_memory_items enable row level security;
alter table public.explore_growth_events enable row level security;
alter table public.explore_ai_observations enable row level security;
alter table public.explore_ai_actions enable row level security;
alter table public.explore_memory_relations enable row level security;

drop policy if exists explore_user_profiles_self on public.explore_user_profiles;
create policy explore_user_profiles_self on public.explore_user_profiles for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_sessions_self on public.explore_conversation_sessions;
create policy explore_sessions_self on public.explore_conversation_sessions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_conversations_self on public.explore_conversations;
create policy explore_conversations_self on public.explore_conversations for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_goals_self on public.explore_growth_goals;
create policy explore_goals_self on public.explore_growth_goals for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_memories_self on public.explore_memory_items;
create policy explore_memories_self on public.explore_memory_items for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_events_self on public.explore_growth_events;
create policy explore_events_self on public.explore_growth_events for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_observations_self on public.explore_ai_observations;
create policy explore_observations_self on public.explore_ai_observations for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_actions_self on public.explore_ai_actions;
create policy explore_actions_self on public.explore_ai_actions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists explore_relations_self on public.explore_memory_relations;
create policy explore_relations_self on public.explore_memory_relations for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 探境 周报历史表（新增，2026-08-15）
create table if not exists public.explore_weekly_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null,
  week_end date not null,
  score numeric(3,1) not null default 0,
  completed jsonb not null default '[]'::jsonb,
  insight text,
  next_steps jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, week_start)
);

create index if not exists idx_explore_weekly_reports_user_week
  on public.explore_weekly_reports (user_id, week_start desc);

drop trigger if exists explore_weekly_reports_updated_at on public.explore_weekly_reports;
create trigger explore_weekly_reports_updated_at
  before update on public.explore_weekly_reports
  for each row execute function public.explore_set_updated_at();

alter table public.explore_weekly_reports enable row level security;

drop policy if exists explore_weekly_reports_self on public.explore_weekly_reports;
create policy explore_weekly_reports_self
  on public.explore_weekly_reports
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 探境 目标阶段与行动项（新增，2026-08-19）
alter table public.explore_growth_goals
  add column if not exists stages jsonb not null default '[]'::jsonb;

-- 探境 AI 成长维度与成长构成（新增，2026-08-20）
alter table public.explore_user_profiles
  add column if not exists growth_dimensions jsonb not null default '[]'::jsonb;
alter table public.explore_user_profiles
  add column if not exists growth_composition jsonb not null default '[]'::jsonb;

-- 探境 低情绪陪伴层级状态（新增，2026-08-20）
alter table public.explore_conversation_sessions
  add column if not exists mood_stage integer not null default 0;

-- 探境 关系图谱支持记忆↔目标（新增，2026-08-20）
alter table public.explore_memory_relations
  alter column target_id drop not null;
alter table public.explore_memory_relations
  add column if not exists target_goal_id uuid references public.explore_growth_goals(id) on delete cascade;
create unique index if not exists idx_explore_memory_relations_goal_unique
  on public.explore_memory_relations (source_id, target_goal_id, relation_type);

-- 探境 每日建议（新增，2026-08-20）
create table if not exists public.explore_daily_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  suggestion_date date not null default current_date,
  content text not null,
  created_at timestamptz not null default now(),
  unique (user_id, suggestion_date)
);

create index if not exists idx_explore_daily_suggestions_user_date
  on public.explore_daily_suggestions (user_id, suggestion_date desc);

alter table public.explore_daily_suggestions enable row level security;

drop policy if exists explore_daily_suggestions_self on public.explore_daily_suggestions;
create policy explore_daily_suggestions_self
  on public.explore_daily_suggestions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 探境 语义记忆检索函数（新增，2026-08-17）
create or replace function public.explore_match_memories(
  p_user_id uuid,
  query_embedding vector(1536),
  match_threshold float default 0.3,
  match_count int default 10
)
returns table (
  id uuid,
  type varchar,
  content text,
  summary text,
  importance int,
  emotion varchar,
  similarity float
)
language sql
stable
as $$
  select
    m.id,
    m.type,
    m.content,
    m.summary,
    m.importance,
    m.emotion,
    1 - (m.embedding <=> query_embedding) as similarity
  from public.explore_memory_items m
  where m.user_id = p_user_id
    and m.embedding is not null
    and 1 - (m.embedding <=> query_embedding) > match_threshold
  order by m.embedding <=> query_embedding
  limit match_count;
$$;

-- 2026-09-16 观察文案口吻统一：存量观察从「用户……」改为「你……」
-- 与 explore-observations 的提示词及 normalizeVoice 对应；增量幂等，可重复执行
update public.explore_ai_observations
set content = replace(content, '这个用户', '你')
where content like '%这个用户%';

update public.explore_ai_observations
set content = replace(content, '该用户', '你')
where content like '%该用户%';

update public.explore_ai_observations
set content = replace(content, '用户', '你')
where content like '%用户%';

-- 2026-09-16 其余生成文案口吻统一（每日建议/画像/主动消息/目标分析/周报）
-- 与各函数提示词及 normalizeVoice 对应；增量幂等，可重复执行
update public.explore_daily_suggestions
set content = replace(replace(replace(content, '这个用户', '你'), '该用户', '你'), '用户', '你')
where content like '%用户%';

update public.explore_user_profiles
set ai_summary = replace(replace(replace(ai_summary, '这个用户', '你'), '该用户', '你'), '用户', '你')
where ai_summary like '%用户%';

update public.explore_user_profiles
set current_stage = replace(replace(replace(current_stage, '这个用户', '你'), '该用户', '你'), '用户', '你')
where current_stage like '%用户%';

update public.explore_ai_actions
set content = replace(replace(replace(content, '这个用户', '你'), '该用户', '你'), '用户', '你')
where content like '%用户%';

-- ai_summary 列存 JSON 字符串，纯文本替换不影响 JSON 结构
update public.explore_growth_goals
set ai_summary = replace(replace(replace(ai_summary, '这个用户', '你'), '该用户', '你'), '用户', '你')
where ai_summary like '%用户%';

update public.explore_weekly_reports
set insight = replace(replace(replace(insight, '这个用户', '你'), '该用户', '你'), '用户', '你')
where insight like '%用户%';

update public.explore_weekly_reports
set completed = (
  select coalesce(jsonb_agg(to_jsonb(replace(replace(replace(elem #>> '{}', '这个用户', '你'), '该用户', '你'), '用户', '你'))), '[]'::jsonb)
  from jsonb_array_elements(completed) as elem
)
where completed::text like '%用户%';

update public.explore_weekly_reports
set next_steps = (
  select coalesce(jsonb_agg(to_jsonb(replace(replace(replace(elem #>> '{}', '这个用户', '你'), '该用户', '你'), '用户', '你'))), '[]'::jsonb)
  from jsonb_array_elements(next_steps) as elem
)
where next_steps::text like '%用户%';

-- 2026-09-16 每日建议按「目标+天」缓存（每个目标每天最多生成一条）
-- 主目标切换后建议跟随当前目标；唯一键从 (user_id, suggestion_date) 改为 (user_id, goal_id, suggestion_date)
-- 与 explore-daily-suggestion 的按目标查询和 upsert 对应；增量幂等，可重复执行
alter table public.explore_daily_suggestions
  add column if not exists goal_id uuid references public.explore_growth_goals(id) on delete set null;

alter table public.explore_daily_suggestions
  drop constraint if exists explore_daily_suggestions_user_id_suggestion_date_key;

create unique index if not exists idx_explore_daily_suggestions_user_goal_date
  on public.explore_daily_suggestions (user_id, goal_id, suggestion_date);

-- 存量行回填：把已生成的建议归到该用户的当前主目标（只影响 goal_id 为空的行）
update public.explore_daily_suggestions s
set goal_id = g.id
from public.explore_growth_goals g
where s.goal_id is null
  and g.user_id = s.user_id
  and g.is_main_goal;

-- 2026-09-19 意见反馈与内容举报（App Store 审核要求 AI 生成内容类应用提供反馈渠道）
-- 只有本人能写、本人能读；删除账号时随 auth.users 级联清空
create table if not exists public.explore_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category varchar(20) not null default 'feedback' check (category in ('feedback', 'content_report')),
  content text not null,
  contact text,
  app_version varchar(20),
  platform varchar(20),
  created_at timestamptz not null default now()
);

create index if not exists idx_explore_feedback_user_created
  on public.explore_feedback (user_id, created_at desc);

alter table public.explore_feedback enable row level security;

drop policy if exists explore_feedback_self on public.explore_feedback;
create policy explore_feedback_self on public.explore_feedback
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
