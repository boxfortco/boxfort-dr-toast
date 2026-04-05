# BoxFort — Dr. Toast’s Mix-Up

Local multiplayer party game in the Jackbox style: an **iOS/iPadOS host** shows the room and prompts; **phones** run a lightweight web client for secret words and voting.

## Repository layout

| Path | Purpose |
|------|---------|
| `Imposter with Dr. Toast/` | SwiftUI host app (Xcode project at repo root) |
| `web/` | Next.js 15 + Tailwind player controller |
| `supabase/migrations/` | PostgreSQL schema, RLS, and Realtime publication |
| `supabase/functions/generate-round/` | Edge Function: Anthropic round generation + imposter assignment |

## Backend choice: Supabase vs Firebase

**Recommendation: Supabase (Postgres + Realtime)** for this game.

- **Relational model** maps cleanly to `games`, `players`, and content tables; you can enforce constraints (unique `room_code`, valid `game_state`) in SQL.
- **Row Level Security** lets you evolve from permissive party-play policies to host-scoped rules later.
- **Realtime** broadcasts `INSERT`/`UPDATE` on `games` and `players` so web clients update instantly without polling.
- **Edge Functions** can safely call Anthropic with secrets stored in Supabase, then write game state with the **service role**.

The host app uses **PostgREST over HTTPS** plus **polling** for lobby sync (no extra Swift packages). The **generate-round** function is invoked over HTTPS when the host taps **Start game**.

## One-time setup

### 1. Supabase project

1. Create a project at [supabase.com](https://supabase.com).
2. In **SQL Editor**, run migrations in order:
   - `supabase/migrations/20250405000000_initial.sql`
   - `supabase/migrations/20250405000001_add_deal_phase.sql` (adds `deal_phase` to `game_state`)
3. Under **Database → Replication**, confirm `games` and `players` are listed for Realtime.
4. Copy **Project URL** and **anon public key** from **Project Settings → API**.

### 2. Edge Function `generate-round` (Anthropic)

The function loads players by `game_id`, calls **Anthropic** (`claude-3-5-haiku-20241022`), assigns one random **Imposter**, writes `crew` / `imposter` roles and `secret_word` for each player, then sets `games.current_prompt` and `games.state = 'deal_phase'`.

**Secrets**

- `ANTHROPIC_API_KEY` — create at [Anthropic Console](https://console.anthropic.com/) and add to Supabase:

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-api03-...
```

(`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are available automatically inside deployed Edge Functions; for local serve, link the project or set them in `supabase/.env`.)

**Deploy** (from repo root, with [Supabase CLI](https://supabase.com/docs/guides/cli) installed and logged in):

```bash
supabase functions deploy generate-round --project-ref YOUR_PROJECT_REF
```

`YOUR_PROJECT_REF` is the project id string in the Supabase dashboard URL.

**Invoke**

- **Body:** `{ "game_id": "<uuid>" }`
- **Headers:** `Authorization: Bearer <anon key>`, `apikey: <anon key>`, `Content-Type: application/json`
- The iOS host calls `POST /functions/v1/generate-round` via `SupabaseRESTClient.invokeGenerateRound`.

### 3. Web client (`web/`)

```bash
cd web
cp .env.local.example .env.local
# Edit .env.local with NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). Optional: `http://localhost:3000/?code=ABCD` to prefill the room code.

Deploy the web app (see **Vercel** below) and use that **origin** in the iOS `webJoinBaseURL` so Share / QR match production.

### Vercel (recommended for the web app)

Vercel hosts the **Next.js** player UI. Your **database, Realtime, and Edge Functions stay on Supabase** — that is intentional: this project uses Supabase Postgres, RLS, Realtime channels, and the `generate-round` Edge Function. **Vercel’s own Postgres (Neon)** is a separate product; switching would mean re‑implementing migrations, Realtime, and server logic. For BoxFort, use **Vercel + Supabase together**.

1. Push the repo to GitHub (or GitLab / Bitbucket).
2. In [Vercel](https://vercel.com): **Add New Project** → import the repo.
3. Set **Root Directory** to `web` (the Next.js app lives there, not the repo root).
4. Under **Environment Variables**, add (Production / Preview as you prefer):
   - `NEXT_PUBLIC_SUPABASE_URL` — from Supabase → Project Settings → API
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` — same page (**anon public** key only; never the service role key)
5. Deploy. Your live URL will look like `https://<project>.vercel.app`.
6. Update **iOS** `BoxFortConfig.webJoinBaseURL` to that URL (no trailing slash).
7. **Anthropic API key:** store it only in **Supabase** (Edge Function secrets), not in Vercel env vars — the browser must never see it. In Supabase CLI: `supabase secrets set ANTHROPIC_API_KEY=...` then redeploy `generate-round`. If a key was ever pasted into chat or committed, **rotate it** in the Anthropic console and update Supabase secrets.

CLI alternative (from your machine): `npm i -g vercel`, then `cd web && vercel` and link the project; set the same env vars in the Vercel dashboard or `vercel env pull`.

### 4. iOS host

1. Open `Imposter with Dr. Toast.xcodeproj` in Xcode.
2. Edit `Imposter with Dr. Toast/BoxFortConfig.swift`:
   - `supabaseURL`, `supabaseAnonKey` — same as web `.env.local`.
   - `webJoinBaseURL` — deployed web origin with **no trailing slash** (e.g. `https://boxfort.vercel.app`). Used for **ShareLink** and **QR** (`?code=ABCD`).
3. Build and run. Flow: **Onboarding** → **Lobby** (room code, QR, share, player list) → **Start game** (enabled with ≥ 3 players) calls the Edge Function.

## How syncing works

- **Host:** Polls every 2s: `games` + `players` for the active `game_id`. **Start game** invokes `generate-round`.
- **Web:** After join, Realtime on `players` and `games`; lobby shows a playful waiting state; after `deal_phase`, phones show their **secret word** when assigned.

## Next steps

- Tighten RLS and host authentication before a public release.
- Prompt phase UI on the host and voting sync.
