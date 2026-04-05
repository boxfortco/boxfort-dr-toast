"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { GameRow, PlayerRow } from "@/types/game";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const PLAYER_ID_KEY = "boxfort_player_id";

const CHEF_EMOJIS = [
  "🧑‍🍳",
  "👩‍🍳",
  "🥪",
  "🧀",
  "🥕",
  "🍞",
  "🍳",
  "🧁",
  "🍿",
  "🥤",
];

function normalizeRoomCode(raw: string): string {
  return raw.replace(/[^a-zA-Z]/g, "").toUpperCase().slice(0, 4);
}

function emojiForName(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) {
    h = (h * 31 + name.charCodeAt(i)) >>> 0;
  }
  return CHEF_EMOJIS[h % CHEF_EMOJIS.length];
}

type Props = {
  initialCode?: string;
};

export function JoinLobby({ initialCode = "" }: Props) {
  const [roomCode, setRoomCode] = useState(() => normalizeRoomCode(initialCode));
  const [displayName, setDisplayName] = useState("");
  const [players, setPlayers] = useState<PlayerRow[]>([]);
  const [gameId, setGameId] = useState<string | null>(null);
  const [gameRow, setGameRow] = useState<GameRow | null>(null);
  const [myPlayerId, setMyPlayerId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);

  const supabaseReady = useMemo(() => {
    try {
      getSupabaseBrowserClient();
      return true;
    } catch {
      return false;
    }
  }, []);

  useEffect(() => {
    if (!supabaseReady) {
      setConfigError(
        "Configure NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in web/.env.local"
      );
    }
  }, [supabaseReady]);

  const subscribeToLobby = useCallback((gid: string) => {
    const supabase = getSupabaseBrowserClient();

    const loadPlayers = () =>
      supabase
        .from("players")
        .select("*")
        .eq("game_id", gid)
        .order("created_at", { ascending: true })
        .then(({ data, error: qErr }) => {
          if (qErr) return;
          setPlayers((data ?? []) as PlayerRow[]);
        });

    const loadGame = () =>
      supabase
        .from("games")
        .select("*")
        .eq("id", gid)
        .maybeSingle()
        .then(({ data, error: gErr }) => {
          if (gErr) return;
          if (data) setGameRow(data as GameRow);
        });

    const chPlayers = supabase
      .channel(`players:${gid}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "players",
          filter: `game_id=eq.${gid}`,
        },
        () => {
          void loadPlayers();
        }
      )
      .subscribe();

    const chGames = supabase
      .channel(`games:${gid}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "games",
          filter: `id=eq.${gid}`,
        },
        () => {
          void loadGame();
        }
      )
      .subscribe();

    void loadPlayers();
    void loadGame();

    return () => {
      void supabase.removeChannel(chPlayers);
      void supabase.removeChannel(chGames);
    };
  }, []);

  useEffect(() => {
    if (!gameId) return;
    return subscribeToLobby(gameId);
  }, [gameId, subscribeToLobby]);

  useEffect(() => {
    if (typeof window === "undefined" || !gameId) return;
    const stored = sessionStorage.getItem(PLAYER_ID_KEY);
    if (stored) setMyPlayerId(stored);
  }, [gameId]);

  async function handleJoin(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!supabaseReady) return;
    const code = normalizeRoomCode(roomCode);
    const name = displayName.trim();
    if (code.length !== 4) {
      setError("Enter the 4-letter room code from the host screen.");
      return;
    }
    if (name.length < 1) {
      setError("Enter your name.");
      return;
    }

    setBusy(true);
    try {
      const supabase = getSupabaseBrowserClient();
      const { data: game, error: gameErr } = await supabase
        .from("games")
        .select("*")
        .eq("room_code", code)
        .maybeSingle();

      if (gameErr) {
        setError(gameErr.message);
        return;
      }
      if (!game) {
        setError("No game found for that code. Check with the host.");
        return;
      }

      const { data: inserted, error: insErr } = await supabase
        .from("players")
        .insert({
          game_id: game.id,
          display_name: name,
        })
        .select("id")
        .single();

      if (insErr) {
        setError(insErr.message);
        return;
      }

      if (inserted?.id && typeof window !== "undefined") {
        sessionStorage.setItem(PLAYER_ID_KEY, inserted.id as string);
        setMyPlayerId(inserted.id as string);
      }

      setGameRow(game as GameRow);
      setGameId(game.id as string);
    } finally {
      setBusy(false);
    }
  }

  const me = useMemo(
    () => players.find((p) => p.id === myPlayerId),
    [players, myPlayerId]
  );

  const inLobby = gameRow?.state === "lobby";
  const inDeal =
    gameRow?.state === "deal_phase" || gameRow?.state === "deal";

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-8 px-6 py-12">
      <header className="text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-800/90">
          BoxFort
        </p>
        <h1 className="mt-2 font-serif text-3xl font-bold text-stone-900">
          Dr. Toast&apos;s Mix-Up
        </h1>
        <p className="mt-3 text-pretty text-sm leading-relaxed text-stone-600">
          Enter the room code on the iPad, then your name. Your phone keeps
          secrets and votes — you do the talking out loud.
        </p>
      </header>

      {configError && (
        <div className="rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          {configError}
        </div>
      )}

      {!gameId ? (
        <form
          onSubmit={handleJoin}
          className="flex flex-col gap-4 rounded-2xl border-2 border-dashed border-stone-300 bg-[#faf7f2] p-6 shadow-[4px_4px_0_0_rgba(120,113,108,0.25)]"
        >
          <label className="flex flex-col gap-1.5 text-left">
            <span className="text-xs font-semibold uppercase tracking-wide text-stone-600">
              Room code
            </span>
            <input
              className="rounded-lg border border-stone-300 bg-white px-3 py-3 text-center font-mono text-2xl tracking-[0.35em] text-stone-900 uppercase placeholder:normal-case placeholder:tracking-normal placeholder:text-stone-400"
              inputMode="text"
              autoCapitalize="characters"
              autoCorrect="off"
              spellCheck={false}
              maxLength={4}
              placeholder="e.g. ZOOM"
              value={roomCode}
              onChange={(e) => setRoomCode(normalizeRoomCode(e.target.value))}
            />
          </label>

          <label className="flex flex-col gap-1.5 text-left">
            <span className="text-xs font-semibold uppercase tracking-wide text-stone-600">
              Your name
            </span>
            <input
              className="rounded-lg border border-stone-300 bg-white px-3 py-3 text-lg text-stone-900 placeholder:text-stone-400"
              autoComplete="nickname"
              placeholder="What should we call you?"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
            />
          </label>

          {error && (
            <p className="text-sm text-red-700" role="alert">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={busy || !supabaseReady}
            className="rounded-xl bg-amber-700 px-4 py-3 text-lg font-semibold text-amber-50 shadow-[3px_3px_0_0_rgba(68,64,60,0.35)] transition hover:bg-amber-800 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? "Joining…" : "Join room"}
          </button>
        </form>
      ) : inLobby ? (
        <section className="flex flex-col gap-6 rounded-2xl border-2 border-dashed border-emerald-700/40 bg-emerald-50/80 p-6 shadow-[4px_4px_0_0_rgba(52,120,81,0.2)]">
          <div className="flex flex-col items-center gap-3 text-center">
            <div
              className="flex h-24 w-24 items-center justify-center rounded-2xl border-2 border-dashed border-emerald-800/25 bg-white text-5xl shadow-inner"
              aria-hidden
            >
              {emojiForName(displayName.trim() || "chef")}
            </div>
            <p className="font-serif text-xl font-bold text-emerald-950">
              You&apos;re in!
            </p>
            <p className="max-w-xs text-pretty text-base leading-relaxed text-emerald-950/90">
              Waiting for the Host to start the game… Grab a snack, not a
              spoiler.
            </p>
            <p className="text-sm text-emerald-900/75">
              Room{" "}
              <span className="font-mono font-bold text-emerald-950">
                {roomCode}
              </span>
              {" · "}
              <span className="font-semibold">{displayName.trim()}</span>
            </p>
          </div>

          <div>
            <p className="mb-2 text-center text-xs font-semibold uppercase tracking-wide text-emerald-900/70">
              In the kitchen
            </p>
            <ul className="divide-y divide-emerald-800/10 rounded-xl border border-emerald-800/15 bg-white/90">
              {players.map((p) => (
                <li
                  key={p.id}
                  className="flex items-center gap-3 px-4 py-3 text-stone-900"
                >
                  <span className="text-2xl" aria-hidden>
                    {emojiForName(p.display_name)}
                  </span>
                  <span className="font-medium">{p.display_name}</span>
                  {p.id === myPlayerId && (
                    <span className="ml-auto text-xs font-semibold uppercase tracking-wide text-emerald-700">
                      you
                    </span>
                  )}
                </li>
              ))}
            </ul>
          </div>
        </section>
      ) : inDeal && me?.secret_word ? (
        <section className="flex flex-col gap-4 rounded-2xl border-2 border-dashed border-amber-600/50 bg-amber-50/90 p-6 shadow-[4px_4px_0_0_rgba(120,90,40,0.2)]">
          <p className="text-center font-serif text-lg font-bold text-amber-950">
            Your secret ingredient
          </p>
          <p className="text-center text-4xl font-bold tracking-tight text-amber-900">
            {me.secret_word}
          </p>
          <p className="text-center text-sm text-amber-950/80">
            Don&apos;t say it out loud — work it into your answer when it&apos;s
            your turn.
          </p>
        </section>
      ) : (
        <section className="rounded-2xl border border-stone-200 bg-white/80 p-6 text-center text-stone-700">
          <p className="font-medium">Round update</p>
          <p className="mt-2 text-sm text-stone-600">
            Stay on this screen — the host is moving the game along.
          </p>
        </section>
      )}

      <footer className="text-center text-xs text-stone-500">
        BoxFort — papercraft party games for families.
      </footer>
    </div>
  );
}
