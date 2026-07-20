# Lokale FSC-harness — directory + consumer-peer uitvraag-org

Runnable shift-left van de ZAD-deploy: een lokale FSC-directory + de peer `uitvraag-org`
(manager + outway + inway + controller + txlog + eigen DB's) + een SNI-router op `:443`. Bewijst dat
`uitvraag-org` zich aanmeldt (announce) bij de directory. Geen aangeboden dienst, geen
OIDC-login-voorziening — control-plane-only voor deze ene peer. Bouwt voort op `pki/`
(zie dat README voor het cert-contract).

> **Vereist Docker + `docker compose` (v2) en gegenereerde certs** (`pki/issue.sh`, vereist
> `cfssl`). Draai eerst de PKI in `pki/`, dan de stack + smoke hieronder.

## Benodigdheden

- **Docker** + `docker compose` (v2). De eerste `up` bouwt de `manager-migrate`-wrapper lokaal
  uit `deploy/zad/manager-migrate` (FROM de stock multi-arch manager-image) — dus geen
  amd64-only ghcr-image; werkt ook op Apple Silicon.
- Gegenereerde certs uit `pki/` — draai daar eerst `./init-ca.sh`, `./issue.sh` en
  `./verify.sh` (zie `pki/README.md`, sectie "Uitvoeren"). Zonder certs faalt elke
  container die `/pki` mount bij boot (ontbrekend bestand).

## Draaiboek

Alle commando's vanuit de **repo-root**.

```bash
# 1. Genereer de PKI voor uitvraag-org (zie pki/README.md).
cd pki
./init-ca.sh
./issue.sh
./verify.sh          # verwacht: "== ALLE ASSERTS GROEN =="
cd -

# 2. Harness-env. De cert-lezende containers draaien als JOUW UID/GID, zodat ze de
#    0600-privékeys via de owner-bit lezen (keys blijven dicht).
cp deploy/local/.env.example deploy/local/.env
printf 'HOST_UID=%s\nHOST_GID=%s\n' "$(id -u)" "$(id -g)" >> deploy/local/.env

# 3. Start de stack.
docker compose -f deploy/local/docker-compose.yaml up -d
sleep 20 && docker compose -f deploy/local/docker-compose.yaml ps

# 4. Draai de smoke.
./deploy/local/run-smokes.sh    # verwacht: "ALLE SMOKES GROEN."
```

Losse smoke (voor gerichte diagnose):

```bash
./deploy/local/smoke-announce.sh    # verwacht: "OK: uitvraag-org is aangemeld ..."
```

Opruimen:

```bash
docker compose -f deploy/local/docker-compose.yaml down -v
```

> **Hosts-bestand niet nodig.** De SNI-hostnames (`directory.fsc-test.local`,
> `uitvraag-org.fsc-test.local`, `inway.uitvraag-org.fsc-test.local`) resolven *binnen* het
> docker-netwerk via de router-aliases. De UIs benader je via `localhost`-poorten hieronder.

## Wat er opkomt

- **postgres** — één instantie, per component een eigen database (`postgres-init.sql`):
  `fsc_directory`, `fsc_uitvraag_org`, `fsc_controller_uitvraag_org`, `fsc_txlog_uitvraag_org`.
- **router** (haproxy) — SNI-passthrough op `:443` naar `manager-directory` en
  `manager-uitvraag-org`.
- **manager-directory** + **directory-ui** (`http://localhost:8080`, geen login) — de lokale
  FSC-directory (`AUTO_SIGN_GRANTS=servicePublication,delegatedServicePublication`).
- **migrate-uitvraag-org**, **manager-uitvraag-org** — de manager van de peer (announce, token- en
  contractendpoints).
- **migrate-controller-uitvraag-org**, **controller-uitvraag-org** (`http://localhost:8090`, zonder
  login: `AUTHN_TYPE=none`) — dienst-beheer (contract-publicatie, delegatie).
- **migrate-txlog-uitvraag-org**, **txlog-uitvraag-org** — transactielog-API van de peer
  (internal-PKI-mTLS).
- **outway-uitvraag-org** — client-egress: leest z'n contract-/service-config van de eigen
  manager (internal-authenticated `:9443`) en logt uitgaande transacties bij txlog. Geen inbound
  SNI-route (geen aangeboden dienst).
- **inway-uitvraag-org** — ingress-proxy: registreert zich bij de eigen controller (`:9443`) en
  leest z'n config bij de eigen manager op de internal-**unauthenticated** poort (`:9444`) —
  bewust anders dan de outway (zie `CLAUDE.md`, "inway vs outway: verschillende manager-poort").
  Eigen SNI-route op de router (`inway.uitvraag-org.fsc-test.local`). Biedt (nog) geen dienst aan:
  er is geen `CreateService` gedaan.
- **toolbox** — curl-client op het netwerk voor mTLS-onboarding-calls (niet gebruikt door deze
  announce-only-proof, maar beschikbaar voor gerichte diagnose).

Geen aangeboden-dienst-onboarding, geen OIDC-login-voorziening — beide zijn buiten scope voor
deze announce-proof. De inway draait wel (mesh-ingress + registratie), maar biedt nog geen dienst
aan.

## Smoke

| Script | Bewijst |
|--------|---------|
| `smoke-announce.sh` | `uitvraag-org` (OIN `00000000000000000020`) staat in `peers.peers` met een `manager_address` op `:443`. |
| `run-smokes.sh` | Draait `smoke-announce.sh`. |

Announce-only: er is (nog) geen dienst-publicatie of discovery-smoke — de inway draait wel, maar
er is nog geen `CreateService` gedaan, dus er valt nog niets te discoveren of aan te roepen.

## Troubleshooting

- **Container kan cert niet vinden** → controleer dat `pki/out/uitvraag-org/<endpoint>/` en
  `pki/internal/uitvraag-org/<endpoint>/` bestaan (na `./pki/issue.sh`); paden moeten
  matchen met de compose-env.
- **`permission denied` op `key.pem` bij boot** → `HOST_UID`/`HOST_GID` in
  `deploy/local/.env` matchen niet met de eigenaar van de keys. Zet ze met
  `printf 'HOST_UID=%s\nHOST_GID=%s\n' "$(id -u)" "$(id -g)" >> deploy/local/.env` en
  `docker compose -f deploy/local/docker-compose.yaml up -d --force-recreate`.
- **Poort bezet** (443, 8080, 8090) → stop de conflicterende dienst of pas de `ports`/`bind`
  in `docker-compose.yaml` / `haproxy.cfg` aan.
- **Smoke faalt** → `docker compose -f deploy/local/docker-compose.yaml logs
  manager-directory manager-uitvraag-org controller-uitvraag-org` voor de mesh-logs.
- **`migrate-*` hangt / `database "…" does not exist`** → `postgres-init.sql` draait alleen bij
  een **vers** volume. Bestaat er al een postgres-volume van een eerdere run? Maak de ontbrekende
  DB eenmalig aan (`... exec -T postgres psql -U postgres -c "CREATE DATABASE <naam>;"`) of
  `down -v && up -d` (wist alles, re-init inclusief nieuwe DB's).

## Cert-contract (referentie, overgenomen uit `pki/README.md`)

De harness mount `pki/` read-only op `/pki`. Per endpoint (`manager`, `controller`, `outway`,
`inway`, `txlog`) twee ketens:

| Pad | Doel | Env |
|-----|------|-----|
| `/pki/ca/root.pem` | group-CA root (trust-anchor) | `TLS_GROUP_ROOT_CERT` |
| `/pki/internal/<peer>/ca/root.pem` | **per-peer** internal-CA root | `TLS_ROOT_CERT`, `TLS_INTERNAL_UNAUTHENTICATED_ROOT_CERT` |
| `/pki/out/<peer>/<endpoint>/{cert,key}.pem` | group-identity (hergebruikt voor token+contract) | `TLS_GROUP_CERT/KEY`, `TLS_GROUP_TOKEN_*`, `TLS_GROUP_CONTRACT_*` |
| `/pki/internal/<peer>/<endpoint>/{cert,key}.pem` | internal mTLS | `TLS_CERT/KEY`, `TLS_INTERNAL_UNAUTHENTICATED_*` |

`<peer>` ∈ {`directory`, `uitvraag-org`}. De mesh verifieert de hostname niet (auth op OIN), maar
houd de paden consistent met `SELF_ADDRESS`/SNI.

De directory-peer heeft eigen CSR's onder `pki/peers/directory/`: `directory/csr.json`
(gebruikt door `manager-directory` én `directory-ui` via `/pki/{out,internal}/directory/directory/...`)
en `manager/csr.json` (scaffolding voor een latere ZAD-directory-deploy; de lokale compose wiret
het niet). Beide dragen de directory-OIN `00000000000000000010`. `issue.sh` negeert ongebruikte
endpoints, dus de extra `manager`-CSR is onschadelijk.

> **Let op:** de certs ontbreken tot `pki/issue.sh` gedraaid is (vereist `cfssl`). Zonder
> gegenereerde certs faalt stap 1 van het draaiboek — genereer ze eerst.
