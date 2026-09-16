import { test } from "node:test";
import assert from "node:assert/strict";
import { parseModelResult, normalizeGoal, normalizeGoalUpdate, normalizeGoalStatusUpdate, normalizeMemory } from "./model-result.ts";

test("parses a clean JSON reply with a valid memory", () => {
  const raw = JSON.stringify({
    reply: "听起来这是一个重要的决定。",
    memory: {
      type: "decision",
      content: "用户决定从真实用户反馈开始验证产品方向",
      summary: "转向真实用户验证",
      importance: 90,
      emotion: "坚定",
    },
  });
  assert.deepEqual(parseModelResult(raw), {
    reply: "听起来这是一个重要的决定。",
    memory: {
      type: "decision",
      content: "用户决定从真实用户反馈开始验证产品方向",
      summary: "转向真实用户验证",
      importance: 90,
      emotion: "坚定",
    },
    goal: null,
    goal_update: null,
    goal_status_update: null,
  });
});

test("parses a goal from goal_creation mode", () => {
  const raw = JSON.stringify({
    reply: "我们把它变成一个可以靠近的目标。",
    memory: null,
    goal: {
      title: "成为 AI 时代的独立创造者",
      description: "用一个真实产品验证创造方向",
      success_definition: "90 天完成一个 AI 产品 MVP 并获得 10 个用户反馈",
    },
    goal_update: null,
  });
  assert.deepEqual(parseModelResult(raw), {
    reply: "我们把它变成一个可以靠近的目标。",
    memory: null,
    goal: {
      title: "成为 AI 时代的独立创造者",
      description: "用一个真实产品验证创造方向",
      success_definition: "90 天完成一个 AI 产品 MVP 并获得 10 个用户反馈",
    },
    goal_update: null,
    goal_status_update: null,
  });
});

test("strips markdown fences around JSON", () => {
  const raw = '```json\n{"reply":"你好","memory":null}\n```';
  assert.deepEqual(parseModelResult(raw), {
    reply: "你好",
    memory: null,
    goal: null,
    goal_update: null,
    goal_status_update: null,
  });
});

test("falls back to raw text when JSON is malformed", () => {
  const raw = "这不是 JSON，只是一段回复";
  assert.deepEqual(parseModelResult(raw), {
    reply: "这不是 JSON，只是一段回复",
    memory: null,
    goal: null,
    goal_update: null,
    goal_status_update: null,
  });
});

test("normalizes importance and rejects unknown memory types", () => {
  assert.equal(normalizeMemory({ type: "event", content: "完成了首版设计", importance: "95" })?.importance, 95);
  assert.equal(normalizeMemory({ type: "event", content: "x", importance: 250 })?.importance, 100);
  assert.equal(normalizeMemory({ type: "event", content: "x", importance: -3 })?.importance, 0);
  assert.equal(normalizeMemory({ type: "gossip", content: "x" }), null);
  assert.equal(normalizeMemory({ type: "event", content: "   " }), null);
  assert.equal(normalizeMemory(null), null);
});

test("normalizes goals and rejects empty titles", () => {
  assert.deepEqual(normalizeGoal({ title: "目标A", description: "描述", success_definition: "标准" }), {
    title: "目标A",
    description: "描述",
    success_definition: "标准",
  });
  assert.equal(normalizeGoal({ title: "   ", description: "x" }), null);
  assert.equal(normalizeGoal(null), null);
});

test("normalizes goal_update", () => {
  assert.deepEqual(normalizeGoalUpdate({
    done_actions: ["完成 5 次用户访谈"],
    advance_stage: true,
    goal_completed: false,
    note: "已完成第一轮用户访谈",
  }), {
    done_actions: ["完成 5 次用户访谈"],
    advance_stage: true,
    goal_completed: false,
    note: "已完成第一轮用户访谈",
  });
  assert.equal(normalizeGoalUpdate(null), null);
  assert.equal(normalizeGoalUpdate({ done_actions: [], advance_stage: false, goal_completed: false, note: "" }), null);
});

test("normalizes goal_status_update", () => {
  assert.deepEqual(normalizeGoalStatusUpdate({ status: "paused", note: "先停一下" }), {
    status: "paused",
    note: "先停一下",
  });
  assert.equal(normalizeGoalStatusUpdate({ status: "bogus", note: "x" }), null);
  assert.equal(normalizeGoalStatusUpdate(null), null);
});
