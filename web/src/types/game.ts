export type GameState =
  | "lobby"
  | "deal"
  | "deal_phase"
  | "prompt"
  | "voting"
  | "resolution";

export type GameRow = {
  id: string;
  room_code: string;
  state: GameState;
  current_prompt: string | null;
  created_at: string;
  updated_at: string;
};

export type PlayerRow = {
  id: string;
  game_id: string;
  display_name: string;
  role: "crew" | "imposter" | null;
  secret_word: string | null;
  score: number;
  created_at: string;
};
