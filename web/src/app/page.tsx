import { JoinLobby } from "@/components/JoinLobby";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>;
}) {
  const sp = await searchParams;
  return <JoinLobby initialCode={sp.code ?? ""} />;
}
