import { test } from "node:test";
import assert from "node:assert/strict";
import { buildSystemPrompt, type ChatMode } from "./prompt.ts";

// 低情绪陪伴会主动邀请用户倾诉，安全底线是硬要求（App Store 1.2 / 1.4.1，
// 也是产品兜底）。这组用例防止后续改动把它删掉或只加在某一个模式上。
const modes: ChatMode[] = ["normal", "low_mood", "goal_creation"];

for (const mode of modes) {
  test(`${mode} 模式的提示词带安全底线`, () => {
    const prompt = buildSystemPrompt(mode);
    assert.match(prompt, /安全底线/, "缺少安全底线段落");
    assert.match(prompt, /不做诊断/, "缺少「不做诊断」约束");
    assert.match(prompt, /自伤/, "缺少自伤倾向的处置要求");
    assert.match(prompt, /紧急电话/, "缺少紧急情况引导");
    assert.match(prompt, /专业帮助/, "缺少寻求专业帮助的引导");
  });
}

test("安全底线之外仍保留各模式自身的要点", () => {
  assert.match(buildSystemPrompt("low_mood"), /第一层（情绪理解）/, "低情绪模式丢了分层流程");
  assert.match(buildSystemPrompt("goal_creation"), /成功标准/, "目标共创模式丢了目标结构");
  assert.match(buildSystemPrompt("normal"), /日常成长对话/, "日常模式丢了模式说明");
});
