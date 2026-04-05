import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type AnthropicMessageResponse = {
  content: Array<{ type: string; text?: string }>;
};

type RoundPayload = {
  prompt: string;
  crew_word: string;
  imposter_word: string;
};

function stripJsonFence(text: string): string {
  const trimmed = text.trim();
  const fence = /^```(?:json)?\s*([\s\S]*?)```$/m.exec(trimmed);
  if (fence) return fence[1].trim();
  return trimmed;
}

function parseRoundJson(raw: string): RoundPayload {
  const cleaned = stripJsonFence(raw);
  const parsed = JSON.parse(cleaned) as Record<string, unknown>;
  const prompt = parsed.prompt;
  const crew_word = parsed.crew_word;
  const imposter_word = parsed.imposter_word;
  if (
    typeof prompt !== "string" ||
    typeof crew_word !== "string" ||
    typeof imposter_word !== "string"
  ) {
    throw new Error("Model JSON missing prompt, crew_word, or imposter_word");
  }
  return { prompt, crew_word, imposter_word };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!anthropicKey || !supabaseUrl || !serviceKey) {
    return new Response(
      JSON.stringify({ error: "Server misconfigured: missing secrets" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  let gameId: string;
  try {
    const body = (await req.json()) as { game_id?: string };
    if (!body.game_id || typeof body.game_id !== "string") {
      return new Response(JSON.stringify({ error: "game_id required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    gameId = body.game_id;
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: players, error: playersErr } = await supabase
    .from("players")
    .select("id, display_name, game_id")
    .eq("game_id", gameId)
    .order("created_at", { ascending: true });

  if (playersErr) {
    return new Response(JSON.stringify({ error: playersErr.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!players || players.length < 3) {
    return new Response(
      JSON.stringify({ error: "Need at least 3 players to start" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const playerLines = players
    .map((p: { display_name: string; id: string }) => `- ${p.display_name} (${p.id})`)
    .join("\n");

  const system =
    "You are a writer for a family-friendly BoxFort game. Generate a silly scenario with a blank space. Then, generate two related but distinct words that could fill that blank. Word A is for the Crew. Word B is for the Imposter. Return ONLY a JSON object with the keys: 'prompt', 'crew_word', 'imposter_word'. No markdown, no commentary.";

  const user = `Players in this round:\n${playerLines}\n\nProduce one round suitable for all ages.`;

  const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": anthropicKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-3-5-haiku-20241022",
      max_tokens: 1024,
      system,
      messages: [{ role: "user", content: user }],
    }),
  });

  if (!anthropicRes.ok) {
    const errText = await anthropicRes.text();
    return new Response(
      JSON.stringify({
        error: "Anthropic request failed",
        detail: errText.slice(0, 2000),
      }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const anthropicJson = (await anthropicRes.json()) as AnthropicMessageResponse;
  const textBlock = anthropicJson.content?.find((c) => c.type === "text");
  const rawText = textBlock?.text ?? "";
  let round: RoundPayload;
  try {
    round = parseRoundJson(rawText);
  } catch (e) {
    return new Response(
      JSON.stringify({
        error: "Failed to parse model JSON",
        detail: String(e),
        raw: rawText.slice(0, 2000),
      }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const imposterIndex = Math.floor(Math.random() * players.length);
  const imposter = players[imposterIndex] as { id: string; display_name: string };

  for (const p of players as { id: string }[]) {
    const isImposter = p.id === imposter.id;
    const { error: upErr } = await supabase
      .from("players")
      .update({
        role: isImposter ? "imposter" : "crew",
        secret_word: isImposter ? round.imposter_word : round.crew_word,
      })
      .eq("id", p.id);
    if (upErr) {
      return new Response(JSON.stringify({ error: upErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  }

  const { error: gameErr } = await supabase
    .from("games")
    .update({
      current_prompt: round.prompt,
      state: "deal_phase",
    })
    .eq("id", gameId);

  if (gameErr) {
    return new Response(JSON.stringify({ error: gameErr.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({
      ok: true,
      imposter_id: imposter.id,
      prompt: round.prompt,
      crew_word: round.crew_word,
      imposter_word: round.imposter_word,
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
