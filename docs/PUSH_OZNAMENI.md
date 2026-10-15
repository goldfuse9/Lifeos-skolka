# Push oznámení do LifeOS (i při zavřené aplikaci)

Databáze školky sama řadí oznámení rodičům do fronty `push_fronta` — při nové
zprávě od školky, nové akci nebo třídní schůzce, zveřejněném albu fotek a
zápisu učitelky (teplota, úraz…). Odesílá je rozšíření **pg_net** přímo na
Expo Push API; žádný vlastní server ani tajné klíče v aplikaci.
Na zamčené obrazovce je jen obecný text (u zápisu učitelky žádné hodnoty).

Dokud není vše níže hotové, LifeOS dál ukazuje **místní** oznámení při
stažení (otevření aplikace, návrat do ní, každých 5 minut, když běží).
Jakmile telefon dostane push token a server push posílá (`push_aktivni()`),
místní oznámení o stejných věcech se vypnou, aby nepřišla dvakrát.

## Co je potřeba nastavit

1. **Supabase**
   - spustit `supabase/migrace-2026-10-15i-push.sql`
   - Database → Extensions → zapnout **pg_net** (migrace se o to pokusí sama)
2. **Apple** — push na iPhonu jde jen s placeným účtem Apple Developer Program
   (osobní bezplatný tým push oprávnění podepsat neumí).
3. **Expo** (projekt LifeOS už má `projectId` v `app.json`)
   - `npx eas credentials` → iOS → Push Notifications: nechat Expo vytvořit
     a uložit APNs klíč (nebo nahrát vlastní .p8)
   - Android: podle návodu Expo nahrát FCM klíč (Firebase)
4. **Sestavení LifeOS s push oprávněním**
   `LIFEOS_PUSH=1 npx expo run:ios --device --configuration Release`
   (bez `LIFEOS_PUSH=1` se push oprávnění z aplikace odstraní — jako dosud)

## Kontrola

- v Supabase: `select * from push_tokeny;` — po otevření LifeOS rodičem tu je token
- po nové zprávě: `select token, text, odeslano, vysledek from push_fronta order by id desc limit 5;`
  `odeslano` vyplněné = odešlo na Expo; odpovědi Expo jsou v `net._http_response`
