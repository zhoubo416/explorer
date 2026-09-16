import { readFileSync } from "node:fs";
import { parseModelResult } from "./model-result.ts";
import { buildSystemPrompt } from "./prompt.ts";

const loadDotEnv = (path: string): Record<string, string> => {
  const out: Record<string, string> = {};
  try {
    for (const line of readFileSync(path, "utf8").split("\n")) {
      const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
      if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, "");
    }
  } catch {
    /* ignore missing file */
  }
  return out;
};

const env = { ...loadDotEnv("mobile/.env"), ...process.env };
const apiKey = env.DEEPSEEK_API_KEY || env.DEEPSEEK_ApiKey;
const model = env.DEEPSEEK_MODEL || "deepseek-chat";

if (!apiKey) {
  console.error("Missing DeepSeek key (set DEEPSEEK_ApiKey in mobile/.env or DEEPSEEK_API_KEY).");
  process.exit(1);
}

const cases: { mode: "normal" | "low_mood"; history: { role: "user" | "assistant"; content: string }[] }[] = [
  {
    mode: "normal",
    history: [
      { role: "user", content: "我决定了，不再一直学新东西，先从真实用户反馈开始验证我的 AI 产品方向。" },
    ],
  },
  {
    mode: "normal",
    history: [
      { role: "user", content: "今天天气不错。" },
    ],
  },
];

const callDeepSeek = async (mode: "normal" | "low_mood", history: { role: string; content: string }[]) => {
  const res = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      temperature: 0.7,
      messages: [{ role: "system", content: buildSystemPrompt(mode) }, ...history],
    }),
  });
  if (!res.ok) throw new Error(`DeepSeek HTTP ${res.status}: ${await res.text()}`);
  const body = await res.json();
  const raw = body?.choices?.[0]?.message?.content;
  if (typeof raw !== "string") throw new Error("Empty model response");
  return raw;
};

for (const [index, c] of cases.entries()) {
  try {
    const raw = await callDeepSeek(c.mode, c.history);
    const parsed = parseModelResult(raw);
    console.log(`\n=== case ${index + 1} (mode=${c.mode}) ===`);
    console.log("raw:", raw);
    console.log("parsed:", JSON.stringify(parsed, null, 2));
  } catch (error) {
    console.error(`\n=== case ${index + 1} FAILED ===`);
    console.error(String(error));
  }
}
