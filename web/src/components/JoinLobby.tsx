"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { GameRow, PlayerRow } from "@/types/game";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { LandingMarketing } from "@/components/LandingMarketing";

const PLAYER_ID_KEY = "boxfort_player_id";
const LAST_PLAYER_ID_KEY = "boxfort_last_player_id";
const DISPLAY_NAME_KEY = "boxfort_display_name";
const SFX_VOLUME_KEY = "boxfortSfxVolume";
const MUSIC_VOLUME_KEY = "boxfortMusicVolume";
const MUTE_ALL_AUDIO_KEY = "boxfortMuteAllAudio";
const ROLE_REVEAL_SEEN_PREFIX = "boxfort_role_reveal_seen";
/** Fade long stingers (panic / outcome) so `bg_noir` can return when phase changes. */
const OVERRIDE_FADE_MS = 350;

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

function normalizeRoomCode(raw: string): string {
  return raw.replace(/[^a-zA-Z]/g, "").toUpperCase().slice(0, 4);
}

/** Burnt toast sees the shared burnt asset on their own phone; everyone else sees the library slice. */
function displayAvatarUrl(
  p: PlayerRow,
  viewerId: string | null
): string | null {
  if (viewerId && p.id === viewerId && p.role === "imposter") {
    return "/characters/burnt_toast.jpg";
  }
  return "/characters/detective_toast.jpg";
}

function PlayerAvatar({
  player,
  viewerId,
  className,
}: {
  player: PlayerRow;
  viewerId: string | null;
  className: string;
}) {
  const url = displayAvatarUrl(player, viewerId) ?? "/characters/detective_toast.jpg";
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={url}
      alt=""
      className={`rounded-full border-2 border-amber-800/20 bg-amber-50 object-cover ${className}`}
    />
  );
}

type Props = {
  initialCode?: string;
  /** Existing player row (e.g. hub added themselves on iPad; link includes `?player=`). */
  initialPlayerId?: string;
};

export function JoinLobby({
  initialCode = "",
  initialPlayerId = "",
}: Props) {
  const bgAudioRef = useRef<HTMLAudioElement | null>(null);
  const sfxAudioRef = useRef<HTMLAudioElement | null>(null);
  const overrideAudioRef = useRef<HTMLAudioElement | null>(null);
  const overrideFadeIntervalRef = useRef<ReturnType<typeof setInterval> | null>(
    null
  );
  const userInteractedRef = useRef(false);
  const lastOutcomeRoundRef = useRef<number | null>(null);
  const prevGameStateRef = useRef<string | null>(null);

  const [roomCode, setRoomCode] = useState(() => normalizeRoomCode(initialCode));
  const [displayName, setDisplayName] = useState("");
  const [players, setPlayers] = useState<PlayerRow[]>([]);
  const [gameId, setGameId] = useState<string | null>(null);
  const [gameRow, setGameRow] = useState<GameRow | null>(null);
  const [myPlayerId, setMyPlayerId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [voteBusy, setVoteBusy] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);
  const [showWebMenu, setShowWebMenu] = useState(false);
  const [muteAllAudio, setMuteAllAudio] = useState(true);
  const [musicVolume, setMusicVolume] = useState(0.6);
  const [sfxVolume, setSfxVolume] = useState(0.8);
  const [bootstrapping, setBootstrapping] = useState(() => {
    const p = initialPlayerId.trim();
    return p.length > 0 && /^[0-9a-f-]{36}$/i.test(p);
  });
  const [roleRevealSeenRound, setRoleRevealSeenRound] = useState<number | null>(
    null
  );
  /** True when URL contained `player=` — that session shares one DB row; warn so families don’t reuse the link. */
  const [showPlayerLinkWarning, setShowPlayerLinkWarning] = useState(false);

  const supabaseReady = useMemo(() => {
    try {
      getSupabaseBrowserClient();
      return true;
    } catch {
      return false;
    }
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const storedMute = localStorage.getItem(MUTE_ALL_AUDIO_KEY);
    if (storedMute == null) {
      localStorage.setItem(MUTE_ALL_AUDIO_KEY, "true");
    }
    const savedName = localStorage.getItem(DISPLAY_NAME_KEY);
    if (savedName && savedName.trim().length > 0) {
      setDisplayName(savedName.trim());
    }
    setMuteAllAudio((storedMute ?? "true") === "true");
    setMusicVolume(
      clamp01(Number(localStorage.getItem(MUSIC_VOLUME_KEY) ?? "0.6"))
    );
    setSfxVolume(clamp01(Number(localStorage.getItem(SFX_VOLUME_KEY) ?? "0.8")));
  }, [initialCode]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    localStorage.setItem(MUTE_ALL_AUDIO_KEY, muteAllAudio ? "true" : "false");
  }, [muteAllAudio]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    localStorage.setItem(MUSIC_VOLUME_KEY, String(clamp01(musicVolume)));
  }, [musicVolume]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    localStorage.setItem(SFX_VOLUME_KEY, String(clamp01(sfxVolume)));
  }, [sfxVolume]);

  useEffect(() => {
    if (!supabaseReady) {
      setConfigError(
        "Configure NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in web/.env.local"
      );
    }
  }, [supabaseReady]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const q = new URLSearchParams(window.location.search);
    if (q.has("player")) setShowPlayerLinkWarning(true);
  }, []);

  /** Resume session from query param or persisted player id (refresh-safe). */
  useEffect(() => {
    if (!supabaseReady || typeof window === "undefined") return;
    const params = new URLSearchParams(window.location.search);
    const pid = (
      params.get("player") ??
      initialPlayerId ??
      sessionStorage.getItem(PLAYER_ID_KEY) ??
      localStorage.getItem(LAST_PLAYER_ID_KEY) ??
      ""
    ).trim();
    if (!pid || !/^[0-9a-f-]{36}$/i.test(pid)) return;

    let cancelled = false;
    setBootstrapping(true);

    void (async () => {
      try {
        const supabase = getSupabaseBrowserClient();
        const { data: pl, error } = await supabase
          .from("players")
          .select("*")
          .eq("id", pid)
          .maybeSingle();
        if (cancelled || error || !pl) return;
        const { data: game, error: gErr } = await supabase
          .from("games")
          .select("*")
          .eq("id", pl.game_id)
          .maybeSingle();
        if (cancelled || gErr || !game) return;
        sessionStorage.setItem(PLAYER_ID_KEY, pid);
        localStorage.setItem(LAST_PLAYER_ID_KEY, pid);
        setMyPlayerId(pid);
        setGameId(game.id as string);
        setGameRow(game as GameRow);
        setRoomCode(normalizeRoomCode(game.room_code));
      } finally {
        if (!cancelled) setBootstrapping(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [supabaseReady, initialPlayerId]);

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
        localStorage.setItem(LAST_PLAYER_ID_KEY, inserted.id as string);
        localStorage.setItem(DISPLAY_NAME_KEY, name);
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
  const inPrompt =
    gameRow?.state === "prompt" ||
    gameRow?.state === "deal_phase" ||
    gameRow?.state === "deal";
  const inVoting = gameRow?.state === "voting";
  const inResolution = gameRow?.state === "resolution";

  const showdownPending = useMemo(
    () =>
      gameRow?.state === "resolution" &&
      gameRow.last_imposter_caught === true &&
      gameRow.showdown_resolved === false,
    [gameRow]
  );

  const turnOrder = gameRow?.turn_order ?? [];
  const turnIndex = gameRow?.turn_index ?? 0;

  const submitVote = useCallback(
    async (suspectId: string) => {
      if (!myPlayerId || !gameId || suspectId === myPlayerId) return;
      setVoteBusy(true);
      setError(null);
      try {
        const supabase = getSupabaseBrowserClient();
        const { error: uErr } = await supabase
          .from("players")
          .update({ vote_for: suspectId, voted_at: new Date().toISOString() })
          .eq("id", myPlayerId);
        if (uErr) setError(uErr.message);
      } finally {
        setVoteBusy(false);
      }
    },
    [gameId, myPlayerId]
  );

  const imposterPlayers = useMemo(
    () => players.filter((p) => p.role === "imposter"),
    [players]
  );

  const burntToastWins = useMemo(() => {
    if (!gameRow) return false;
    if (gameRow.last_imposter_caught === false) return true;
    if (
      gameRow.last_imposter_caught === true &&
      gameRow.showdown_resolved === true &&
      gameRow.imposter_word_guessed === true
    ) {
      return true;
    }
    return false;
  }, [gameRow]);

  const detectivesWin = useMemo(() => {
    if (!gameRow) return false;
    return (
      gameRow.last_imposter_caught === true &&
      gameRow.showdown_resolved === true &&
      gameRow.imposter_word_guessed !== true
    );
  }, [gameRow]);

  const voteTally = useMemo(() => {
    const m = new Map<string, number>();
    for (const p of players) {
      if (p.vote_for)
        m.set(p.vote_for, (m.get(p.vote_for) ?? 0) + 1);
    }
    return m;
  }, [players]);

  const myTurn =
    inPrompt &&
    Boolean(myPlayerId) &&
    turnOrder.length > 0 &&
    turnOrder[turnIndex] === myPlayerId;

  const clueRound = gameRow?.clue_round ?? 0;
  const currentRound = gameRow?.round_number ?? 0;

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (!gameId || !myPlayerId || !currentRound) {
      setRoleRevealSeenRound(null);
      return;
    }
    const key = `${ROLE_REVEAL_SEEN_PREFIX}:${gameId}:${myPlayerId}`;
    const seen = Number(sessionStorage.getItem(key) ?? "0");
    setRoleRevealSeenRound(Number.isFinite(seen) ? seen : 0);
  }, [gameId, myPlayerId, currentRound]);

  const shouldShowRoleReveal =
    gameRow?.state === "deal" &&
    !!me &&
    !!myPlayerId &&
    currentRound > 0 &&
    (roleRevealSeenRound ?? 0) < currentRound &&
    (me.role === "imposter" || me.role === "crew");

  const dismissRoleReveal = useCallback(() => {
    if (!gameId || !myPlayerId || !currentRound || typeof window === "undefined")
      return;
    const key = `${ROLE_REVEAL_SEEN_PREFIX}:${gameId}:${myPlayerId}`;
    sessionStorage.setItem(key, String(currentRound));
    setRoleRevealSeenRound(currentRound);
  }, [gameId, myPlayerId, currentRound]);

  const cancelOverrideFade = useCallback(() => {
    if (overrideFadeIntervalRef.current) {
      clearInterval(overrideFadeIntervalRef.current);
      overrideFadeIntervalRef.current = null;
    }
  }, []);

  const fadeOutOverrideAudio = useCallback(
    async (durationMs = OVERRIDE_FADE_MS): Promise<void> => {
      const a = overrideAudioRef.current;
      if (!a) return;
      cancelOverrideFade();
      a.onended = null;
      const startVol = a.volume;
      const steps = 10;
      const stepMs = Math.max(8, durationMs / steps);
      return new Promise((resolve) => {
        let step = 0;
        overrideFadeIntervalRef.current = setInterval(() => {
          step++;
          const el = overrideAudioRef.current;
          if (!el) {
            cancelOverrideFade();
            resolve();
            return;
          }
          el.volume = Math.max(0, startVol * (1 - step / steps));
          if (step >= steps) {
            cancelOverrideFade();
            el.pause();
            el.currentTime = 0;
            overrideAudioRef.current = null;
            resolve();
          }
        }, stepMs);
      });
    },
    [cancelOverrideFade]
  );

  const stopOverrideAudio = useCallback(() => {
    cancelOverrideFade();
    const a = overrideAudioRef.current;
    if (!a) return;
    a.onended = null;
    a.pause();
    a.currentTime = 0;
    overrideAudioRef.current = null;
  }, [cancelOverrideFade]);

  const stopAllAudio = useCallback(() => {
    cancelOverrideFade();
    const bg = bgAudioRef.current;
    if (bg) {
      bg.pause();
      bg.currentTime = 0;
    }
    const sfx = sfxAudioRef.current;
    if (sfx) {
      sfx.pause();
      sfx.currentTime = 0;
    }
    stopOverrideAudio();
  }, [cancelOverrideFade, stopOverrideAudio]);

  const readAudioSettings = useCallback(() => {
    if (typeof window === "undefined") {
      return { muted: true, music: 0.6, sfx: 0.8 };
    }
    const stored = localStorage.getItem(MUTE_ALL_AUDIO_KEY);
    const muted = (stored ?? "true") === "true";
    const music = clamp01(Number(localStorage.getItem(MUSIC_VOLUME_KEY) ?? "0.6"));
    const sfx = clamp01(Number(localStorage.getItem(SFX_VOLUME_KEY) ?? "0.8"));
    return { muted, music, sfx };
  }, []);

  const applyAudioVolumes = useCallback(() => {
    const { music, sfx } = readAudioSettings();
    if (bgAudioRef.current) bgAudioRef.current.volume = music;
    if (overrideAudioRef.current) overrideAudioRef.current.volume = music;
    if (sfxAudioRef.current) sfxAudioRef.current.volume = sfx;
  }, [readAudioSettings]);

  const ensureBackgroundAudio = useCallback(async () => {
    const { muted } = readAudioSettings();
    if (muted || !userInteractedRef.current) return;
    applyAudioVolumes();
    const bg = bgAudioRef.current;
    if (!bg || !bg.paused) return;
    try {
      await bg.play();
    } catch {
      // Ignore autoplay blocking; next interaction retries.
    }
  }, [applyAudioVolumes, readAudioSettings]);

  const playSFX = useCallback(
    async (file: string) => {
      const { muted } = readAudioSettings();
      if (muted || !userInteractedRef.current) return;
      const existing = sfxAudioRef.current;
      if (existing) {
        existing.pause();
      }
      const a = new Audio(`/audio/${file}`);
      sfxAudioRef.current = a;
      applyAudioVolumes();
      a.currentTime = 0;
      try {
        await a.play();
      } catch {
        // ignore browser block
      }
    },
    [applyAudioVolumes, readAudioSettings]
  );

  const playOverride = useCallback(
    async (file: string, loop: boolean) => {
      const { muted } = readAudioSettings();
      if (muted || !userInteractedRef.current) return;
      cancelOverrideFade();
      const bg = bgAudioRef.current;
      if (bg && !bg.paused) bg.pause();
      stopOverrideAudio();
      const a = new Audio(`/audio/${file}`);
      a.loop = loop;
      overrideAudioRef.current = a;
      applyAudioVolumes();
      if (!loop) {
        a.onended = () => {
          overrideAudioRef.current = null;
          void ensureBackgroundAudio();
        };
      }
      try {
        await a.play();
      } catch {
        // ignore browser block
      }
    },
    [
      applyAudioVolumes,
      cancelOverrideFade,
      ensureBackgroundAudio,
      readAudioSettings,
      stopOverrideAudio,
    ]
  );

  const syncStateAudio = useCallback(async () => {
    const { muted } = readAudioSettings();
    if (muted || !userInteractedRef.current) {
      stopAllAudio();
      return;
    }
    applyAudioVolumes();
    const showdownPending =
      gameRow?.state === "resolution" &&
      gameRow.last_imposter_caught === true &&
      gameRow.showdown_resolved === false;
    if (showdownPending) {
      const cur = overrideAudioRef.current;
      if (cur?.loop && cur.src.includes("detectives_panic")) {
        return;
      }
      await fadeOutOverrideAudio();
      await playOverride("detectives_panic.mp3", true);
      return;
    }

    if (gameRow?.state === "resolution" && gameRow.showdown_resolved === true) {
      const round = gameRow.round_number ?? 0;
      if (lastOutcomeRoundRef.current !== round) {
        lastOutcomeRoundRef.current = round;
        const burntToastWins =
          gameRow.last_imposter_caught === false ||
          gameRow.imposter_word_guessed === true;
        await fadeOutOverrideAudio();
        await playOverride(
          burntToastWins ? "detectives_lost.mp3" : "detectives_won.mp3",
          false
        );
        return;
      }
      // Already queued outcome for this round — do not fade/stop on every realtime poll.
      return;
    }

    if (gameRow?.state === "lobby") {
      lastOutcomeRoundRef.current = null;
    }
    await fadeOutOverrideAudio();
    await ensureBackgroundAudio();
  }, [
    applyAudioVolumes,
    ensureBackgroundAudio,
    fadeOutOverrideAudio,
    gameRow,
    playOverride,
    readAudioSettings,
    stopAllAudio,
  ]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const bg = new Audio("/audio/bg_noir.mp3");
    bg.loop = true;
    bg.preload = "auto";
    bgAudioRef.current = bg;
    applyAudioVolumes();

    const handleVisibility = () => {
      if (document.hidden) {
        stopAllAudio();
        return;
      }
      void syncStateAudio();
    };
    const handleStorage = () => {
      void syncStateAudio();
    };
    const handlePageHide = () => stopAllAudio();

    document.addEventListener("visibilitychange", handleVisibility);
    window.addEventListener("storage", handleStorage);
    window.addEventListener("pagehide", handlePageHide);
    window.addEventListener("beforeunload", handlePageHide);

    return () => {
      document.removeEventListener("visibilitychange", handleVisibility);
      window.removeEventListener("storage", handleStorage);
      window.removeEventListener("pagehide", handlePageHide);
      window.removeEventListener("beforeunload", handlePageHide);
      stopAllAudio();
      bgAudioRef.current = null;
      sfxAudioRef.current = null;
      overrideAudioRef.current = null;
    };
  }, [applyAudioVolumes, stopAllAudio, syncStateAudio]);

  useEffect(() => {
    void syncStateAudio();
  }, [syncStateAudio]);

  useEffect(() => {
    prevGameStateRef.current = null;
  }, [gameId]);

  useEffect(() => {
    const cur = gameRow?.state ?? null;
    const prev = prevGameStateRef.current;
    if (prev === "voting" && cur === "resolution") {
      requestAnimationFrame(() => {
        window.scrollTo({ top: 0, left: 0, behavior: "smooth" });
      });
    }
    prevGameStateRef.current = cur;
  }, [gameRow?.state]);

  if (bootstrapping && !gameId) {
    return (
      <div className="mx-auto flex min-h-screen w-[90vw] max-w-[720px] flex-col justify-center gap-6 py-12">
        <p className="text-center font-medium text-stone-700">
          Linking your slice…
        </p>
        <p className="text-center text-sm text-stone-500">
          Hang tight — connecting this phone to your player.
        </p>
      </div>
    );
  }

  if (gameId && gameRow?.state === "deal_phase") {
    return (
      <div
        className="noir-theme mx-auto flex min-h-screen w-[90vw] max-w-[720px] flex-col items-center justify-center gap-4 py-12 text-center"
        onPointerDownCapture={() => {
          if (!userInteractedRef.current) {
            userInteractedRef.current = true;
            void syncStateAudio();
          }
        }}
      >
        <p className="font-serif text-3xl font-bold text-stone-900">Game starting</p>
        <p className="max-w-[42ch] text-sm text-stone-700">
          Waiting for the host to continue. You&apos;ll soon find out if you are
          Burnt Toast or Detective Toast.
        </p>
      </div>
    );
  }

  return (
    <div
      className="noir-theme mx-auto flex min-h-screen w-[90vw] max-w-[720px] flex-col justify-center gap-8 py-12"
      onPointerDownCapture={() => {
        if (!userInteractedRef.current) {
          userInteractedRef.current = true;
          void syncStateAudio();
        }
      }}
      onClickCapture={(e) => {
        const target = e.target as HTMLElement | null;
        if (!target) return;
        const button = target.closest("button");
        if (!button) return;
        const audioMode = button.getAttribute("data-audio");
        if (audioMode === "none") return;
        if (audioMode === "new-game") {
          void playSFX("new_game.mp3");
          return;
        }
        void playSFX("button_press.mp3");
      }}
    >
      {gameId && showPlayerLinkWarning && (
        <div className="rounded-xl border border-amber-500/45 bg-amber-50 px-4 py-3 text-left text-sm text-amber-950 shadow-[2px_2px_0_0_rgba(120,83,30,0.12)]">
          <p className="font-semibold">This link is for one saved player</p>
          <p className="mt-1 leading-relaxed text-amber-950/90">
            If more than one person opened this exact URL, you are sharing the same
            player — votes and clues stay in sync. Other players should join with the
            room code only (no{" "}
            <span className="font-mono text-xs">player=</span> in the address bar).
          </p>
          <button
            type="button"
            className="mt-2 text-xs font-semibold text-amber-900 underline decoration-amber-700/50"
            onClick={() => setShowPlayerLinkWarning(false)}
          >
            Dismiss
          </button>
        </div>
      )}
      {showWebMenu && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/35 px-4">
          <div className="w-full max-w-[560px] rounded-2xl border border-stone-700/25 bg-[#f8f3ea] p-4 shadow-xl">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-sm font-semibold uppercase tracking-[0.14em] text-stone-700">
                Menu
              </p>
              <button
                type="button"
                onClick={() => setShowWebMenu(false)}
                className="rounded-lg border border-stone-400/40 px-2.5 py-1 text-sm text-stone-700 hover:bg-stone-100"
              >
                Done
              </button>
            </div>

            <section className="rounded-xl border border-stone-700/20 bg-white/70 p-3 text-stone-900">
              <p className="text-xs font-semibold uppercase tracking-[0.12em] text-stone-700">
                Audio
              </p>
              <div className="mt-2 space-y-3">
                <label className="flex items-center justify-between gap-3 text-sm font-medium">
                  <span>Mute all audio</span>
                  <input
                    type="checkbox"
                    checked={muteAllAudio}
                    onChange={(e) => setMuteAllAudio(e.target.checked)}
                    className="h-4 w-4 accent-stone-900"
                  />
                </label>
                <label className="block">
                  <div className="mb-1 flex items-center justify-between text-sm">
                    <span>Music volume</span>
                    <span className="font-mono text-xs">
                      {Math.round(musicVolume * 100)}%
                    </span>
                  </div>
                  <input
                    type="range"
                    min={0}
                    max={1}
                    step={0.05}
                    value={musicVolume}
                    disabled={muteAllAudio}
                    onChange={(e) =>
                      setMusicVolume(clamp01(Number(e.target.value)))
                    }
                    className="w-full accent-stone-900 disabled:opacity-50"
                  />
                </label>
                <label className="block">
                  <div className="mb-1 flex items-center justify-between text-sm">
                    <span>SFX volume</span>
                    <span className="font-mono text-xs">
                      {Math.round(sfxVolume * 100)}%
                    </span>
                  </div>
                  <input
                    type="range"
                    min={0}
                    max={1}
                    step={0.05}
                    value={sfxVolume}
                    disabled={muteAllAudio}
                    onChange={(e) =>
                      setSfxVolume(clamp01(Number(e.target.value)))
                    }
                    className="w-full accent-stone-900 disabled:opacity-50"
                  />
                </label>
              </div>
            </section>

            <section className="mt-3 rounded-xl border border-stone-700/20 bg-white/70 p-3 text-stone-900">
              <p className="text-xs font-semibold uppercase tracking-[0.12em] text-stone-700">
                Rules overview
              </p>
              <ul className="mt-2 space-y-2 text-sm text-stone-800">
                <li>
                  <strong>Roles:</strong> Detective Toasts share one word and image.
                  Burnt Toast gets neither.
                </li>
                <li>
                  <strong>Clues:</strong> Everyone gives a clue in order. The category
                  stays the same for the round; passes track how many times around the
                  table you have gone.
                </li>
                <li>
                  <strong>Themes + fairness:</strong> Host picks a theme (food, animals,
                  vehicles, nature, toys). Everyone sees the same category line; only
                  Detective Toasts get the picture and word. Speaking order is random; on
                  pass 1, early Burnt Toast may get one optional decoy word.
                </li>
                <li>
                  <strong>Voting:</strong> Tell Chief Loaf who Burnt Toast is. Top-vote
                  ties count.
                </li>
                <li>
                  <strong>Scoring:</strong> If Burnt Toast is caught and misses the final
                  guess, each Detective Toast gets +100. Otherwise each Burnt Toast gets
                  +100.
                </li>
              </ul>
            </section>
          </div>
        </div>
      )}

      {!gameId && (
        <div className="flex w-full justify-center px-2 pb-1 pt-0">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/characters/detective_toast_logo.png"
            alt=""
            className="h-auto w-full max-w-[min(100%,22rem)] object-contain drop-shadow-[0_1px_2px_rgba(28,25,23,0.12)]"
          />
        </div>
      )}

      <header className="text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-800/90">
          Detective Toast
        </p>
        <div className="mt-3">
          <button
            type="button"
            onClick={() => setShowWebMenu(true)}
            className="rounded-lg border border-stone-700/25 bg-white/70 px-3 py-1.5 text-xs font-semibold uppercase tracking-[0.12em] text-stone-700 hover:bg-white"
          >
            Menu
          </button>
        </div>
        <h1 className="mt-2 font-serif text-3xl font-bold text-stone-900">
          Hunt for the Burnt Toast
        </h1>
        {!gameId ? (
          <p className="mt-3 text-pretty text-sm leading-relaxed text-stone-600">
            A quick party mystery for families and friends. Enter the{" "}
            <strong className="font-semibold text-stone-800">room code</strong> from the
            hub and your name below — then scroll to learn how it works.
          </p>
        ) : (
          <p className="mt-3 text-pretty text-sm leading-relaxed text-stone-600">
            You&apos;re in the room. Keep this tab open while the host runs the game.
          </p>
        )}
      </header>

      {configError && (
        <div className="rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          {configError}
        </div>
      )}

      {error && gameId && (
        <div
          className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900"
          role="alert"
        >
          {error}
        </div>
      )}

      {!gameId ? (
        <>
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
        <LandingMarketing />
        </>
      ) : shouldShowRoleReveal && me ? (
        <section className="flex min-h-[68vh] flex-col items-center justify-center gap-6 rounded-2xl border-2 border-dashed border-stone-500/35 bg-white/80 p-6 shadow-[4px_4px_0_0_rgba(82,72,55,0.2)]">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={
              me.role === "imposter"
                ? "/characters/burnt_toast.jpg"
                : "/characters/detective_toast.jpg"
            }
            alt=""
            className="h-auto w-full rounded-2xl object-contain"
          />
          <p className="text-center text-xs font-semibold uppercase tracking-[0.14em] text-stone-600">
            Round {currentRound}
          </p>
          <p className="text-center font-serif text-3xl font-bold text-stone-900">
            {me.role === "imposter" ? "You are Burnt Toast" : "You are Detective Toast"}
          </p>
          <p className="text-center text-sm text-stone-700">
            {me.role === "imposter"
              ? "Blend in with short clues — one word or a phrase is OK. You do not get the word or image."
              : "You get the shared word and image. Each turn, give a word or short phrase without saying the secret."}
          </p>
          <button
            type="button"
            onClick={dismissRoleReveal}
            className="w-full rounded-xl bg-stone-900 px-4 py-3 text-base font-semibold text-stone-100 transition hover:bg-black"
          >
            Enter round
          </button>
        </section>
      ) : inLobby ? (
        <section className="flex flex-col gap-6 rounded-2xl border-2 border-dashed border-emerald-700/40 bg-emerald-50/80 p-6 shadow-[4px_4px_0_0_rgba(52,120,81,0.2)]">
          <div className="flex flex-col items-center gap-3 text-center">
            <div
              className="flex h-24 w-24 shrink-0 items-center justify-center overflow-hidden rounded-2xl border-2 border-dashed border-emerald-800/25 bg-white shadow-inner"
              aria-hidden
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/characters/detective_toast.jpg"
                alt=""
                className="h-full w-full rounded-2xl object-cover"
              />
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
                  <PlayerAvatar
                    player={p}
                    viewerId={myPlayerId}
                    className="h-10 w-10 shrink-0"
                  />
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
      ) : inResolution && me ? (
        <section className="flex flex-col gap-5 rounded-2xl border-2 border-dashed border-violet-600/45 bg-violet-50/90 p-6 shadow-[4px_4px_0_0_rgba(90,50,120,0.18)]">
          {showdownPending ? (
            <div className="rounded-2xl border border-rose-600/40 bg-rose-50/95 px-4 py-4 text-center">
              <p className="text-sm font-medium leading-snug text-rose-950">
                The host’s red countdown on the hub is the only timer. Listen for Burnt Toast’s
                final guess — only the hub can confirm whether they named the secret word.
              </p>
            </div>
          ) : null}
          <p className="text-center font-serif text-xl font-bold text-violet-950">
            Chief Loaf has spoken
          </p>
          {detectivesWin || burntToastWins ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={detectivesWin ? "/characters/detectives_won.jpg" : "/characters/burnt_toast_won.jpg"}
              alt=""
              className="h-auto w-full rounded-2xl object-contain"
            />
          ) : null}
          {imposterPlayers.length === 1 ? (
            <div className="flex flex-col items-center gap-2 text-center">
              <p className="text-sm font-semibold uppercase tracking-wide text-violet-800/90">
                Chief Loaf names Burnt Toast
              </p>
              <p className="w-full rounded-2xl border-2 border-amber-600/70 bg-amber-100/90 px-5 py-4 font-serif text-3xl font-bold leading-tight text-violet-950 shadow-[inset_0_1px_0_0_rgba(255,255,255,0.5)]">
                {imposterPlayers[0]!.display_name}
              </p>
            </div>
          ) : imposterPlayers.length > 1 ? (
            <div className="flex flex-col items-center gap-3 text-center">
              <p className="text-sm font-semibold uppercase tracking-wide text-violet-800/90">
                Chief Loaf names the Burnt Toasts
              </p>
              <div className="flex w-full flex-col gap-2">
                {imposterPlayers.map((p) => (
                  <p
                    key={p.id}
                    className="rounded-xl border-2 border-amber-600/60 bg-amber-100/85 px-4 py-3 font-serif text-2xl font-bold text-violet-950"
                  >
                    {p.display_name}
                  </p>
                ))}
              </div>
            </div>
          ) : null}
          {gameRow?.last_imposter_caught === true &&
          gameRow?.showdown_resolved === false ? (
            <p className="text-center text-sm font-medium text-rose-900">
              Chief Loaf grants one final guess... Burnt Toast has a chance to name the word.
            </p>
          ) : gameRow?.last_imposter_caught === true &&
            gameRow?.imposter_word_guessed === true ? (
            <p className="text-center text-sm font-medium text-orange-900">
              Burnt Toast was found, but guessed the secret word correctly — Burnt Toast wins this round (+100 each).
            </p>
          ) : gameRow?.last_imposter_caught === true ? (
            <p className="text-center text-sm font-medium text-emerald-900">
              Burnt Toast was found and missed the final guess — Detective Toasts win this round (+100 each).
            </p>
          ) : gameRow?.last_imposter_caught === false ? (
            <p className="text-center text-sm text-violet-900/90">
              Burnt Toast escaped the vote — Burnt Toast wins this round (+100 each).
            </p>
          ) : null}
          {me.role === "imposter" ? (
            <p className="text-center text-sm leading-relaxed text-violet-950/85">
              {gameRow?.imposter_word_guessed === true
                ? "You were Burnt Toast — they caught you, but you nailed the secret word and stole the round."
                : "You were Burnt Toast. Crumb-by-crumb, did they catch you?"}
            </p>
          ) : me.last_vote_correct === true ? (
            <p className="text-center text-sm font-semibold text-emerald-800">
              {gameRow?.imposter_word_guessed === true
                ? "You found Burnt Toast — but they guessed the word, so Burnt Toast wins this round."
                : "You pointed at Burnt Toast — detective instincts."}
            </p>
          ) : me.last_vote_correct === false ? (
            <p className="text-center text-sm text-violet-900/90">
              Your vote landed on a fellow detective this time.
            </p>
          ) : (
            <p className="text-center text-sm text-violet-900/80">
              Scores below — butter luck next round.
            </p>
          )}
          <ul className="divide-y divide-violet-800/10 rounded-xl border border-violet-800/15 bg-white/90">
            {players
              .slice()
              .sort((a, b) => b.score - a.score)
              .map((p) => (
                <li
                  key={p.id}
                  className="flex items-center justify-between gap-3 px-4 py-3 text-stone-900"
                >
                  <span className="font-medium">{p.display_name}</span>
                  <span className="text-sm font-semibold text-violet-900/80">
                    {p.score} pts
                  </span>
                </li>
              ))}
          </ul>
          <p className="text-center text-xs text-violet-900/70">
            The host will start the next round when everyone is ready.
          </p>
        </section>
      ) : inVoting && me ? (
        <section className="flex flex-col gap-4 rounded-2xl border-2 border-dashed border-rose-600/45 bg-rose-50/90 p-6 shadow-[4px_4px_0_0_rgba(120,60,70,0.18)]">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/characters/chief_loaf.jpg"
            alt=""
            className="h-auto w-full rounded-2xl object-contain opacity-95"
          />
          <p className="text-center font-serif text-lg font-bold text-rose-950">
            Tell Chief Loaf who Burnt Toast is
          </p>
          <p className="text-center text-sm leading-relaxed text-rose-950/85">
            Chief Loaf judges by the top vote pile (ties count). You can&apos;t pick
            yourself.
          </p>
          {voteTally.size > 0 && (
            <ul className="rounded-lg border border-rose-200/80 bg-white/80 px-3 py-2 text-xs text-rose-950/90">
              {players.map((p) => {
                const n = voteTally.get(p.id) ?? 0;
                if (n === 0) return null;
                return (
                  <li key={p.id} className="flex justify-between gap-2 py-0.5">
                    <span>{p.display_name}</span>
                    <span className="font-mono font-semibold">{n} votes</span>
                  </li>
                );
              })}
            </ul>
          )}
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {players
              .filter((p) => p.id !== myPlayerId)
              .map((p) => {
                const selected = me.vote_for === p.id;
                return (
                  <button
                    key={p.id}
                    type="button"
                    disabled={voteBusy}
                    onClick={() => void submitVote(p.id)}
                    className={`flex items-center gap-3 rounded-xl border-2 px-4 py-3 text-left transition ${
                      selected
                        ? "border-rose-700 bg-rose-100/90"
                        : "border-rose-300/80 bg-white/95 hover:border-rose-500"
                    }`}
                  >
                    <PlayerAvatar
                      player={p}
                      viewerId={myPlayerId}
                      className="h-12 w-12 shrink-0"
                    />
                    <span className="font-semibold text-rose-950">
                      {p.display_name}
                    </span>
                    {selected && (
                      <span className="ml-auto text-xs font-bold uppercase text-rose-800">
                        your vote
                      </span>
                    )}
                  </button>
                );
              })}
          </div>
        </section>
      ) : inPrompt && me?.role === "imposter" ? (
        <section className="flex flex-col gap-4 rounded-2xl border-2 border-dashed border-amber-600/50 bg-amber-50/90 p-6 shadow-[4px_4px_0_0_rgba(120,90,40,0.2)]">
          {myTurn && (
            <div
              className="rounded-xl border-2 border-amber-600 bg-amber-200/90 px-4 py-3 text-center shadow-[3px_3px_0_0_rgba(120,83,30,0.35)]"
              role="status"
            >
              <p className="text-xs font-bold uppercase tracking-[0.15em] text-amber-950">
                It&apos;s your turn
              </p>
              <p className="mt-1 text-sm font-medium text-amber-950/90">
                Give a word or short phrase — you don&apos;t know the secret, so stay
                vague.
              </p>
            </div>
          )}
          <p className="text-center text-xs font-semibold uppercase tracking-wide text-amber-900/70">
            Round {gameRow?.round_number ?? 1} · Clue passes done: {clueRound}
          </p>
          {gameRow?.current_prompt && (
            <p className="text-center font-serif text-lg font-bold leading-snug text-amber-950">
              {gameRow.current_prompt}
            </p>
          )}
          <p className="text-center text-xs leading-relaxed text-amber-950/75">
            Everyone sees this fill-in-the-blank. Only Detective Toasts get the picture and
            the secret word on their phone — stay vague if the line feels easy to guess.
          </p>
          <p className="rounded-lg bg-stone-800 px-3 py-2 text-center text-sm font-bold text-amber-100">
            You are the Burnt Toast
          </p>
          <p className="text-center text-sm text-amber-950/85">
            You don&apos;t get the picture or the secret word — only Detective Toasts
            do. Everyone still sees your toast portrait; on your phone you look
            charred. Blend in with a word or short phrase.
          </p>
          <div className="flex flex-col items-center gap-2">
            <p className="text-center text-xs font-semibold uppercase tracking-wide text-amber-900/70">
              {clueRound === 0 &&
              myTurn &&
              me.imposter_nudge_words &&
              me.imposter_nudge_words.length >= 1
                ? "First pass — optional decoy"
                : "Your word"}
            </p>
            {clueRound === 0 &&
            myTurn &&
            me.imposter_nudge_words &&
            me.imposter_nudge_words.length >= 1 ? (
              <div className="w-full rounded-xl border-2 border-amber-700/35 bg-amber-100/90 px-4 py-4 text-center shadow-inner">
                <p className="text-xs text-amber-900/80">
                  Not the real answer — just something you can say out loud.
                </p>
                <p className="mt-3 font-serif text-2xl font-bold text-amber-950">
                  {me.imposter_nudge_words[0]}
                </p>
              </div>
            ) : (
              <p className="text-center text-2xl font-bold tracking-tight text-amber-900/80">
                (none — you&apos;re flying blind)
              </p>
            )}
            <PlayerAvatar
              player={me}
              viewerId={myPlayerId}
              className="h-20 w-20"
            />
          </div>
          {turnOrder.length > 0 && (
            <div className="mt-2 rounded-xl border border-amber-800/15 bg-white/80 p-3">
              <p className="mb-2 text-center text-xs font-semibold uppercase tracking-wide text-amber-900/70">
                Speaking order
              </p>
              <ol className="space-y-2 text-sm text-amber-950">
                {turnOrder.map((pid, i) => {
                  const pl = players.find((x) => x.id === pid);
                  const name = pl?.display_name ?? "Player";
                  const current = turnOrder[turnIndex] === pid;
                  return (
                    <li
                      key={`${pid}-${i}`}
                      className={`flex items-center gap-3 ${current ? "font-bold text-amber-900" : ""}`}
                    >
                      <span className="w-6 text-right text-amber-800/70">
                        {i + 1}.
                      </span>
                      {pl && (
                        <PlayerAvatar
                          player={pl}
                          viewerId={myPlayerId}
                          className="h-9 w-9 shrink-0"
                        />
                      )}
                      <span className="flex-1">{name}</span>
                      {current && (
                        <span className="text-xs font-semibold uppercase text-orange-700">
                          now
                        </span>
                      )}
                    </li>
                  );
                })}
              </ol>
            </div>
          )}
        </section>
      ) : inPrompt && me?.role === "crew" && me.secret_word ? (
        <section className="flex flex-col gap-4 rounded-2xl border-2 border-dashed border-amber-600/50 bg-amber-50/90 p-6 shadow-[4px_4px_0_0_rgba(120,90,40,0.2)]">
          {myTurn && (
            <div
              className="rounded-xl border-2 border-amber-600 bg-amber-200/90 px-4 py-3 text-center shadow-[3px_3px_0_0_rgba(120,83,30,0.35)]"
              role="status"
            >
              <p className="text-xs font-bold uppercase tracking-[0.15em] text-amber-950">
                It&apos;s your turn
              </p>
              <p className="mt-1 text-sm font-medium text-amber-950/90">
                Give a word or short phrase — don&apos;t toast the secret aloud.
              </p>
            </div>
          )}
          <p className="text-center text-xs font-semibold uppercase tracking-wide text-amber-900/70">
            Round {gameRow?.round_number ?? 1} · Clue passes done: {clueRound}
          </p>
          {gameRow?.current_prompt && (
            <p className="text-center font-serif text-lg font-bold leading-snug text-amber-950">
              {gameRow.current_prompt}
            </p>
          )}
          {gameRow?.round_image_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={gameRow.round_image_url}
              alt=""
              className="mx-auto h-auto w-full max-w-[50vw] md:max-w-[32vw] rounded-2xl object-contain"
            />
          ) : null}
          <p className="text-center text-sm text-amber-950/85">
            You&apos;re Detective Toast. Use the picture and your word — a word or short
            phrase is fine when it&apos;s your turn.
          </p>
          <div className="flex flex-col items-center gap-2">
            <p className="text-center text-xs font-semibold uppercase tracking-wide text-amber-900/70">
              Your word
            </p>
            <p className="text-center text-4xl font-bold tracking-tight text-amber-900">
              {me.secret_word}
            </p>
            <PlayerAvatar
              player={me}
              viewerId={myPlayerId}
              className="h-20 w-20"
            />
          </div>
          {turnOrder.length > 0 && (
            <div className="mt-2 rounded-xl border border-amber-800/15 bg-white/80 p-3">
              <p className="mb-2 text-center text-xs font-semibold uppercase tracking-wide text-amber-900/70">
                Speaking order
              </p>
              <ol className="space-y-2 text-sm text-amber-950">
                {turnOrder.map((pid, i) => {
                  const pl = players.find((x) => x.id === pid);
                  const name = pl?.display_name ?? "Player";
                  const current = turnOrder[turnIndex] === pid;
                  return (
                    <li
                      key={`${pid}-${i}`}
                      className={`flex items-center gap-3 ${current ? "font-bold text-amber-900" : ""}`}
                    >
                      <span className="w-6 text-right text-amber-800/70">
                        {i + 1}.
                      </span>
                      {pl && (
                        <PlayerAvatar
                          player={pl}
                          viewerId={myPlayerId}
                          className="h-9 w-9 shrink-0"
                        />
                      )}
                      <span className="flex-1">{name}</span>
                      {current && (
                        <span className="text-xs font-semibold uppercase text-orange-700">
                          now
                        </span>
                      )}
                    </li>
                  );
                })}
              </ol>
            </div>
          )}
        </section>
      ) : inPrompt && me ? (
        <section className="rounded-2xl border border-amber-200 bg-amber-50/80 p-6 text-center text-amber-950">
          <p className="font-medium">Dealing roles…</p>
          <p className="mt-2 text-sm text-amber-900/80">
            Hang tight — the round is still starting.
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
        <a
          href="https://detectivetoast.com"
          className="font-medium text-stone-600 underline decoration-stone-400/60 underline-offset-2 hover:text-stone-800"
        >
          DetectiveToast.com
        </a>
        <span className="text-stone-400"> · </span>
        Hunt for the Burnt Toast
      </footer>
    </div>
  );
}
