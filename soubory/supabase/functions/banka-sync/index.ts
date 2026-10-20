// Supabase Edge Function „banka-sync“ — stáhne příchozí platby z banky školky
// a spáruje je s dětmi (databázová funkce banka_zpracuj → fin_zpracuj_platby).
//
// Kdo ji spouští:
//   • pg_cron každých 15 min (supabase/banka-cron.sql) s hlavičkou x-cron-secret
//     → projde všechny školky s aktivním napojením,
//   • ředitelna tlačítkem „Načíst platby z banky“ s JWT přihlášené ředitelky,
//     zástupkyně nebo hospodářky → jen jejich školka.
//
// Banka: Fio (API Bankovnictví). Stahuje se vždy posledních N dní (periods),
// ne „od poslední zarážky“ (last) — když se něco pokazí, další běh to dožene;
// duplicity pozná databáze podle ID pohybu.
//
// Nasazení: supabase functions deploy banka-sync --no-verify-jwt
//           supabase secrets set CRON_SECRET=<dlouhý náhodný řetězec>
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// veřejný klíč; kdyby v prostředí nebyl, poslouží klíč služby — práva stejně určí JWT uživatele v hlavičce
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? SERVICE;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const FIO_API = Deno.env.get("FIO_API_URL") ?? "https://fioapi.fio.cz/v1/rest";   // jiná adresa jen pro testy

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });

type Platba = { datum: string; castka: number; vs: string; protiucet: string; nazev: string; zprava: string; doklad: string };
type Napojeni = { skola_id: string; banka: string; token: string; stahovat_dni: number };

/* Datum v Praze jako RRRR-MM-DD. */
function denPraha(d: Date): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Prague" }).format(d);
}

/* Fio vrací datum buď jako „2026-10-15+0200“, nebo (starší dokumentace) jako ms od epochy. */
function fioDatum(v: unknown): string | null {
  if (typeof v === "number") return denPraha(new Date(v));
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}/.test(v)) return v.slice(0, 10);
  return null;
}

const sloupec = (t: Record<string, { value: unknown } | null>, n: number): unknown => t["column" + n]?.value ?? null;
const text = (v: unknown) => (v == null ? "" : String(v).trim());

/* Stažení pohybů z Fio a převod na příchozí platby v CZK. */
async function stahniFio(token: string, dni: number): Promise<Platba[]> {
  const doDne = denPraha(new Date());
  const od = denPraha(new Date(Date.now() - dni * 86400000));
  const res = await fetch(`${FIO_API}/periods/${encodeURIComponent(token)}/${od}/${doDne}/transactions.json`);
  if (res.status === 409) throw new Error("Banka dotaz odmítla — mezi dvěma staženími musí být aspoň 30 s. Zkuste to za chvíli.");
  if (res.status === 401 || res.status === 404 || res.status === 500) {
    throw new Error(`Banka token nepřijala (HTTP ${res.status}). Platnost tokenu Fio je nejvýš 180 dní — vytvořte nový v internetovém bankovnictví.`);
  }
  if (!res.ok) throw new Error(`Banka vrátila chybu HTTP ${res.status}.`);
  const data = await res.json();
  const tx: Record<string, { value: unknown } | null>[] = data?.accountStatement?.transactionList?.transaction ?? [];
  const out: Platba[] = [];
  for (const t of tx) {
    const castka = Number(sloupec(t, 1));
    const mena = text(sloupec(t, 14)) || "CZK";
    const typ = text(sloupec(t, 8)).toLowerCase();
    const datum = fioDatum(sloupec(t, 0));
    const id = text(sloupec(t, 22));
    if (!(castka > 0) || mena !== "CZK" || !datum || !id || typ.includes("úrok")) continue;   // jen příchozí platby
    const ucet = text(sloupec(t, 2)), banka = text(sloupec(t, 3));
    out.push({
      datum,
      castka: Math.round(castka * 100) / 100,
      vs: text(sloupec(t, 5)).replace(/\D/g, "").slice(0, 10),
      protiucet: ucet ? (banka ? `${ucet}/${banka}` : ucet) : "",
      nazev: text(sloupec(t, 10)) || text(sloupec(t, 7)),
      zprava: text(sloupec(t, 16)),
      doklad: "fio:" + id,
    });
  }
  return out;
}

async function synchronizuj(sb: SupabaseClient, n: Napojeni) {
  try {
    const platby = n.banka === "fio" ? await stahniFio(n.token, n.stahovat_dni) : [];
    const { data, error } = await sb.rpc("banka_zpracuj", { p_skola: n.skola_id, p_platby: platby });
    if (error) throw new Error(error.message);
    return { skola: n.skola_id, ok: true, stazeno: platby.length, vysledek: data };
  } catch (e) {
    const chyba = e instanceof Error ? e.message : String(e);
    await sb.rpc("banka_zpracuj", { p_skola: n.skola_id, p_platby: null, p_chyba: chyba });
    return { skola: n.skola_id, ok: false, chyba };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ chyba: "Použijte POST." }, 405);

  const sluzba = createClient(URL_SB, SERVICE, { auth: { persistSession: false } });
  let skola: string | null = null;

  const cron = req.headers.get("x-cron-secret");
  if (CRON_SECRET && cron && cron === CRON_SECRET) {
    skola = null;   // všechny školky
  } else {
    // ruční spuštění z ředitelny: ověřit uživatele a jeho právo na platby
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ chyba: "Chybí přihlášení." }, 401);
    const uzivatel = createClient(URL_SB, ANON, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data, error } = await uzivatel.rpc("muze_stahnout_z_banky");
    if (error || !data) return json({ chyba: "Platby z banky načítá vedení nebo hospodářka." }, 403);
    skola = data as string;
  }

  const { data: napojeni, error } = await sluzba.rpc("banka_ke_stazeni", { p_skola: skola });
  if (error) return json({ chyba: error.message }, 500);
  if (skola && !(napojeni ?? []).length) return json({ chyba: "Školka nemá zapnuté napojení banky." }, 400);

  const vysledky = [];
  for (const n of (napojeni ?? []) as Napojeni[]) vysledky.push(await synchronizuj(sluzba, n));   // postupně, každá školka má vlastní token
  return json(skola ? vysledky[0] : { skolek: vysledky.length, vysledky });
});
