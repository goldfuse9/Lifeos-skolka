// Minimální náhrada supabase-js (jen .rpc) pro lokální test proti PostgREST.
export type SupabaseClient = ReturnType<typeof createClient>;
export function createClient(url: string, key: string, opt?: { global?: { headers?: Record<string, string> } }) {
  const auth = opt?.global?.headers?.Authorization ?? `Bearer ${key}`;
  return {
    async rpc(name: string, args: Record<string, unknown> = {}) {
      const r = await fetch(`${url}/rest/v1/rpc/${name}`, { method: "POST", headers: { Authorization: auth, apikey: key, "Content-Type": "application/json" }, body: JSON.stringify(args) });
      const t = await r.text(); const d = t ? JSON.parse(t) : null;
      return r.ok ? { data: d, error: null } : { data: null, error: { message: d?.message ?? t } };
    },
  };
}
