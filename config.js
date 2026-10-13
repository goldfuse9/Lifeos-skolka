/* Připojení k serveru (Supabase). Publishable klíč je veřejný — smí být
   v aplikaci; práva hlídá databáze (RLS). Tajný (secret / service_role)
   klíč sem nikdy nepatří. Bez tohoto souboru (nebo s url: '') běží
   aplikace ve zkušebním provozu s ukázkovými daty v prohlížeči. */
window.SKOLKA_SERVER = {
  url: 'https://jokprqoifzjojbpozefh.supabase.co',
  key: 'sb_publishable_rBPacvhihkerELrGfAweQg_BYGtccLI',
};
