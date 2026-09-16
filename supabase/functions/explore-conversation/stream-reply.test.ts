import { test } from "node:test";
import assert from "node:assert/strict";
import { createReplyStream } from "./stream-reply.ts";

const collect = (pieces: string[]) => {
  const chunks: string[] = [];
  const stream = createReplyStream((chunk) => chunks.push(chunk));
  for (const piece of pieces) stream.feed(piece);
  return { chunks, text: chunks.join(""), stream };
};

test("分片到达时能拼出完整 reply", () => {
  const json = '{"reply":"听起来这是一个重要的决定。","memory":{"type":"decision"}}';
  // 故意切在 JSON 结构中间
  const pieces = [json.slice(0, 3), json.slice(3, 12), json.slice(12, 20), json.slice(20)];
  const { text, stream } = collect(pieces);
  assert.equal(text, "听起来这是一个重要的决定。");
  assert.equal(stream.reply(), "听起来这是一个重要的决定。");
  // raw 必须完整保留，供 parseModelResult 做最终解析
  assert.equal(stream.raw(), json);
});

test("只吐出 reply 的值，不泄漏后面的字段", () => {
  const { text } = collect([
    '{"reply":"好的","memory":{"type":"event","content":"不应该出现在流里"}}',
  ]);
  assert.equal(text, "好的");
});

test("正确处理转义字符", () => {
  const json = '{"reply":"第一行\\n第二行 \\"引用\\" 和反斜杠 \\\\"}';
  const { text } = collect([json]);
  assert.equal(text, '第一行\n第二行 "引用" 和反斜杠 \\');
});

test("正确处理 \\uXXXX 转义，且跨分片时不丢字符", () => {
  const json = '{"reply":"\\u4f60\\u597d"}';
  // 把 你 切开，验证半个转义序列到达时不会被误吐
  const cut = json.indexOf("\\u597d");
  const { text, stream } = collect([json.slice(0, cut), json.slice(cut)]);
  assert.equal(text, "你好");
  assert.equal(stream.reply(), "你好");
});

test("一次喂入多个事件也不会重复输出", () => {
  const { text, stream } = collect(['{"reply":"abc"}']);
  stream.feed("");
  assert.equal(text, "abc");
});

test("模型返回纯文本时降级为原文输出", () => {
  const text = "我听到你说想做出自己的产品，这听起来是一件让你既兴奋又有点不确定的事情，我们可以先把它说得更具体一点，比如你希望它解决谁的什么问题。";
  const { text: out, stream } = collect([text.slice(0, 20), text.slice(20)]);
  assert.equal(out, text);
  assert.equal(stream.raw(), text);
});

test("过短且无 JSON 迹象时先不输出（避免误吐半个 JSON）", () => {
  const { text } = collect(['{"rep']);
  assert.equal(text, "");
});

test("短于阈值的纯文本不会流式输出（由 done 事件兜底补全）", () => {
  // 这是刻意的取舍：宁可晚一点显示，也不要先吐半个 JSON。
  // 服务端在结束时会用 done 事件带上最终回复，客户端据此补全。
  const { text, stream } = collect(["好的，我明白了。"]);
  assert.equal(text, "");
  assert.equal(stream.raw(), "好的，我明白了。");
});

test("reply 为空字符串时不输出内容", () => {
  const { text, stream } = collect(['{"reply":"","memory":null}']);
  assert.equal(text, "");
  assert.equal(stream.raw(), '{"reply":"","memory":null}');
});
