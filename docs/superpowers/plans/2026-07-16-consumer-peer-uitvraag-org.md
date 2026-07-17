# FSC consumer-peer `uitvraag-org` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Een FSC consumer-peer `uitvraag-org` (OIN `00000000000000000020`) opzetten in `moza-fsc-testconsumer` — PKI + lokale announce-proof + ZAD-deploy + CI — als getrouwe spiegel van de provider-peer in `moza-fsc-org-a`.

**Architecture:** Deze repo is een deploy-/configuratie-repo die OpenFSC-container-images (`v1.43.7`) consumeert. De peer bestaat uit **manager + outway + controller + txlog + postgres**. Elk bestand is óf een verbatim-kopie uit `../moza-fsc-org-a`, óf een kopie met een afgebakende consumer-aanpassing (inway→outway, `magazijn-a`→`uitvraag-org`, `mgz*`→`uvr*`, geen service-publicatie). Zie `docs/design.md` voor de ontwerprationale.

**Tech Stack:** OpenFSC images (`federatedserviceconnectivity/{manager,outway,controller,txlog-api,directory-ui}`), docker-compose, HAProxy (SNI-passthrough), CFSSL (test-PKI), Postgres 17, bash-scripts, ZAD v2 Operations Manager API, GitHub Actions.

## Global Constraints

- **Bronrepo (voorbeeld):** `../moza-fsc-org-a` — checkout naast deze repo. "Kopieer X" = `cp ../moza-fsc-org-a/X ./X` tenzij anders vermeld.
- **Peer-identiteit (lockstep in álle csr's + adressen):** naam `uitvraag-org` (`subject.O`), OIN `00000000000000000020` (`subject.serialNumber`).
- **Group ID** `moza-fbs-test`; **directory-OIN** `00000000000000000010`.
- **Endpoints** (PKI + componenten): `manager`, `outway`, `controller`, `txlog`. **Géén** `inway`.
- **ZAD-component-prefix** `uvr*`: `uvrmgr` (manager), `uvrout` (outway), `uvrctl` (controller), `uvrtxlog` (txlog), `uvrpg` (postgres).
- **FSC-image-pin** `v1.43.7`. Migrate-wrappers: `ghcr.io/minbzk/moza-fsc-testnet/{manager,controller,txlog}-migrate:<tag>`.
- **ZAD-project + API-key-secret** zijn placeholders (`__ZAD_PROJECT__`, secret `ZAD_API_KEY_FSCUITVRAAG`) — worden later ingevuld; niet blokkerend voor `plan`.
- **Secrets/keys/certs nooit committen** — alleen scripts, CA-configs, `csr.json`'s en `.example`-templates (`.gitignore`).
- **Lokaal geen Docker/cfssl gegarandeerd:** statische checks (`bash -n`, `jq`, `yamllint`) draaien lokaal; de volledige compose-smoke + `pki/issue.sh` draaien host-side (Task 8).
- **Git:** werk op branch `feature/consumer-peer-uitvraag-org`. Nooit direct naar `main`. Geen reviewer op de PR, geen auto-close-keyword (`Closes #N`) in de PR-body.
- **Commit-trailer:** `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Alle `git mv`/edits t.o.v. een verbatim-kopie:** bekijk de diff vóór commit; drift t.o.v. org-a moet bewust zijn.

---

### Task 1: Top-level scaffolding

**Files:**
- Create (verbatim uit org-a): `DISCLAIMER.md`, `LICENSE`, `SECURITY.md`, `SUPPORT.md`, `.markdownlint.yaml`, `.yamllint.yaml`, `.gitignore`
- Create (aangepast): `README.md`, `CLAUDE.md`

**Interfaces:**
- Produces: repo-conventies (Dutch, EUPL, secret-hygiene) + `.gitignore`-paden (`pki/ca`, `pki/out`, `pki/internal`, `pki/zad-upload`, `deploy/local/.env`) waar Task 2/3 op leunen.

- [ ] **Step 1: Kopieer de verbatim top-level bestanden**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in DISCLAIMER.md LICENSE SECURITY.md SUPPORT.md .markdownlint.yaml .yamllint.yaml .gitignore; do
  cp "../moza-fsc-org-a/$f" "./$f"
done
```

- [ ] **Step 2: Controleer dat `.gitignore` de PKI-secrets + `.env` dekt**

Run: `grep -E 'pki/(ca|out|internal|zad-upload)|deploy/local/.env' .gitignore`
Expected: alle vijf paden aanwezig (peer-agnostisch — geen aanpassing nodig).

- [ ] **Step 3: Schrijf `README.md`** (consumer-variant; vervang de provider-README)

```markdown
# Uitvraag-org — FSC consumer-peer

Een **FSC consumer-peer** voor de uitvraag-organisatie die als **afnemer** aansluit op de
FSC-federatie van [`moza-fsc-testnet`](https://github.com/MinBZK/moza-fsc-testnet) (repo A — de
directory + group-CA) en straks via een lokale **outway** de dienst `berichtenmagazijn` bij
magazijn-a aanroept. De peer bestaat uit de standaard OpenFSC-componenten
**manager + outway + controller + txlog** met een eigen managed Postgres, co-located met de
achterliggende uitvraag-app.

Gemodelleerd naar de provider-peer in
[`moza-fsc-org-a`](https://github.com/MinBZK/moza-fsc-org-a); deze repo bevat uitsluitend FSC-infra
(PKI + deploy), niet de uitvraag-applicatie zelf.

> **Niet voor productie.** Test-PKI en test-federatie (`moza-fbs-test`). Sleutels/certs horen
> **niet** in git — zie `.gitignore`.

## Identiteit

| Parameter | Waarde |
|-----------|--------|
| Peer-naam | `uitvraag-org` |
| Peer-OIN (= Peer ID) | `00000000000000000020` |
| Group ID | `moza-fbs-test` |
| Directory-OIN | `00000000000000000010` |
| Componenten | manager + outway + controller + txlog + postgres |
| FSC-images (pin) | `v1.43.7` |

## Structuur

| Pad | Rol |
|-----|-----|
| `pki/` | Test-PKI: group- + internal-certs per endpoint (cfssl). Zie `pki/README.md`. |
| `deploy/local/` | Lokale docker-compose-proof: directory + consumer-peer + SNI-router + announce-smoke. |
| `deploy/zad/` | ZAD-rollout (Operations Manager v2-API): `upsert-peer.sh` + cert-/verificatie-runbooks. |
| `.github/workflows/zad-deploy-peer.yml` | Deployt de peer naar ZAD (plan op PR, apply op main). |
| `docs/design.md` | Ontwerp + scope. |

## Quickstart

### 1. PKI — group-CA van het testnet + certs uitgeven

```bash
cd pki
# (voor de lokale proof: ./init-ca.sh   — eigen CA)
./issue.sh          # group- + internal-cert per endpoint
./gen-crl.sh        # lege CRL
./verify.sh         # acceptatie-asserts (exit 0 = groen)
./zad-bundle.sh uitvraag-org   # upload-klare set in pki/zad-upload/uitvraag-org/
```

### 2. Lokale compose-proof (announce-only)

```bash
cd deploy/local
cp .env.example .env      # vul PKI_DIR + HOST_UID/GID
docker compose up -d
./run-smokes.sh           # announce
```

### 3. ZAD

Zie `deploy/zad/README.md`. Kort: eigen ZAD-project (later invullen) + eigen API-key
(secret `ZAD_API_KEY_FSCUITVRAAG`); `upsert-peer.sh` beheert deployment + componenten + images;
cert-attachments + "Publicatie op het web" zijn UI-only.

## Licentie

[EUPL v1.2](LICENSE).
```

- [ ] **Step 4: Schrijf `CLAUDE.md`** (kopieer org-a's `CLAUDE.md` en pas de consumer-delen aan)

Kopieer eerst: `cp ../moza-fsc-org-a/CLAUDE.md ./CLAUDE.md`. Pas daarna deze punten aan (de rest — taalregels, git-werkwijze, CI, conventies — blijft identiek):

- Titel/Project-sectie: "**uitvraag-org-fsc-peer** — de **FSC consumer-peer** … die als afnemer aansluit …". Verwijs naar `moza-fsc-org-a` (provider) i.p.v. andersom.
- Idioom-lijst: voeg `outway` toe; `inway` mag blijven staan als algemeen idioom.
- "Wat dit wel/niet is": images `manager`, `outway`, `controller`, `txlog-api` (i.p.v. inway); de **outway** heeft geen DB en gebruikt het stock-image.
- Identiteit-tabel: naam `uitvraag-org`, OIN `00000000000000000020`, ZAD-project _placeholder_, endpoints `manager/outway/controller/txlog`.
- Kernbeslissingen + ZAD-lessen: vervang overal `magazijn-a`→`uitvraag-org`, `mgz*`→`uvr*`, `inway`→`outway`; verwijder de "dienst publiceren / CreateService / AUTO_SIGN"-passages (consumer publiceert niet). Behoud de txlog-, cert-mount-, multi-poort- en self-hosted-Postgres-lessen 1:1.

- [ ] **Step 5: Statische check + commit**

Run: `yamllint .yamllint.yaml .markdownlint.yaml 2>/dev/null; echo "lint-exit=$?"` (yamllint niet aanwezig → sla over; CI dekt het)
Run: `test -s README.md && test -s CLAUDE.md && test -s LICENSE && echo "files OK"`
Expected: `files OK`.

```bash
git add README.md CLAUDE.md DISCLAIMER.md LICENSE SECURITY.md SUPPORT.md .markdownlint.yaml .yamllint.yaml .gitignore
git commit -m "chore: top-level scaffolding consumer-peer uitvraag-org (#781)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: PKI-laag (CA-configs + scripts + directory-csr's verbatim; `gen-csr.sh` aangepast)

**Files:**
- Create (verbatim uit org-a): `pki/config.json`, `pki/ca.json`, `pki/intermediate.json`, `pki/internal-ca.json`, `pki/init-ca.sh`, `pki/gen-crl.sh`, `pki/issue.sh`, `pki/verify.sh`, `pki/zad-bundle.sh`, `pki/combine-pem.sh`, `pki/fix-permissions.sh`, `pki/peers/directory/directory/csr.json`, `pki/peers/directory/manager/csr.json`
- Create (aangepast): `pki/gen-csr.sh`, `pki/README.md`
- Generated + gecommit: `pki/peers/uitvraag-org/{manager,outway,controller,txlog}/csr.json`

**Interfaces:**
- Consumes: `.gitignore` (Task 1) — `pki/{ca,out,internal,zad-upload}` gitignored.
- Produces: na `issue.sh` → group-certs `pki/out/uitvraag-org/{manager,outway,controller,txlog}/{cert,key}.pem` + internal-certs `pki/internal/uitvraag-org/{ca,manager,outway,controller,txlog}/...`, geconsumeerd door de compose (Task 3) en de ZAD-bundle (Task 5). SAN's: `<endpoint>.uitvraag-org.fsc-test.local` (+ `uitvraag-org.fsc-test.local` op manager) + ZAD-mesh-host `<short>-<deployment>-<project>.<base-domain>` + Service-DNS `<deployment>-<short>`(`.<namespace>.svc.cluster.local`).

- [ ] **Step 1: Kopieer de peer-agnostische PKI-bestanden verbatim**

```bash
mkdir -p pki/peers/directory
for f in config.json ca.json intermediate.json internal-ca.json \
         init-ca.sh gen-crl.sh issue.sh verify.sh zad-bundle.sh combine-pem.sh fix-permissions.sh; do
  cp "../moza-fsc-org-a/pki/$f" "pki/$f"
done
cp -r ../moza-fsc-org-a/pki/peers/directory/. pki/peers/directory/
chmod +x pki/*.sh
```

- [ ] **Step 2: Verifieer dat `issue.sh`/`verify.sh`/`zad-bundle.sh` peer-agnostisch zijn**

Run: `grep -nE 'magazijn-a|mgz' pki/issue.sh pki/verify.sh pki/zad-bundle.sh pki/gen-crl.sh pki/init-ca.sh pki/combine-pem.sh pki/fix-permissions.sh`
Expected: geen treffers (deze scripts itereren over `peers/*/` en zijn niet peer-specifiek). Bij een treffer: die is peer-specifiek en hoort in `gen-csr.sh` te zitten — meld het, wijzig niet blind.

- [ ] **Step 3: Schrijf `pki/gen-csr.sh`** (kopieer org-a's versie en pas de identiteit + endpoints aan)

Begin met `cp ../moza-fsc-org-a/pki/gen-csr.sh pki/gen-csr.sh`, en pas exact deze regels aan:

De ZAD-topologie-defaults — zet `PROJECT` op de placeholder:
```bash
PROJECT="${ZAD_PROJECT:-__ZAD_PROJECT__}"
```

De peer-identiteit + endpoint-tabel:
```bash
PEER="uitvraag-org"
OIN="00000000000000000020"                                # = subject.serialNumber = Peer ID
# endpoint:component-korte-naam (de ZAD-component + Service heet `<deployment>-<short>`).
ENDPOINTS=( "manager:uvrmgr" "outway:uvrout" "controller:uvrctl" "txlog:uvrtxlog" )
```

Laat de rest (SAN-opbouw, jq-generatie, de `[ "${endpoint}" = manager ]`-tak die de kale
peer-FQDN toevoegt) ongewijzigd — die is endpoint-generiek.

- [ ] **Step 4: `bash -n` + genereer + valideer de csr's**

Run: `bash -n pki/gen-csr.sh && echo "syntax OK"`
Expected: `syntax OK`.
Run: `bash pki/gen-csr.sh`
Expected: vier regels `csr uitvraag-org/{manager,outway,controller,txlog}: ...` + `OK: csr.json's gegenereerd ...`.
Run: `for f in pki/peers/uitvraag-org/*/csr.json; do jq -e '.serialnumber=="00000000000000000020"' "$f" >/dev/null && echo "OK $f"; done`
Expected: vier `OK`-regels.
Run: `jq . pki/config.json pki/internal-ca.json pki/ca.json pki/intermediate.json >/dev/null && echo "json OK"`
Expected: `json OK`.

- [ ] **Step 5: (host-side, indien `cfssl` beschikbaar) issue + verify** — anders overslaan tot Task 8

Run: `command -v cfssl >/dev/null && (cd pki && ./init-ca.sh && ./issue.sh && ./gen-crl.sh && ./verify.sh) || echo "cfssl afwezig — uitgesteld naar Task 8"`
Expected: `== ALLE ASSERTS GROEN ==` (met cfssl) óf de uitstel-melding.

- [ ] **Step 6: Schrijf `pki/README.md`** (kopieer org-a's versie; vervang `magazijn-a`→`uitvraag-org`, endpoint-lijst `manager/controller/inway/txlog`→`manager/outway/controller/txlog`, OIN → `00000000000000000020`, en de `openssl`-voorbeeldregel naar `out/uitvraag-org/outway/cert.pem`). De GROUP/INTERNAL-uitleg + scripttabel blijven inhoudelijk gelijk.

- [ ] **Step 7: Commit** (alleen scripts + configs + csr-templates; `ca/`/`out/`/`internal/` zijn gitignored)

Run: `git status --porcelain pki | grep -E '\.(pem|key|crl)$' && echo "STOP: secrets zichtbaar" || echo "geen secrets"`
Expected: `geen secrets`.

```bash
git add pki/*.json pki/*.sh pki/README.md pki/peers/
git commit -m "feat(pki): consumer-peer uitvraag-org PKI (manager/outway/controller/txlog) (#781)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Lokale compose-proof (announce-only)

**Files:**
- Create: `deploy/local/postgres-init.sql`, `deploy/local/.env.example`, `deploy/local/haproxy.cfg`, `deploy/local/docker-compose.yaml`, `deploy/local/smoke-announce.sh`, `deploy/local/run-smokes.sh`, `deploy/local/README.md`

**Interfaces:**
- Consumes: certs uit Task 2 (`/pki/out/uitvraag-org/...`, `/pki/internal/uitvraag-org/...`, `/pki/out/directory/...`, `/pki/internal/directory/...`), `.env` (`PKI_DIR`, `HOST_UID/GID`).
- Produces: een draaiende stack (directory + consumer-peer) waarin de consumer-OIN `00000000000000000020` in de directory-DB `peers.peers` met `manager_address` op `:443` verschijnt.

- [ ] **Step 1: `.env.example` + `postgres-init.sql`**

```bash
cp ../moza-fsc-org-a/deploy/local/.env.example deploy/local/.env.example
```

Schrijf `deploy/local/postgres-init.sql`:
```sql
-- Eén postgres, per component een eigen database (spiegelt OpenFSC: manager en
-- controller delen geen DB — beide hebben een public.schema_migrations).
CREATE DATABASE fsc_directory;
CREATE DATABASE fsc_uitvraag_org;
CREATE DATABASE fsc_controller_uitvraag_org;
CREATE DATABASE fsc_txlog_uitvraag_org;
```

- [ ] **Step 2: `haproxy.cfg`** (kopieer org-a en vervang de peer-backends)

Begin met `cp ../moza-fsc-org-a/deploy/local/haproxy.cfg deploy/local/haproxy.cfg`. Vervang het `frontend`-`use_backend`-blok + de backends door (directory ongewijzigd; `magazijn-a`→`uitvraag-org`; **geen** inway-route — de outway is client):

```haproxy
frontend https_sni
    bind *:443
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    use_backend dir if { req_ssl_sni -i directory.fsc-test.local }
    use_backend uvr if { req_ssl_sni -i uitvraag-org.fsc-test.local }

backend dir
    server s1 manager-directory:8443
backend uvr
    server s1 manager-uitvraag-org:8443
```

De `global`/`resolvers docker`/`defaults`-secties blijven ongewijzigd. Verwijder de router-alias
`inway.magazijn-a.fsc-test.local` uit de compose (Step 3) — die hoort niet bij een consumer.

- [ ] **Step 3: `docker-compose.yaml`** (kopieer org-a en transformeer)

Begin met `cp ../moza-fsc-org-a/deploy/local/docker-compose.yaml deploy/local/docker-compose.yaml`. Voer deze transformaties uit:

1. **Header-comment:** "directory + consumer-peer uitvraag-org (manager/outway/controller/txlog)".
2. **`router.networks.default.aliases`:** houd `directory.fsc-test.local`; vervang `magazijn-a.fsc-test.local`→`uitvraag-org.fsc-test.local`; **verwijder** `inway.magazijn-a.fsc-test.local`.
3. **`manager-directory`:** ongewijzigd (blijft de lokale directory).
4. **`migrate-magazijn-a` → `migrate-uitvraag-org`:** DSN-DB `fsc_magazijn_a`→`fsc_uitvraag_org`.
5. **`manager-magazijn-a` → `manager-uitvraag-org`:** service-key + alle `magazijn-a`→`uitvraag-org` (SELF_ADDRESS, cert-paden `out/uitvraag-org/manager/*`, `internal/uitvraag-org/...`, DSN `fsc_uitvraag_org`, network-alias `manager.uitvraag-org.fsc-test.local`, anchor-namen `&uvr-grp`/`&uvr-int` i.p.v. `&mgz-*`). `CONTROLLER_REGISTRATION_API_ADDRESS`→`https://controller.uitvraag-org.fsc-test.local:9443`; `TX_LOG_API_ADDRESS`→`https://txlog.uitvraag-org.fsc-test.local:9443`. `depends_on`: `migrate-uitvraag-org` + `manager-directory`.
6. **`stub-upstream`:** **verwijderen** (geen aangeboden dienst).
7. **`inway-magazijn-a`:** **verwijderen**; vervang door `outway-uitvraag-org` (Step 4).
8. **`directory-ui`:** houd; `TLS_GROUP_CERT/KEY` → `out/uitvraag-org/manager/*` (lezer-peer-identiteit).
9. **`migrate-controller-magazijn-a` → `migrate-controller-uitvraag-org`** en **`controller-magazijn-a` → `controller-uitvraag-org`:** service-keys + alle `magazijn-a`→`uitvraag-org`; DSN-DB `fsc_controller_uitvraag_org`; host-poort blijft `127.0.0.1:8090:8080`; `MANAGER_ADDRESS_INTERNAL`→`https://manager.uitvraag-org.fsc-test.local:9443`; internal-cert-paden `internal/uitvraag-org/controller/*`; alias `controller.uitvraag-org.fsc-test.local`; `depends_on` → `migrate-controller-uitvraag-org` + `manager-uitvraag-org`.
10. **`toolbox`:** houd; `depends_on` → `manager-uitvraag-org` + `controller-uitvraag-org`.
11. **`migrate-txlog-magazijn-a` → `migrate-txlog-uitvraag-org`** en **`txlog-magazijn-a` → `txlog-uitvraag-org`:** service-keys + `magazijn-a`→`uitvraag-org`; DSN-DB `fsc_txlog_uitvraag_org`; internal-cert-paden `internal/uitvraag-org/txlog/*`; alias `txlog.uitvraag-org.fsc-test.local`.

Controleer na de sed-achtige vervangingen dat er nergens meer `magazijn-a`, `mgz`, `inway` of `stub-upstream` in het bestand staat (Step 5).

- [ ] **Step 4: Voeg de `outway-uitvraag-org`-service toe** (vervangt het verwijderde inway-blok; volledige inhoud)

```yaml
  outway-uitvraag-org:
    image: docker.io/federatedserviceconnectivity/outway:${IMAGE_TAG:-v1.43.7}
    user: "${HOST_UID:-1000}:${HOST_GID:-1000}"   # host-UID -> leest 0600-keys
    restart: on-failure                            # boot-race met de eigen manager
    command:
      - /usr/local/bin/outway
      - serve
    environment:
      LOG_TYPE: local
      LOG_LEVEL: debug
      GROUP_ID: moza-fbs-test
      NAME: uitvraag-org-outway
      SELF_ADDRESS: https://outway.uitvraag-org.fsc-test.local:443
      LISTEN_ADDRESS: 0.0.0.0:8443
      MONITORING_ADDRESS: 0.0.0.0:8081
      DISABLE_CRL_CHECKS: "true"
      # De outway leest z'n contract-/service-config van de eigen manager (internal-unauthenticated):
      MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS: https://manager.uitvraag-org.fsc-test.local:9444
      # Echte txlog-api (INTERNAL-PKI mTLS): bij egress logt de outway de transactie (direction: out).
      TX_LOG_API_ADDRESS: https://txlog.uitvraag-org.fsc-test.local:9443
      TLS_ROOT_CERT: /pki/internal/uitvraag-org/ca/root.pem
      TLS_CERT: /pki/internal/uitvraag-org/outway/cert.pem
      TLS_KEY: /pki/internal/uitvraag-org/outway/key.pem
      TLS_GROUP_ROOT_CERT: /pki/ca/root.pem
      TLS_GROUP_CERT: /pki/out/uitvraag-org/outway/cert.pem
      TLS_GROUP_KEY: /pki/out/uitvraag-org/outway/key.pem
    volumes:
      - "${PKI_DIR:?zet PKI_DIR in .env}:/pki:ro"
    networks:
      default:
        # Alias = de internal-cert-hostnaam; géén :443-router-route (de outway is client, geen ingress).
        aliases:
          - outway.uitvraag-org.fsc-test.local
    depends_on:
      manager-uitvraag-org:
        condition: service_started
      txlog-uitvraag-org:
        condition: service_started
```

> **Verifieer bij de eerste host-run (Task 8):** de exacte outway-env-namen (`LISTEN_ADDRESS`, `NAME`, `MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS`) tegen `docker run --rm federatedserviceconnectivity/outway:v1.43.7 /usr/local/bin/outway serve --help` of de OpenFSC `helm/charts`-outway-values. Cert-paden + hostnamen blijven gelijk; pas alleen env-sleutels aan als de image andere namen verwacht.
>
> **RESOLVED (na ZAD-deploy):** `fsc-outway serve` v1.43.7 eist `MANAGER_INTERNAL_ADDRESS` (authenticated, `:9443`) + `CONTROLLER_REGISTRATION_API_ADDRESS` (`:9443`) — níet `MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS`. De outway registreert zich dus, net als de inway, bij de controller. `upsert-peer.sh`/de compose/`design.md` dragen de gecorrigeerde env; deze plan-blokken blijven als historisch record staan.

- [ ] **Step 5: Config-consistentie + lint**

Run: `grep -nE 'magazijn-a|mgz|stub-upstream|inway' deploy/local/docker-compose.yaml deploy/local/haproxy.cfg`
Expected: geen treffers.
Run: `command -v yamllint >/dev/null && yamllint deploy/local/docker-compose.yaml deploy/local/postgres-init.sql 2>/dev/null; echo "yamllint-exit=${?}"` (afwezig → CI dekt het)
Run: `grep -c 'uitvraag-org' deploy/local/docker-compose.yaml`
Expected: ≥ 20.

- [ ] **Step 6: `smoke-announce.sh`** (kopieer org-a en pas OIN/naam aan)

Begin met `cp ../moza-fsc-org-a/deploy/local/smoke-announce.sh deploy/local/smoke-announce.sh`. Wijzig:
- `PROVIDER_OIN="00000001003214345000"` → `CONSUMER_OIN="00000000000000000020"` (en alle referenties);
- alle log-teksten `magazijn-a`→`uitvraag-org`;
- in het debug-`logs`-commando onderaan: `migrate-magazijn-a manager-magazijn-a`→`migrate-uitvraag-org manager-uitvraag-org`.
De `peers.peers`-query op `manager_address LIKE '%:443'` + de directory-self-check blijven ongewijzigd.

- [ ] **Step 7: `run-smokes.sh`** (announce-only)

```bash
#!/usr/bin/env bash
set -euo pipefail
d="$(dirname "$0")"
"$d/smoke-announce.sh"
echo "ALLE SMOKES GROEN."
```
Run: `chmod +x deploy/local/*.sh && bash -n deploy/local/smoke-announce.sh deploy/local/run-smokes.sh && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 8: `deploy/local/README.md`** (kopieer org-a en pas aan)

Kopieer org-a's `deploy/local/README.md` en pas aan: titel "directory + consumer-peer uitvraag-org"; componentenlijst manager+outway+controller+txlog; **verwijder** de `publish-service.sh`/`smoke-discover.sh`-regels (announce-only); SNI-hostnames `directory.fsc-test.local` + `uitvraag-org.fsc-test.local` (geen inway-host); controller-UI op `http://localhost:8090`; smoke-verwachting "OK: uitvraag-org is aangemeld ...".

- [ ] **Step 9: Commit**

```bash
git add deploy/local/
git commit -m "feat(local): announce-proof consumer-peer uitvraag-org (directory + manager+outway+controller+txlog) (#781)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: ZAD-deploy — `upsert-peer.sh` + runbooks

**Files:**
- Create: `deploy/zad/upsert-peer.sh`, `deploy/zad/postgres-init.sql`, `deploy/zad/cert-manifest.md`, `deploy/zad/verify-zad.md`, `deploy/zad/README.md`

**Interfaces:**
- Consumes: certs (Task 2) via cert-attachments op `/etc/fsc/...`; placeholders `__ZAD_PROJECT__` + secret `ZAD_API_KEY_FSCUITVRAAG` (Task 6).
- Produces: `upsert-peer.sh validate|plan|apply` die de componenten `uvrpg`, `uvrmgr`, `uvrctl`, `uvrout`, `uvrtxlog` op ZAD zet. `plan` is jq-only (geen netwerk/secrets) — de CI-gate op PR (Task 6).

- [ ] **Step 1: `deploy/zad/postgres-init.sql`** (kopieer org-a verbatim — schema's `manager` + `txlog`, controller-uitzondering)

```bash
cp ../moza-fsc-org-a/deploy/zad/postgres-init.sql deploy/zad/postgres-init.sql
```
(Inhoud is peer-agnostisch: `CREATE SCHEMA manager, txlog` + toelichting. Geen wijziging nodig.)

- [ ] **Step 2: Schrijf `deploy/zad/upsert-peer.sh`** (kopieer org-a en transformeer naar de consumer-componentenset)

Begin met `cp ../moza-fsc-org-a/deploy/zad/upsert-peer.sh deploy/zad/upsert-peer.sh`. Voer deze afgebakende transformaties uit — de structuur (`validate`/`plan`/`apply`, `component_body`, `post`/`poll_task`, self-hosted `uvrpg`, search_path-DSN's, re-roll) blijft identiek:

1. **Defaults:**
   - `PROJECT="${ZAD_PROJECT:-__ZAD_PROJECT__}"`
   - `MGZ*`-hostvars → `UVR*` (`UVRMGR_HOST_DISPLAY`, `UVRCTL_HOST_DISPLAY`, `UVROUT_HOST_DISPLAY`, `UVRTXLOG_HOST_DISPLAY`) met korte namen `uvrmgr`/`uvrctl`/`uvrout`/`uvrtxlog`.
   - `MGZ*_SVC` → `UVR*_SVC` (`${DEPLOYMENT}-uvrmgr` etc., plus `UVRPG_SVC=${DEPLOYMENT}-uvrpg`).
2. **Verwijder alle magazijn-app/inway-specifieke config:** `ZAD_MAGAZIJNA_*`, `MAGAZIJNA_PROJECT/-DEPLOYMENT/-UPSTREAM_URL`, `INWAY_IMAGE`, en de inway-env-blob. De consumer heeft geen upstream-app en geen inway.
3. **Images:** `MANAGER_IMAGE`/`CONTROLLER_IMAGE`/`TXLOG_IMAGE` (migrate-wrappers, ongewijzigd) + `OUTWAY_IMAGE="docker.io/federatedserviceconnectivity/outway:${IMAGE_TAG}"` (stock, geen DB → geen migrate-wrapper) + `POSTGRES_IMAGE` (ongewijzigd).
4. **`UVRMGR_ENV`** (was `MGZMGR_ENV`): `magazijn-a`→`uitvraag-org` in de cert-paden; `AUTO_SIGN_GRANTS=` blijft leeg; `CONTROLLER_REGISTRATION_API_ADDRESS=https://${UVRCTL_SVC}:9443`; `TX_LOG_API_ADDRESS=https://${UVRTXLOG_SVC}:8443`; `SELF_ADDRESS=https://${UVRMGR_HOST_DISPLAY}:443`.
5. **`UVRCTL_ENV`** (was `MGZCTL_ENV`): `magazijn-a`→`uitvraag-org`; `MANAGER_ADDRESS_INTERNAL=https://${UVRMGR_SVC}:9443`.
6. **`UVROUT_ENV`** (nieuw, vervangt `MGZINWAY_ENV`):
```bash
UVROUT_ENV="$(printf '%s\n' \
  "LOG_TYPE=live" "LOG_LEVEL=info" \
  "NAME=uitvraag-org-outway" \
  "GROUP_ID=moza-fbs-test" \
  "LISTEN_ADDRESS=0.0.0.0:8443" \
  "MONITORING_ADDRESS=0.0.0.0:8081" \
  "DISABLE_CRL_CHECKS=true" \
  "TLS_GROUP_ROOT_CERT=/etc/fsc/ca/root.pem" \
  "TLS_GROUP_CERT=/etc/fsc/out/uitvraag-org/outway/cert.pem" \
  "TLS_GROUP_KEY=/etc/fsc/out/uitvraag-org/outway/key.pem" \
  "TLS_ROOT_CERT=/etc/fsc/internal/uitvraag-org/ca/root.pem" \
  "TLS_CERT=/etc/fsc/internal/uitvraag-org/outway/cert.pem" \
  "TLS_KEY=/etc/fsc/internal/uitvraag-org/outway/key.pem" \
  "SELF_ADDRESS=https://${UVROUT_HOST_DISPLAY}:443" \
  "MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS=https://${UVRMGR_SVC}:9444" \
  "TX_LOG_API_ADDRESS=https://${UVRTXLOG_SVC}:8443")"
UVROUT_ALIASES=""
```
7. **`UVRTXLOG_ENV`** (was `MGZTXLOG_ENV`): `magazijn-a`→`uitvraag-org` in de cert-paden.
8. **`UVRPG_ENV` + `_pg_dsn`**: `MGZPG`→`UVRPG`; `_pg_dsn` gebruikt `${UVRPG_SVC}`. DSN's toevoegen aan `UVRMGR_ENV` (schema `manager`), `UVRCTL_ENV` (leeg schema), `UVRTXLOG_ENV` (schema `txlog`).
9. **`DEPLOY_BODY` components:** `{reference:"uvrpg"...}, {reference:"uvrmgr"...}, {reference:"uvrctl"...}, {reference:"uvrout", image:$outway}, {reference:"uvrtxlog"...}` (inway → outway).
10. **Component-bodies + `post`-calls:** `UVRPG_BODY '[5432]'`, `UVRMGR_BODY '[8443,9443,9444]'`, `UVRCTL_BODY '[8080,9443,9444]'`, `UVROUT_BODY '[8443]'`, `UVRTXLOG_BODY '[8443]'`. In `post`: `uvrpg`→`uvrmgr`→`uvrctl`→`uvrout`→`uvrtxlog`.
11. **Directory-host default** (`DIRECTORY_MANAGER_HOST`) blijft `dirmgr-test-mft-tp9.${BASE_DOMAIN}` (override via `ZAD_DIRECTORY_MANAGER_HOST`).
12. **Plan-/klaar-output + PG_PASSWORD-check:** `mgz`→`uvr`; verwijder de inway/upstream-regels.

Run: `bash -n deploy/zad/upsert-peer.sh && echo "syntax OK"`
Expected: `syntax OK`.
Run: `grep -nE 'magazijn|mgz|inway|MAGAZIJNA' deploy/zad/upsert-peer.sh`
Expected: geen treffers.

- [ ] **Step 3: `plan`-dry-run (jq-only, geen netwerk)**

Run: `ZAD_PG_PASSWORD=x deploy/zad/upsert-peer.sh plan test v1.43.7`
Expected: vijf `### component uvr*`-secties met valide JSON-bodies (manager/controller/outway/txlog/pg); geen `magazijn`/`inway`; exit 0.

- [ ] **Step 4: `deploy/zad/cert-manifest.md`** (kopieer org-a en pas de component-tabellen aan)

Kopieer org-a's `cert-manifest.md`; vervang overal `magazijn-a`→`uitvraag-org`, `mgzmgr/mgzctl/mgzinway/mgztxlog/mgzpg`→`uvrmgr/uvrctl/uvrout/uvrtxlog/uvrpg`. Vervang de **`mgzinway`-tabel** door een **`uvrout`-tabel** met dezelfde structuur als de inway (group-root + group cert/key + internal-root + internal cert/key op `out/uitvraag-org/outway/*` resp. `internal/uitvraag-org/outway/*`). De `uvrctl`-tabel (alleen internal, geen group) + `uvrtxlog`-tabel (alleen internal) + `uvrpg` (init-script-attachment) blijven qua vorm gelijk.

- [ ] **Step 5: `deploy/zad/verify-zad.md` + `deploy/zad/README.md`** (kopieer org-a en pas aan)

- `verify-zad.md`: vervang `magazijn-a`→`uitvraag-org`, `mgz*`→`uvr*`; **schrap de dienst-publicatie-stap** (`CreateService`/publish — consumer publiceert niet); de announce-verificatie (`peers.peers`, consumer-OIN `…0020`) blijft; discover/contract markeren als vervolg (op ZAD tegen echte directory + magazijn-a).
- `README.md`: vervang identiteit + componentenlijst (manager/outway/controller/txlog); env-var-tabel `mgz`→`uvr`; **verwijder** `ZAD_MAGAZIJNA_*`-rijen; secret-naam `ZAD_API_KEY_FSCUITVRAAG`; project _placeholder_.

- [ ] **Step 6: Commit**

```bash
git add deploy/zad/
git commit -m "feat(zad): consumer-peer uitvraag-org ZAD-deploy (uvr* componenten, outway) (#781)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `zad-bundle` rookt voor de consumer (verificatie van de PKI↔ZAD-mapping)

**Files:** geen nieuwe (verificatie van Task 2 + Task 4 samen).

**Interfaces:**
- Consumes: `pki/zad-bundle.sh` (Task 2), cert-manifest paden (Task 4).
- Produces: bevestiging dat `zad-bundle.sh uitvraag-org` de vier endpoints (manager/outway/controller/txlog) in `pki/zad-upload/uitvraag-org/` verzamelt met een `MANIFEST.md` waarvan de paden sporen met `cert-manifest.md`.

- [ ] **Step 1 (host-side, na `issue.sh`): bundle draaien**

Run: `cd pki && ./zad-bundle.sh uitvraag-org && ls zad-upload/uitvraag-org/`
Expected: `MANIFEST.md` + `ca/`, `out/uitvraag-org/{manager,outway,controller,txlog}/`, `internal/uitvraag-org/{ca,manager,outway,controller,txlog}/`. `zad-upload/` is gitignored.

- [ ] **Step 2: MANIFEST-paden sporen met cert-manifest**

Run: `grep -oE '/etc/fsc/[^ |`]+' pki/zad-upload/uitvraag-org/MANIFEST.md | sort -u`
Expected: elk pad komt voor in `deploy/zad/cert-manifest.md` (handmatige cross-check: outway heeft group+internal, controller/txlog alleen internal). Bij een mismatch: corrigeer `cert-manifest.md` (Task 4), niet de bundle.

(Geen commit — verificatie-only; `zad-upload/` is gitignored.)

---

### Task 6: CI-workflows

**Files:**
- Create (verbatim uit org-a): `.github/workflows/lint.yml`, `.github/workflows/codeql.yml`, `.github/workflows/scorecard.yml`
- Create (aangepast): `.github/workflows/zad-deploy-peer.yml`

**Interfaces:**
- Consumes: `upsert-peer.sh` (Task 4).
- Produces: PR → `plan` (geen secrets); `main` → `apply` (secret `ZAD_API_KEY_FSCUITVRAAG` + `ZAD_PG_PASSWORD`).

- [ ] **Step 1: Kopieer de peer-agnostische workflows verbatim**

```bash
mkdir -p .github/workflows
for w in lint.yml codeql.yml scorecard.yml; do
  cp "../moza-fsc-org-a/.github/workflows/$w" ".github/workflows/$w"
done
```

- [ ] **Step 2: Schrijf `zad-deploy-peer.yml`** (kopieer org-a en pas aan)

Begin met `cp ../moza-fsc-org-a/.github/workflows/zad-deploy-peer.yml .github/workflows/zad-deploy-peer.yml`. Wijzig:
- Header-comment + `name`: consumer-peer uitvraag-org.
- `env`: `PROJECT: ${{ vars.ZAD_PROJECT_ID_UITVRAAG || '__ZAD_PROJECT__' }}`; **verwijder** `MAGAZIJNA_PROJECT` + de `ZAD_MAGAZIJNA_PROJECT`-doorgifte.
- Plan-step + apply-step: `magazijn-a`→`uitvraag-org`; het secret `ZAD_API_KEY_FSCORGA`→`ZAD_API_KEY_FSCUITVRAAG`.
- De PR-comment-step: hostnamen `mgzmgr/mgzctl/mgzinway`→`uvrmgr/uvrctl/uvrout`; verwijder de inway-regel-tekst waar die "dienst publiceren" impliceert (vervang door de outway).
- Behoud: `permissions: read-all`, `concurrency`, SHA-gepinde `actions/checkout`, `plan` op PR / `apply` op push-main, `ZAD_PG_PASSWORD`-doorgifte.

- [ ] **Step 3: Lint/validatie**

Run: `command -v actionlint >/dev/null && actionlint .github/workflows/*.yml || echo "actionlint afwezig — CI dekt het"`
Run: `grep -nE 'magazijn|mgz|ZAD_API_KEY_FSCORGA|MAGAZIJNA' .github/workflows/zad-deploy-peer.yml`
Expected: geen treffers.
Run: `command -v yamllint >/dev/null && yamllint .github/workflows/*.yml 2>/dev/null; echo "done"`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/
git commit -m "ci: lint/codeql/scorecard + ZAD-deploy-peer workflow (plan op PR, apply op main) (#781)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Draft-PR bijwerken + doc-consistentie

**Files:** geen code (PR-body + eventuele doc-nazorg).

- [ ] **Step 1: `docs/design.md` ↔ implementatie kruischeck**

Run: `grep -nE 'uvrmgr|uvrout|uvrctl|uvrtxlog|uvrpg' deploy/zad/upsert-peer.sh | wc -l`
Expected: > 0 (component-namen sporen met het ontwerp).
Controleer handmatig dat de componentenlijst in `docs/design.md` (manager/outway/controller/txlog/postgres) en de compose/ZAD-realiteit gelijk zijn. Werk het ontwerp bij als er drift is.

- [ ] **Step 2: PR-body verversen** (implementatie is nu compleet; nog steeds draft tot host-side smoke groen is)

Run: `gh pr edit 1 --body-file <(printf '%s\n' 'Zie docs/design.md. Implementatie: PKI + lokale announce-proof + ZAD-deploy + CI voor consumer-peer uitvraag-org (#781). Host-side compose-smoke volgt (Task 8) voordat de PR ready-for-review gaat.')`
Expected: PR #1 bijgewerkt. (Bij een Projects-classic-fout: `gh api -X PATCH repos/MinBZK/moza-fsc-testconsumer/pulls/1 -F body=@<bestand>`.)

- [ ] **Step 3: Commit eventuele doc-fixes**

```bash
git add -A && git diff --cached --quiet || git commit -m "docs: ontwerp↔implementatie consistent (#781)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 8: Host-side acceptatie-smoke (handmatig, docker-host)

**Files:** geen (verificatie-only). Draait op de docker-host (lokaal geen Docker/cfssl gegarandeerd). Levert het end-to-end announce-bewijs.

- [ ] **Step 1: PKI host-side genereren**

Run: `cd pki && ./init-ca.sh && ./issue.sh && ./gen-crl.sh && ./verify.sh`
Expected: `== ALLE ASSERTS GROEN ==`, exit 0. (Verify checkt keten + OIN + isolatie voor alle uitvraag-org-endpoints.)

- [ ] **Step 2: Env + stack**

Run:
```bash
cp deploy/local/.env.example deploy/local/.env
printf 'HOST_UID=%s\nHOST_GID=%s\n' "$(id -u)" "$(id -g)" >> deploy/local/.env
docker compose -f deploy/local/docker-compose.yaml up -d
sleep 25 && docker compose -f deploy/local/docker-compose.yaml ps
```
Expected: alle services `Up`; `manager-uitvraag-org`, `outway-uitvraag-org`, `controller-uitvraag-org`, `txlog-uitvraag-org`, `manager-directory` draaien.

- [ ] **Step 3: Anti-crash-loop-guard** (outway boot zonder contract; mag niet loopen)

Run (na ~30s): `docker compose -f deploy/local/docker-compose.yaml ps --format '{{.Name}} {{.State}} {{.Status}}' | grep -iE 'restart|exited' && echo "LOOP GEVONDEN" || echo "geen restart-loop — OK"`
Expected: `geen restart-loop — OK`. Zo niet: `docker compose logs outway-uitvraag-org` en de outway-env corrigeren (Step 4-noot Task 3) i.p.v. de loop te laten draaien.

- [ ] **Step 4: Announce-smoke**

Run: `./deploy/local/run-smokes.sh`
Expected: `OK: uitvraag-org is aangemeld bij de directory (manager_address op :443).`, `ALLE SMOKES GROEN.`, exit 0.

- [ ] **Step 5: Controller-UI bereikbaar**

Run: `curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8090/`
Expected: `200` (of een redirect-code van de controller-UI).

- [ ] **Step 6: Opruimen + PR ready**

Run: `docker compose -f deploy/local/docker-compose.yaml down -v`
Daarna: markeer PR #1 als ready-for-review (`gh pr ready 1`) — géén reviewer toevoegen.

---

## Self-Review (uitgevoerd)

**Spec-dekking:** identiteit → Global Constraints + Task 2; componenten manager/outway/controller/txlog/postgres → Task 3 (lokaal) + Task 4 (ZAD); PKI (group+internal, endpoints) → Task 2; announce-only lokale proof → Task 3 + Task 8; ZAD-deploy + self-hosted PG + cert-runbooks → Task 4; CI (plan/apply, placeholders) → Task 6; docs → Task 1 + Task 7. Alle ontwerp-secties gedekt. Out-of-scope (discover/contract/data-pad) blijft out.

**Placeholder-scan:** bewuste placeholders `__ZAD_PROJECT__` + secret `ZAD_API_KEY_FSCUITVRAAG` (Global Constraints, ingevuld door de gebruiker) en één "verifieer outway-env-namen bij host-run" met concreet fallback-commando. Geen kale TODO's.

**Type-/naam-consistentie:** endpoints `manager/outway/controller/txlog` en ZAD-refs `uvrmgr/uvrout/uvrctl/uvrtxlog/uvrpg` consistent tussen Task 2/3/4/6; OIN `00000000000000000020` overal; anchor-namen `&uvr-*` uniek t.o.v. org-a's `&mgz-*`; DB's `fsc_uitvraag_org`/`fsc_controller_uitvraag_org`/`fsc_txlog_uitvraag_org` consistent tussen compose + postgres-init.
