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

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const apiKey = Deno.env.get("DASHSCOPE_API_KEY");
    const baseUrl = Deno.env.get("DASHSCOPE_BASE_URL") ??
      "https://llm-t2z6g1f4j7dhfig1.cn-beijing.maas.aliyuncs.com/compatible-mode/v1";
    if (!apiKey) return jsonResponse({ error: "DASHSCOPE_API_KEY not configured" }, 503);

    // Require a valid Supabase user to prevent anonymous abuse.
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);
    const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonResponse({ error: "Unauthorized" }, 401);

    const body = await request.json().catch(() => null);
    const rawInput = body?.input;
    if (!rawInput) return jsonResponse({ error: "input is required" }, 400);
    const inputs = (Array.isArray(rawInput) ? rawInput : [rawInput]).map((x) => String(x)).slice(0, 32);
    if (inputs.some((x) => !x.trim())) return jsonResponse({ error: "input contains empty text" }, 400);

    const res = await fetch(`${baseUrl}/embeddings`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: "text-embedding-v4", input: inputs, dimensions: 1536 }),
    });
    if (!res.ok) return jsonResponse({ error: `Embedding request failed: ${await res.text()}` }, 502);

    const data = await res.json();
    const embeddings = (data?.data ?? []).map((d: any) => d?.embedding ?? null);
    return jsonResponse({ embeddings });
  }
  catch (err) {
    return jsonResponse({
      error: err instanceof Error ? err.message : String(err),
    }, 500);
  }
});
