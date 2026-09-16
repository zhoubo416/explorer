import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const extractJson = (raw: string): Record<string, unknown> | null => {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)\s*```/i)?.[1] ?? raw;
  const start = fenced.indexOf("{");
  const end = fenced.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(fenced.slice(start, end + 1));
  } catch {
    return null;
  }
};

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

const callDeepSeek = async (apiKey: string, model: string, messages: unknown[], temperature: number): Promise<Response> => {
  const maxAttempts = 3;
  let lastError = "DeepSeek request failed";
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const res = await fetch(DEEPSEEK_URL, {
        method: "POST",
        headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, temperature, messages }),
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (res.ok) return res;
      if (res.status !== 429 && res.status < 500) return res;
      lastError = `DeepSeek HTTP ${res.status}`;
    } catch (error) {
      clearTimeout(timer);
      lastError = error instanceof Error ? error.message : String(error);
    }
    if (attempt < maxAttempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, 2000 * Math.pow(2, attempt)));
    }
  }
  return new Response(JSON.stringify({ error: lastError }), {
    status: 502,
    headers: { "Content-Type": "application/json" },
  });
};

const cleanString = (v: unknown): string => typeof v === "string" ? v.trim() : "";

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const deepseekApiKey = Deno.env.get("DEEPSEEK_API_KEY");
    const deepseekModel = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
    if (!supabaseUrl || !supabaseAnonKey || !deepseekApiKey) {
      return jsonResponse({ error: "AI service is not configured" }, 503);
    }

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonResponse({ error: "Unauthorized" }, 401);

    const body = await request.json().catch(() => null);
    const title = cleanString(body?.title);
    const description = cleanString(body?.description);
    const successDefinition = cleanString(body?.success_definition);
    if (!title) return jsonResponse({ error: "title is required" }, 400);

    const systemPrompt = `你是"探境"的目标规划器。把一个成长目标拆解成 2 到 4 个循序渐进的阶段，并为每个阶段生成 2 到 3 个足够小、可执行的行动项。
只返回 JSON，不要 Markdown，格式：
{"stages":[{"name":"阶段名","description":"这个阶段要达成什么","actions":["行动1","行动2"]},{"name":"...","description":"...","actions":["行动1"]}]}
规则：
1. 阶段之间是先后递进关系，覆盖从起步到完成的全过程。
2. 每个阶段都有 2 到 3 个行动项。
3. 行动项具体、可验证、一步就能开始。`;

    const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
      { role: "system", content: systemPrompt },
      { role: "user", content: JSON.stringify({ title, description, success_definition: successDefinition }) },
    ], 0.5);
    if (!aiResponse.ok) {
      return jsonResponse({ error: `DeepSeek request failed: ${await aiResponse.text()}` }, 502);
    }
    const aiBody = await aiResponse.json();
    const raw = aiBody.choices?.[0]?.message?.content;
    const parsed = typeof raw === "string" ? extractJson(raw) : null;

    const stages = Array.isArray(parsed?.stages)
      ? parsed.stages
          .filter((s: any) => s && cleanString(s.name))
          .slice(0, 4)
          .map((s: any) => ({
            name: cleanString(s.name),
            description: cleanString(s.description),
            actions: (Array.isArray(s.actions) ? s.actions : [])
              .filter((a: any) => cleanString(a))
              .slice(0, 4)
              .map((a: any) => ({ content: cleanString(a) })),
          }))
      : [];

    return jsonResponse({ stages });
  }
  catch (err) {
    return jsonResponse({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
