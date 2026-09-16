-- 定时触发「主动消息」全量检测
-- 说明：本文件是给 Supabase Dashboard → SQL Editor 手动执行的 cron 配置。

-- 0) 先启用扩展（二选一）：
--    方式 A：Dashboard → Database → Extensions → 打开 pg_cron 和 pg_net
--    方式 B：用 postgres 角色执行下面两句（普通 SQL Editor 可能权限不足）
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;

-- 1) 每天 UTC 01:00（北京时间 09:00）触发
--    改时间：'分 时 日 月 周'，注意 pg_cron 用 UTC。
select cron.schedule(
  'explore-proactive-daily',
  '0 1 * * *',
  $$
  select net.http_post(
    url := 'https://bjbfxxvgtiatstdytzzn.supabase.co/functions/v1/explore-proactive',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqYmZ4eHZndGlhdHN0ZHl0enpuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3MzMzMjksImV4cCI6MjA5OTMwOTMyOX0._rUyza78zwnRKs5VwgSTtSCBR6ngz2tcUe6phKituD8',
      'x-cron-secret', 'explore-cron-859baf6473718b54bb2c276a'
    ),
    body := '{}'
  );
  $$
);

-- 2) 常用管理命令
-- 查看已配置任务：
--   select * from cron.job;
-- 删除本任务：
--   select cron.unschedule('explore-proactive-daily');
