// 从模型的流式输出里增量抽出 reply 字段。
//
// 模型被要求返回 JSON（{"reply":"...","memory":{...}}），所以不能把原始流直接
// 吐给用户——必须边收边解析，只把 reply 这个字符串的值增量送出去。
// 逻辑与 explore-goal-chat 中的同类实现一致，那边已经跑通；这里额外把累积的
// 原始输出暴露出来，供 parseModelResult 做最终解析。
export type ReplyStream = {
  /** 喂入一段模型输出 */
  feed: (delta: string) => void;
  /** 目前为止的完整原始输出 */
  raw: () => string;
  /** 已经抽出的完整回复文本 */
  reply: () => string;
};

export const createReplyStream = (
  onDelta: (chunk: string) => void,
): ReplyStream => {
  let raw = "";
  let state: "idle" | "inReply" | "done" = "idle";
  let index = 0;
  let pending = "";
  let escaped = false;
  let mode: "undecided" | "json" | "plain" = "undecided";
  let plainSent = 0;
  let fullReply = "";

  const flush = () => {
    if (pending) {
      fullReply += pending;
      onDelta(pending);
      pending = "";
    }
  };

  const feed = (delta: string) => {
    raw += delta;

    // 模型没按 JSON 返回时，整段当纯文本流出去
    if (mode === "plain") {
      if (raw.length > plainSent) {
        const chunk = raw.slice(plainSent);
        fullReply += chunk;
        onDelta(chunk);
        plainSent = raw.length;
      }
      return;
    }

    if (mode === "undecided") {
      if (raw.trimStart().startsWith("{")) {
        mode = "json";
      } else if (raw.indexOf('"reply"') >= 0) {
        mode = "json";
      } else if (raw.length > 60) {
        // 够长了还没看到 JSON 的迹象，按纯文本处理
        mode = "plain";
        fullReply += raw;
        onDelta(raw);
        plainSent = raw.length;
        return;
      } else {
        return;
      }
    }

    if (state === "done") return;

    if (state === "idle") {
      const keyIdx = raw.indexOf('"reply"');
      if (keyIdx < 0) return;
      let p = keyIdx + 7;
      while (p < raw.length && (raw[p] === " " || raw[p] === "\t")) p++;
      if (p >= raw.length || raw[p] !== ":") return;
      p++;
      while (p < raw.length && (raw[p] === " " || raw[p] === "\t")) p++;
      if (p >= raw.length || raw[p] !== '"') return;
      state = "inReply";
      index = p + 1;
    }

    while (index < raw.length) {
      const ch = raw[index];
      if (escaped) {
        if (ch === "u" && index + 4 < raw.length) {
          const hex = raw.slice(index + 1, index + 5);
          if (/^[0-9a-fA-F]{4}$/.test(hex)) {
            pending += String.fromCharCode(parseInt(hex, 16));
            index += 5;
          } else {
            pending += "u";
            index++;
          }
        } else {
          const map: Record<string, string> = {
            n: "\n",
            t: "\t",
            r: "\r",
            '"': '"',
            "\\": "\\",
            "/": "/",
          };
          pending += map[ch] ?? ch;
          index++;
        }
        escaped = false;
        continue;
      }
      if (ch === "\\") {
        escaped = true;
        index++;
        continue;
      }
      if (ch === '"') {
        state = "done";
        index++;
        break;
      }
      pending += ch;
      index++;
    }
    flush();
  };

  return {
    feed,
    raw: () => raw,
    reply: () => fullReply,
  };
};
