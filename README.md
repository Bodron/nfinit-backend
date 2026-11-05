# Nfinit backend

Backend standalone pentru jocul Nfinit: **Node.js 24**, **WebSocket**, **MongoDB
Atlas în cloud**, co-op pentru doi jucători și backupul complet al campionilor.
Repository-ul conține numai serverul, motorul de simulare și testele sale.
Nu include aplicația Flutter, imagini, builduri, fișiere `.env` sau credențiale.

## Pornire

Ai nevoie de Node.js 24+ și Dart 3.13.5+. Alternativ, folosește Docker.
Nu ai nevoie de Flutter sau de repository-ul aplicației.

```sh
npm ci
cp config.example .env
# Completează MONGODB_URI cu URI-ul tău MongoDB Atlas.
# Dacă dart nu este în PATH, setează DART_BIN.
npm run check:atlas
npm run build:engine
npm start
```

Copiază exemplul numai dacă nu ai deja `.env`; păstrează configurația existentă.
`config.example` conține exclusiv valori fictive. `.env` este ignorat de Git și
Docker. În producție poți seta variabilele direct în platforma de găzduire.
Nu publica URI-ul MongoDB și nu îl pune în aplicația mobilă.

`npm run check:atlas` verifică prin ping conexiunea la Atlas, fără să afișeze
credențiale sau să introducă documente de test. Serverul de producție folosește
exclusiv MongoDB-ul indicat de `MONGODB_URI`; nu pornește o bază locală și nu
folosește stocarea temporară din teste ca fallback.

```sh
curl http://localhost:8081/healthz
curl http://localhost:8081/readyz
```

`healthz` verifică procesul HTTP; `readyz` verifică MongoDB și motorul co-op.
În Atlas permite IP-ul hostului și folosește un database user cu read/write.
Contul cu care intri pe site-ul Atlas este diferit de utilizatorul bazei.
Parola din URI trebuie codificată corect dacă include caractere speciale.

## Docker și găzduire

Din rădăcina acestui repository, după configurarea `.env`:

```sh
docker compose up --build -d
docker compose logs -f backend
```

Sau:

```sh
docker build -t nfinit-backend .
docker run --env-file .env -p 8081:8081 nfinit-backend
```

Compose pornește numai serviciul backend. MongoDB rămâne în Atlas; nu există
container MongoDB local. Dockerfile-ul include Node și motorul Dart compilat.

Folosește o singură replică a serviciului pe un host cu procese permanente și
suport WebSocket. Expune HTTPS/WSS prin platformă sau reverse proxy. Camerele
active sunt în RAM, iar progresul și rezultatele sunt în MongoDB. Un restart
al serverului încheie partidele active; reconectarea clientului acoperă
întreruperile de rețea, nu restaurarea simulării după restart.

În joc setează URL-ul API-ului, de exemplu `https://api.example.com`, în
**Settings → Champion Saves**. Pentru co-op folosește
`wss://api.example.com/ws`. Pe telefon, localhost înseamnă telefonul, nu
calculatorul care rulează serverul. Clientul mobil nu se conectează direct la
MongoDB. Pentru Flutter Web adaugă originile exacte în `ALLOWED_ORIGINS`.

## Co-op

Primul jucător creează camera și trimite codul de cinci caractere prietenului.
Gazda poate începe numai când sunt conectați exact doi campioni.

- Fiecare campion are propriile skilluri și cooldown-uri; nu există friendly fire.
- Monștrii au 1,65× HP. Ambii jucători primesc valoarea întreagă a lootului
  colectat o singură dată; lovitura finală determină cine primește eliminarea.
- Un campion la 0 HP cade. Revine cu 40% HP la următorul wave dacă partenerul
  supraviețuiește. Partida se termină dacă ambii cad.
- La pierderea conexiunii, jocul se oprește pentru ambii și rezervă locul timp
  de `RECONNECT_GRACE_SECONDS`, implicit 30 de secunde.
- Clientul trimite comenzi, iar serverul calculează mișcarea, skillurile,
  damage-ul, wave-urile și recompensele. Nu acceptă HP/XP/wave declarate de client.
- Partidele co-op folosesc echipamentul de bază. Progresul solo salvat în cloud
  nu acordă upgrade-uri în simularea co-op și nu modifică statisticile autoritare.

Simularea rulează într-un proces Dart, folosind aceleași reguli ca jocul.
`engine/lib/` conține cele 38 de surse Dart pure necesare serverului, fără UI
sau dependențe Flutter. `engine/sources.json` verifică integritatea lor.
În checkout-ul jocului, `npm run sync:engine` actualizează această copie din
sursele comune; în acest repository standalone verifică sursele incluse.
`npm run build:engine` face automat acest pas înaintea compilării.

## MongoDB Atlas și progres

- `players`: profil guest, hash SHA-256 al tokenului și totaluri co-op.
- `coop_matches`: participanții și rezultatele calculate de server.
- `player_progress`: backupul complet al campionilor solo, revizie, ultimele
  trei versiuni și ultimele 32 de confirmări idempotente.

Aplicația salvează întâi progresul într-o bază locală pe dispozitiv și trimite
backupul când backendul devine accesibil. Acest repository conține partea cloud.
Snapshotul include toți campionii, XP, arme, upgrade-uri, esență, campanie,
checkpoint-uri, Journey, recorduri și preferințe. JSON-urile campionilor sunt
păstrate ca șiruri pentru a conserva exact valorile mari.

Uploadul folosește compare-and-set pe revizie și un ID de request. Un retry
nu dublează salvarea; o versiune concurentă produce HTTP 409, fără suprascriere
automată. Clientul oferă alegerea versiunii și păstrează backupul celeilalte.
MongoDB confirmă scrierile cu `majority`. Statisticile co-op rămân separate de
backupul solo. Rezultatul și totalurile celor doi jucători sunt actualizate
în aceeași tranzacție MongoDB, idempotent, după ID-ul partidei.

Identitatea este momentan guest. Tokenul aleator este păstrat pe dispozitiv;
în MongoDB se salvează doar hashul lui. Nu distribui tokenul prietenului,
ci doar codul camerei. Nu există încă login cu email/Apple/Google pentru
recuperarea automată după ștergerea datelor aplicației.

Dacă MongoDB devine indisponibil, rezultatele co-op intră în coada de retry a
procesului, iar rematch-ul așteaptă confirmarea. Acea coadă este în RAM: un
crash înainte de commit poate pierde un rezultat. Outboxul backupului solo
este durabil în aplicația mobilă și se reîncearcă după restartul ei.

## API

Endpointurile de profil și progres cer `Authorization: Bearer TOKEN`.
Un profil poate citi sau modifica numai propriile date.

| Endpoint | Rol |
|---|---|
| `GET /healthz`, `GET /health` | Starea procesului |
| `GET /readyz` | Disponibilitatea Atlas și a motorului |
| `POST /api/session` | Creează profil guest; body `{"name":"Nyx"}` |
| `GET /api/me` | Profil și totaluri co-op |
| `GET /api/matches` | Ultimele 20 de partide |
| `GET /api/progress` | `{progress: {revision, document, updatedAt}}` |
| `PUT /api/progress` | `{baseRevision, mutationId, document}` |

Documentul de progres are schema `{schemaVersion: 1, values: {...}}`, maximum
256 KiB. `mutationId` are 48 de caractere hex. Succesul întoarce
`{accepted: true, revision}`; conflictul întoarce HTTP 409 cu
`{accepted: false, progress: {...}}`. Pentru un profil fără backup,
`revision` este 0 și `document` este null. Tokenurile nu sunt incluse în snapshot.

WebSocket `/ws` primește `join`, `start`, `move`, `voice`, `action` și `leave`.
Emite `identity`, `state` (20 Hz), `error`, `matchSaved` și `roomClosed`.
Mesajele au maximum 4 KiB și sunt limitate la 140 mesaje/secundă/client.

```json
{"type":"join","name":"Nyx","skin":0,"code":""}
{"type":"join","name":"Brum","skin":2,"code":"ABCDE","token":"TOKEN_SALVAT"}
{"type":"start"}
{"type":"move","dx":0.7,"dy":-0.7}
{"type":"action","action":"skill:0"}
{"type":"leave"}
```

## Testare

```sh
npm run build:engine
npm test
npm run test:mongo
```

Testele normale folosesc stocare în memorie injectată explicit și clienți reali
HTTP/WebSocket. Testul `test:mongo` pornește exclusiv pentru test un replica set
MongoDB local temporar; nu citește `.env` și nu scrie în Atlas. Nu există MongoDB
local în pornirea normală sau în Docker Compose.

Dockerfile-ul este pregătit pentru repository standalone; verificarea locală
necesită un daemon Docker pornit. Nu publica `.env`, chei private sau datele
jucătorilor. `.gitignore` și `.dockerignore` exclud aceste fișiere.
