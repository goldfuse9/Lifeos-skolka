// Napodobené Fio API: token „DOBRY…“ vrátí pohyby, cokoli jiného HTTP 500.
const tx = (o: Record<number, unknown>) => Object.fromEntries(Object.entries(o).map(([k, v]) => ["column" + k, v == null ? null : { value: v, id: +k }]));
Deno.serve({ port: 3010 }, (req) => {
  const u = new URL(req.url);
  console.error("FIO", u.pathname.replace(/periods\/[^/]+/, "periods/<token>"));
  if (!u.pathname.includes("/periods/DOBRY")) return new Response("", { status: 500 });
  const body = { accountStatement: { info: {}, transactionList: { transaction: [
    tx({ 0: "2026-10-15+0200", 1: 900, 2: "123-456", 3: "0100", 5: "260001", 8: "Bezhotovostní příjem", 10: "TESTOVA JANA", 14: "CZK", 22: 2001 }),
    tx({ 0: 1760565600000, 1: 500, 2: "222", 3: "0300", 5: null, 8: "Bezhotovostní příjem", 10: "ZKUSEBNI", 14: "CZK", 16: "skolkovne VS 250002", 22: 2002 }),
    tx({ 0: "2026-10-16+0200", 1: -1200, 2: "999", 3: "0800", 5: "1", 8: "Bezhotovostní platba", 14: "CZK", 22: 2003 }),
    tx({ 0: "2026-10-16+0200", 1: 3.12, 8: "Připsaný úrok", 14: "CZK", 22: 2004 }),
    tx({ 0: "2026-10-16+0200", 1: 40, 2: "DE123", 5: "260003", 8: "Bezhotovostní příjem", 14: "EUR", 22: 2005 }),
    tx({ 0: "2026-10-16+0200", 1: 77, 2: "444", 3: "0800", 5: "999999", 8: "Bezhotovostní příjem", 10: "NEZNAMY", 14: "CZK", 22: 2006 }),
  ] } } };
  return Response.json(body);
});
