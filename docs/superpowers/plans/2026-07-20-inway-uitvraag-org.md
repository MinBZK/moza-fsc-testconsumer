# Inway `uvrin` voor `uitvraag-org` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voeg een inway-component `uvrin` toe aan de peer `uitvraag-org`, zodat die naast afnemen
(via `uvrout`) ook diensten kan aanbieden.

**Architecture:** Deze repo is een deploy-/configuratierepo, geen applicatiecode. De inway is een
ingress vóór een aangeboden dienst: stock-image `fsc-inway:v1.43.7`, geen DB, geen migratie-wrapper.
Hij krijgt twee cert-ketens (GROUP voor de mesh, INTERNAL voor component-tot-component), registreert
zich bij `uvrctl` en leest z'n config bij `uvrmgr` op de internal-unauthenticated poort. Elke taak
raakt één laag (PKI → ZAD → lokaal → docs) en is los verifieerbaar.

**Tech Stack:** bash, cfssl, jq, Docker Compose, HAProxy, ZAD Operations Manager v2-API.

**Spec:** `docs/superpowers/specs/2026-07-20-inway-uitvraag-org-design.md`

## Global Constraints

- Peer: `uitvraag-org`, OIN `00000000000000000020`, group `moza-fbs-test`.
- ZAD-project `mpfuc-84g`, deployment `test`, base-domain `rig.prd1.gn2.quattro.rijksapps.nl`.
- OpenFSC-versie: `v1.43.7` (stock-image voor de inway — geen migratie-wrapper, geen DB).
- Componentnaam: **`uvrin`** (niet `uvrinway`) — symmetrisch met `uvrout`.
- Manager-poort: **`MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS`, `:9444`** — org-a's bewezen config.
  NIET `MANAGER_INTERNAL_ADDRESS`/`:9443` (dat is de outway-variant).
- `TX_LOG_API_ADDRESS` verschilt per omgeving: **ZAD `:8443`**, **lokaal `:9443`**. Niet uniformeren.
- Secrets (keys, certs, `.env`) nooit committen — `.gitignore` dekt `pki/{ca,out,internal,zad-upload}`.
- Commit-trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Nooit direct naar `main`; we werken op `feature/inway-uitvraag-org`.
- Buiten scope: `CreateService`/`servicePublication`, `publish-service.sh`, `AUTO_SIGN_GRANTS`.

---

## File Structure

| Bestand | Verantwoordelijkheid | Actie |
|---|---|---|
| `pki/gen-csr.sh` | endpoint→component-mapping, SAN-generatie | Modify (1 regel) |
| `deploy/zad/upsert-peer.sh` | ZAD-componentdefinities + rollout | Modify (6 plekken) |
| `deploy/local/docker-compose.yaml` | lokale proof-topologie | Modify (1 service erbij) |
| `deploy/local/haproxy.cfg` | SNI-passthrough routing | Modify (route + backend) |
| `deploy/zad/cert-manifest.md` | welke bijlage op welk pod-pad | Modify (tabel erbij) |
| `docs/design.md`, `CLAUDE.md`, `pki/README.md`, `deploy/local/README.md`, `deploy/zad/verify-zad.md` | documentatie | Modify |

---

### Task 1: PKI — endpoint `inway` uitgeven

**Files:**
- Modify: `pki/gen-csr.sh:38`
- Genereert (niet in git): `pki/peers/uitvraag-org/inway/csr.json`,
  `pki/out/uitvraag-org/inway/{cert,key}.pem`, `pki/internal/uitvraag-org/inway/{cert,key}.pem`

**Interfaces:**
- Produces: de cert-paden die Task 2 en Task 3 als `TLS_*`-waarden gebruiken:
  `out/uitvraag-org/inway/{cert,key}.pem` (GROUP) en
  `internal/uitvraag-org/inway/{cert,key}.pem` (INTERNAL).
- Produces: SAN `test-uvrin` + `uvrin-test-mpfuc-84g.rig.prd1.gn2.quattro.rijksapps.nl`.

**Voorwaarde:** `pki/ca/` bevat de testnet-CA (root+intermediate uit moza-fsc-testnet). Draai
**nooit** `init-ca.sh` — dat maakt een vreemde CA.

- [ ] **Step 1: Voeg het endpoint toe aan de mapping**

In `pki/gen-csr.sh`, vervang regel 38:

```bash
ENDPOINTS=( "manager:uvrmgr" "outway:uvrout" "controller:uvrctl" "txlog:uvrtxlog" )
```

door:

```bash
ENDPOINTS=( "manager:uvrmgr" "outway:uvrout" "inway:uvrin" "controller:uvrctl" "txlog:uvrtxlog" )
```

- [ ] **Step 2: Genereer de csr's en controleer de SAN's**

Run: `cd pki && ./gen-csr.sh && jq . peers/uitvraag-org/inway/csr.json`

Expected: een regel `csr uitvraag-org/inway: ...` in de uitvoer, en een `csr.json` met exact deze
`hosts` (volgorde telt niet, inhoud wel):

```json
[
  "inway.uitvraag-org.fsc-test.local",
  "uvrin-test-mpfuc-84g.rig.prd1.gn2.quattro.rijksapps.nl",
  "test-uvrin",
  "test-uvrin.rig-prd-mpfuc-84g.svc.cluster.local"
]
```

Plus `"serialnumber": "00000000000000000020"` en `"O": "uitvraag-org"`.
De kale peer-FQDN `uitvraag-org.fsc-test.local` hoort er **niet** in te staan — die is manager-only.

- [ ] **Step 3: Geef de certs uit en verifieer beide ketens**

Run: `cd pki && ./issue.sh && ./gen-crl.sh && ./verify.sh`

Geen `-f`: er komt alleen een endpoint bij, de bestaande vier certs blijven geldig en hoeven niet
her-uitgegeven. `-f` zou de per-peer internal-CA en alle bestaande leafs forceren, met als gevolg
dat alle cert-attachments opnieuw in de ZAD-UI geüpload moeten worden — onnodig voor deze stap.

Expected: `verify.sh` eindigt met OK; de uitvoer noemt nu ook het `inway`-endpoint. Beide ketens
valideren: GROUP tegen `ca/root.pem`, INTERNAL tegen `internal/uitvraag-org/ca/root.pem`.

Als `verify.sh` het inway-endpoint niet noemt: het script leidt zijn endpointlijst mogelijk
zelfstandig af. Controleer met `grep -n "manager\|outway\|endpoint" pki/verify.sh` en voeg `inway`
daar op dezelfde manier toe als de bestaande endpoints.

- [ ] **Step 4: Controleer dat het group-cert de intermediate draagt**

Run: `grep -c "BEGIN CERTIFICATE" pki/out/uitvraag-org/inway/cert.pem`

Expected: `2` (leaf + intermediate). Bij `1` faalt de ZAD-boot later met
`certificate is signed by 'Intermediate CA' and not by provided root CA` — draai dan
`pki/combine-pem.sh` zoals de andere group-certs dat doen.

- [ ] **Step 5: Bouw de ZAD-upload-bundle**

Run: `cd pki && ./zad-bundle.sh uitvraag-org && ls zad-upload/uitvraag-org/ | grep -i inway`

Expected: bestanden voor het inway-endpoint staan in de upload-set, en
`zad-upload/uitvraag-org/MANIFEST.md` noemt de inway-paden met hun `TLS_*`-env-var.
Verschijnt er niets: `zad-bundle.sh` mapt op pad-patronen — controleer `env_for()` in dat script en
breid het patroon uit zoals voor `outway`.

- [ ] **Step 6: Commit**

Alleen het script — certs en keys zijn gitignored.

```bash
git add pki/gen-csr.sh
git commit -m "feat(pki): geef cert-keten uit voor het inway-endpoint (uvrin)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Run daarna: `git status --short`
Expected: geen ongetrackte bestanden onder `pki/out`, `pki/internal` of `pki/zad-upload`.

---

### Task 2: ZAD — component `uvrin` in `upsert-peer.sh`

**Files:**
- Modify: `deploy/zad/upsert-peer.sh` (regels ~105, ~115, ~128, ~194, ~260-273, ~282, ~343, ~370)

**Interfaces:**
- Consumes uit Task 1: `out/uitvraag-org/inway/{cert,key}.pem`,
  `internal/uitvraag-org/inway/{cert,key}.pem`.
- Consumes bestaand: `UVRMGR_SVC`, `UVRCTL_SVC`, `UVRTXLOG_SVC`, `IMAGE_TAG`,
  `component_body() { $1=name $2=image $3=ports_json $4=env $5=services_json $6=aliases }`.
- Produces: `UVRIN_HOST_DISPLAY`, `UVRIN_SVC`, `UVRIN_ENV`, `UVRIN_BODY` — gebruikt door Task 4's docs.

- [ ] **Step 1: Voeg het image toe**

Na regel 105 (`OUTWAY_IMAGE=...`), voeg toe:

```bash
INWAY_IMAGE="docker.io/federatedserviceconnectivity/inway:${IMAGE_TAG}"
```

Werk ook de comment op regel 101-102 bij: `De outway heeft geen DB en dus geen migratie -> stock-image.`
wordt `De outway en inway hebben geen DB en dus geen migratie -> stock-image.`

- [ ] **Step 2: Voeg hostnaam en Service-DNS toe**

Na regel 115 (`UVROUT_HOST_DISPLAY=...`):

```bash
UVRIN_HOST_DISPLAY="uvrin-${DEPLOYMENT}-${PROJECT}.${BASE_DOMAIN}"
```

Na regel 128 (`UVROUT_SVC=...`):

```bash
UVRIN_SVC="${DEPLOYMENT}-uvrin"
```

- [ ] **Step 3: Voeg de env-blob toe**

Direct ná het `UVROUT_ALIASES=""`-blok (regel ~213), vóór het txlog-blok:

```bash
# inway (ingress-proxy): de tegenhanger van uvrout. Registreert zich bij de controller en leest
# z'n service-/contract-config bij de manager op de internal-UNAUTHENTICATED poort (:9444) —
# dit is bewust een andere edge dan de outway (die gebruikt de authenticated :9443, zie e7300c5);
# conform de bewezen provider-config van magazijn-a. Kent GEEN upstream-env: de upstream-URL is
# de endpoint_url bij service-publicatie op de uvrctl Administration-API (nog niet ingericht).
UVRIN_ENV="$(printf '%s\n' \
  "LOG_TYPE=live" "LOG_LEVEL=info" \
  "NAME=uitvraag-org-inway" \
  "GROUP_ID=moza-fbs-test" \
  "LISTEN_ADDRESS=0.0.0.0:8443" \
  "MONITORING_ADDRESS=0.0.0.0:8081" \
  "DISABLE_CRL_CHECKS=true" \
  "TLS_GROUP_ROOT_CERT=/etc/fsc/ca/root.pem" \
  "TLS_GROUP_CERT=/etc/fsc/out/uitvraag-org/inway/cert.pem" \
  "TLS_GROUP_KEY=/etc/fsc/out/uitvraag-org/inway/key.pem" \
  "TLS_ROOT_CERT=/etc/fsc/internal/uitvraag-org/ca/root.pem" \
  "TLS_CERT=/etc/fsc/internal/uitvraag-org/inway/cert.pem" \
  "TLS_KEY=/etc/fsc/internal/uitvraag-org/inway/key.pem" \
  "SELF_ADDRESS=https://${UVRIN_HOST_DISPLAY}:443" \
  "CONTROLLER_REGISTRATION_API_ADDRESS=https://${UVRCTL_SVC}:9443" \
  "MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS=https://${UVRMGR_SVC}:9444" \
  "TX_LOG_API_ADDRESS=https://${UVRTXLOG_SVC}:8443")"
# Geen managed DB en geen $DATABASE_*-substitutie -> geen aliases nodig.
UVRIN_ALIASES=""
```

- [ ] **Step 4: Voeg de component toe aan de deployment-body**

In het `DEPLOY_BODY`-blok (regels 259-263): voeg `--arg inway "${INWAY_IMAGE}"` toe aan de
jq-argumenten (naast `--arg outway`), en breid de `components`-array uit met `uvrin` ná `uvrout`:

```bash
    components:[{reference:"uvrpg", image:$pg}, {reference:"uvrmgr", image:$mgr}, {reference:"uvrctl", image:$ctl}, {reference:"uvrout", image:$outway}, {reference:"uvrin", image:$inway}, {reference:"uvrtxlog", image:$txlog}]}
```

- [ ] **Step 5: Voeg de component-body toe**

Na de `UVROUT_BODY`-regel (~273):

```bash
UVRIN_BODY="$(component_body uvrin "${INWAY_IMAGE}" '[8443]' "${UVRIN_ENV}" '[]' "${UVRIN_ALIASES}")"
```

Let op de zesde positie: `component_body` is `$5=services_json $6=aliases`. Vijf argumenten
doorgeven zou `UVRIN_ALIASES` als `services_json` interpreteren en jq laten falen.

- [ ] **Step 6: Breid de plan-output uit**

Na regel 282 (`echo "### component uvrout (outway)"...`):

```bash
  echo "### component uvrin (inway)"; echo "${UVRIN_BODY}"
```

Vervang regel 284 (de `Extern (mesh, :443)`-regel in het plan-blok) door:

```bash
  echo "Extern (mesh, :443): uvrmgr=${UVRMGR_HOST_DISPLAY} uvrin=${UVRIN_HOST_DISPLAY}  (uvrout=${UVROUT_HOST_DISPLAY} is egress-only — geen mesh-ingress)"
```

- [ ] **Step 7: Verifieer de plan-output (dry-run, geen netwerk)**

Run: `./deploy/zad/upsert-peer.sh plan`

Expected: exit 0, en een sectie `### component uvrin (inway)` met valide JSON. Controleer gericht:

```bash
./deploy/zad/upsert-peer.sh plan | sed -n '/### component uvrin/,/^### /p' | sed '1d;$d' | jq -e '.name == "uvrin" and .ports == [8443] and (.env_vars | contains("MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS=https://test-uvrmgr:9444"))'
```

Expected: `true`.

Controleer ook dat `uvrin` in de deployment-body staat:

```bash
./deploy/zad/upsert-peer.sh plan | sed -n '/### deployment/,/^### /p' | sed '1d;$d' | jq -e '[.components[].reference] | index("uvrin") != null'
```

Expected: `true`.

- [ ] **Step 8: Voeg de rollout-POST toe**

Na regel 343 (`post "uvrout" ...`):

```bash
post "uvrin"    "/components" "${UVRIN_BODY}"
```

Werk regel 370 (de handmatige-stappen-echo) bij — de inway is wél een mesh-ingress:

```bash
echo "  - FSC-componenten: cert-bijlagen op /etc/fsc/... + Publicatie op het web modus 2 op uvrmgr en uvrin (mesh :443; de outway uvrout is egress-only — geen web-publicatie/inbound ingress)."
```

En regel 372 (de `Extern`-echo ná apply) gelijk aan die in Step 6.

- [ ] **Step 9: Syntaxcheck en commit**

Run: `bash -n deploy/zad/upsert-peer.sh && ./deploy/zad/upsert-peer.sh plan >/dev/null && echo OK`
Expected: `OK`

```bash
git add deploy/zad/upsert-peer.sh
git commit -m "feat(zad): voeg inway-component uvrin toe aan de peer-rollout

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Lokale proof — inway in compose + SNI-route

**Files:**
- Modify: `deploy/local/docker-compose.yaml` (service erbij, router-alias)
- Modify: `deploy/local/haproxy.cfg` (route + backend)

**Interfaces:**
- Consumes uit Task 1: de cert-paden onder `${PKI_DIR}`.
- Let op: lokaal is `TX_LOG_API_ADDRESS` poort **`:9443`** (ZAD gebruikt `:8443`).

- [ ] **Step 1: Voeg de inway-service toe**

In `deploy/local/docker-compose.yaml`, direct ná het `outway-uitvraag-org`-blok (eindigt regel 202)
en vóór `toolbox:`:

```yaml
  inway-uitvraag-org:
    image: docker.io/federatedserviceconnectivity/inway:${IMAGE_TAG:-v1.43.7}
    user: "${HOST_UID:-1000}:${HOST_GID:-1000}"   # host-UID -> leest 0600-keys
    restart: on-failure                            # boot-race met controller/manager
    command:
      - /usr/local/bin/inway
      - serve
    environment:
      LOG_TYPE: local
      LOG_LEVEL: debug
      GROUP_ID: moza-fbs-test
      # geregistreerde inway-naam; SELF_ADDRESS wordt als inway_address doorgegeven bij CreateService
      NAME: uitvraag-org-inway
      SELF_ADDRESS: https://inway.uitvraag-org.fsc-test.local:443
      LISTEN_ADDRESS: 0.0.0.0:8443
      MONITORING_ADDRESS: 0.0.0.0:8081
      DISABLE_CRL_CHECKS: "true"
      # Registreert zich bij de controller via TLS op de controller-internal-cert:
      CONTROLLER_REGISTRATION_API_ADDRESS: https://controller.uitvraag-org.fsc-test.local:9443
      # Eigen manager, internal-UNAUTHENTICATED poort (:9444) — bewust anders dan de outway,
      # die de authenticated :9443 gebruikt. Conform magazijn-a's bewezen inway-config.
      MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS: https://manager.uitvraag-org.fsc-test.local:9444
      # Echte txlog-api (INTERNAL-PKI mTLS). Bij een inkomende data-call logt de inway hier de
      # transactie (direction: in) met dezelfde Fsc-Transaction-Id als de outway.
      TX_LOG_API_ADDRESS: https://txlog.uitvraag-org.fsc-test.local:9443
      TLS_ROOT_CERT: /pki/internal/uitvraag-org/ca/root.pem
      TLS_CERT: /pki/internal/uitvraag-org/inway/cert.pem
      TLS_KEY: /pki/internal/uitvraag-org/inway/key.pem
      TLS_GROUP_ROOT_CERT: /pki/ca/root.pem
      TLS_GROUP_CERT: /pki/out/uitvraag-org/inway/cert.pem
      TLS_GROUP_KEY: /pki/out/uitvraag-org/inway/key.pem
    volumes:
      - "${PKI_DIR:?zet PKI_DIR in .env}:/pki:ro"
    # NB: géén network-alias inway.uitvraag-org.fsc-test.local hier — die hoort op de router
    # (:443-SNI-passthrough, zie hierboven bij `router`). De router-backend bereikt deze
    # container via de compose-servicenaam `inway-uitvraag-org:8443`.
    depends_on:
      controller-uitvraag-org:
        condition: service_started
      manager-uitvraag-org:
        condition: service_started
      txlog-uitvraag-org:
        condition: service_started
```

Er is bewust **geen** `stub-upstream`-dependency: die bestaat in deze repo niet (org-a heeft die
wel) en de upstream is nog niet bekend.

- [ ] **Step 2: Voeg de router-alias toe**

In het `router`-blok (regels 51-55), breid `aliases` uit:

```yaml
    networks:
      default:
        aliases:
          - directory.fsc-test.local
          - uitvraag-org.fsc-test.local
          - inway.uitvraag-org.fsc-test.local
```

- [ ] **Step 3: Voeg de SNI-route en backend toe**

In `deploy/local/haproxy.cfg`, ná regel 31:

```text
    use_backend uvrin if { req_ssl_sni -i inway.uitvraag-org.fsc-test.local }
```

En ná het `backend uvr`-blok:

```text
backend uvrin
    server s1 inway-uitvraag-org:8443
```

- [ ] **Step 4: Valideer de compose-syntax**

Run: `cd deploy/local && docker compose config >/dev/null && echo OK`
Expected: `OK`

Run: `cd deploy/local && docker compose config | grep -A 3 "inway-uitvraag-org:" | head -5`
Expected: het inway-image `federatedserviceconnectivity/inway:v1.43.7`.

- [ ] **Step 5: Start de stack en controleer dat de inway gezond boot**

Voorwaarde: `deploy/local/.env` bestaat (`cp .env.example .env`, `PKI_DIR` gezet).

Run: `cd deploy/local && docker compose up -d && sleep 30 && docker compose ps inway-uitvraag-org`
Expected: status `running` (niet `restarting`).

Run: `cd deploy/local && docker compose logs inway-uitvraag-org | tail -30`
Expected: geen `x509`-ketenfouten, geen `certificate signed by unknown authority`, en een regel die
registratie bij de controller bevestigt.

**Als de boot faalt op een ontbrekende env-var** die `manager-internal-address` noemt: dan eist
`fsc-inway serve` v1.43.7 tóch de authenticated poort. Vervang in dat geval
`MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS: https://manager.uitvraag-org.fsc-test.local:9444` door
`MANAGER_INTERNAL_ADDRESS: https://manager.uitvraag-org.fsc-test.local:9443`, en doe dezelfde
wijziging in `upsert-peer.sh` (Task 2, Step 3). Noteer dit als bevinding — de spec benoemt dit als
het waarschijnlijkste faalpunt.

- [ ] **Step 6: Controleer dat de bestaande smokes nog slagen**

Run: `cd deploy/local && ./run-smokes.sh`
Expected: `OK: uitvraag-org is aangemeld ...` — de announce-smoke mag niet geraakt zijn.

- [ ] **Step 7: Commit**

```bash
git add deploy/local/docker-compose.yaml deploy/local/haproxy.cfg
git commit -m "feat(local): voeg inway + SNI-route toe aan de lokale proof

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Documentatie bijwerken

**Files:**
- Modify: `deploy/zad/cert-manifest.md`, `deploy/zad/verify-zad.md`, `docs/design.md`,
  `CLAUDE.md`, `pki/README.md`, `deploy/local/README.md`

**Interfaces:**
- Consumes uit Task 1-3: cert-paden, `uvrin`-componentnaam, hostnamen.

- [ ] **Step 1: Voeg de uvrin-tabel toe aan `cert-manifest.md`**

Ná het `## uvrout (outway)`-blok (eindigt regel 67):

```markdown
## uvrin (inway)

De inway is een mesh-ingress en heeft daarom — net als uvrmgr — een GROUP-cert nodig, plus een
INTERNAL-cert voor de edges naar controller/manager/txlog.

| Bijlage-pad (`/etc/fsc/...`) | Bronbestand (`pki/...`) | Env-var op uvrin |
|-------------------------------|-------------------------------------------|--------------------|
| `ca/root.pem` | `ca/root.pem` | `TLS_GROUP_ROOT_CERT` |
| `out/uitvraag-org/inway/cert.pem` | `out/uitvraag-org/inway/cert.pem` | `TLS_GROUP_CERT` |
| `out/uitvraag-org/inway/key.pem` | `out/uitvraag-org/inway/key.pem` | `TLS_GROUP_KEY` |
| `internal/uitvraag-org/ca/root.pem` | `internal/uitvraag-org/ca/root.pem` | `TLS_ROOT_CERT` |
| `internal/uitvraag-org/inway/cert.pem` | `internal/uitvraag-org/inway/cert.pem` | `TLS_CERT` |
| `internal/uitvraag-org/inway/key.pem` | `internal/uitvraag-org/inway/key.pem` | `TLS_KEY` |

`out/uitvraag-org/inway/cert.pem` moet **twee** PEM-blokken bevatten (leaf + intermediate); een
leaf-only mount faalt op de group-root.
```

Werk ook regel 30 bij: `Per component (`uvrmgr`, `uvrctl`, `uvrout`)` wordt
``Per component (`uvrmgr`, `uvrctl`, `uvrout`, `uvrin`)``.

- [ ] **Step 2: Werk `docs/design.md` bij**

In de componententabel (regels ~80-86), voeg ná de `outway`-rij toe:

```markdown
| inway | `uvrin` | ingress-proxy vóór een aangeboden dienst; registreert zich bij de controller (`:9443`) en leest z'n config bij de manager op de internal-unauthenticated poort (`:9444`). Mesh-ingress: eigen `:443`-route (SNI-passthrough). Kent géén upstream-env — de upstream is de `endpoint_url` bij service-publicatie. |
```

Werk de sectiekop "Verschillen t.o.v. de provider-peer (magazijn-a)" bij: de peer is niet langer
consumer-only. Vervang de eerste bullet (`- **outway i.p.v. inway.** ...`, regels ~90-94) door:

```markdown
- **outway én inway.** De peer was aanvankelijk consumer-only (alleen egress). Sinds de
  inway-uitbreiding (2026-07-20) is hij bidirectioneel: `uvrout` neemt af, `uvrin` biedt aan.
  Beide registreren zich bij de controller; de inway heeft daarnaast een inbound SNI-route en
  een GROUP-cert. Verschil met magazijn-a blijft: er is nog géén gepubliceerde dienst
  (`CreateService` volgt zodra de upstream bekend is).
```

Laat de bullets over `AUTO_SIGN_GRANTS` en de controller-rol staan — die gelden onverkort.

- [ ] **Step 3: Werk `CLAUDE.md` bij**

- Identiteitstabel, rij `Endpoints`: `manager`, `outway`, `inway`, `controller`, `txlog`.
- Sectie "Wat dit wel/niet is": de images-opsomming wordt
  `manager`, `outway`, `inway`, `controller`, `txlog-api`.
- Sectie "Migratie-wrappers": `de outway heeft geen DB en gebruikt het stock-image` wordt
  `de outway en de inway hebben geen DB en gebruiken het stock-image`.
- Voeg onder "ZAD — hard geleerde lessen" een bullet toe:

```markdown
- **inway vs outway: verschillende manager-poort.** De outway praat met de manager op de
  authenticated `:9443` (`MANAGER_INTERNAL_ADDRESS`, sinds `e7300c5`); de inway op de
  internal-unauthenticated `:9444` (`MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS`), conform
  magazijn-a's bewezen provider-config. Niet uniformeren zonder te testen.
```

- [ ] **Step 4: Werk de READMEs en verify-zad.md bij**

- `pki/README.md`: endpointlijst `manager/outway/controller/txlog` → `manager/outway/inway/controller/txlog`.
- `deploy/local/README.md`: componentenlijst uitbreiden met de inway; SNI-hostnames uitbreiden met
  `inway.uitvraag-org.fsc-test.local`.
- `deploy/zad/verify-zad.md`: voeg een verificatiestap toe voor `uvrin` (pod draait, geen
  cert-ketenfouten, registratie bij `uvrctl` zichtbaar) plus een vooruitwijzing:

```markdown
### Nog niet bewijsbaar: het inbound data-pad

`uvrin` draait, maar biedt nog geen dienst aan — er is geen `CreateService` gedaan. Zodra de
upstream bekend is, komt daar bij:

1. `ZAD_UITVRAAG_UPSTREAM_URL` in `upsert-peer.sh` (cross-project ingress-URL, https/:443,
   naar analogie van org-a's `ZAD_MAGAZIJNA_UPSTREAM_URL`).
2. Service aanmaken + publiceren via de `uvrctl` Administration-API; `CreateService` verwacht het
   inway-ADRES (`SELF_ADDRESS`, `https://uvrin-test-mpfuc-84g.<base-domain>:443`), niet de naam.
3. Een smoke voor het pad `externe consumer → uvrin → upstream`.
```

- [ ] **Step 5: Lint de documentatie**

Run: `npx --yes markdownlint-cli2 "**/*.md" "#node_modules"`
Expected: geen fouten. Werkt `npx` niet (geen netwerk), sla over — CI draait dezelfde check via
`.github/workflows/lint.yml` met de config uit `.markdownlint.yaml` (MD013/MD033/MD041/MD060 uit).

- [ ] **Step 6: Consistentiecheck**

Run: `grep -rn "consumer-only\|alleen afnemer\|GEEN.*inway\|géén inway" --include="*.md" . | grep -v docs/superpowers | grep -v "^./.git"`

Expected: geen treffers meer die de peer als consumer-only beschrijven (buiten de historische
plan-/specdocumenten onder `docs/superpowers/`, die als record blijven staan).

Run: `grep -rn "uvrin" --include="*.md" --include="*.sh" --include="*.yaml" . | grep -v "^./.git" | wc -l`
Expected: minstens 10 treffers, verspreid over `pki/`, `deploy/zad/`, `deploy/local/`, `docs/`, `CLAUDE.md`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs: documenteer de inway (uvrin) — cert-manifest, design, runbooks

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: PR openen

- [ ] **Step 1: Push de branch**

```bash
git push -u origin feature/inway-uitvraag-org
```

- [ ] **Step 2: Open de PR**

Geen reviewer toevoegen (repo-conventie). Geen auto-close-keyword als het issue moet openblijven.

```bash
gh pr create --title "Inway uvrin: uitvraag-org wordt bidirectioneel" --body "$(cat <<'EOF'
## Wat

Voegt een inway-component `uvrin` toe aan de peer `uitvraag-org`, naast de bestaande `uvrout`.
De peer kan daarmee ook diensten aanbieden in plaats van alleen afnemen.

Ontwerp: `docs/superpowers/specs/2026-07-20-inway-uitvraag-org-design.md`

## Wijzigingen

- **PKI** — endpoint `inway:uvrin` in `gen-csr.sh`; GROUP- + INTERNAL-keten met SAN `test-uvrin`.
- **ZAD** — component `uvrin` in `upsert-peer.sh` (stock-image, geen DB), plan-output uitgebreid.
- **Lokaal** — service `inway-uitvraag-org` in de compose + SNI-route in haproxy.
- **Docs** — cert-manifest, design.md, CLAUDE.md, runbooks.

## Handmatig na merge (ZAD-UI, niet te scripten)

1. Cert-bijlagen op `/etc/fsc/...` koppelen aan `uvrin` (paden in `deploy/zad/cert-manifest.md`).
2. "Publicatie op het web" modus 2 (SNI-passthrough) aanzetten voor `uvrin`.

## Buiten scope

Service-publicatie (`CreateService` + `servicePublication`) — de upstream is nog niet bekend.
De vervolgstappen staan in `deploy/zad/verify-zad.md`.

## Let op

De inway gebruikt `MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS` (`:9444`), bewust anders dan de
outway (`MANAGER_INTERNAL_ADDRESS`, `:9443`, sinds e7300c5). Dit volgt magazijn-a's bewezen
provider-config.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Definition of Done

- [ ] `./deploy/zad/upsert-peer.sh plan` toont een valide `### component uvrin`-sectie; exit 0.
- [ ] `pki/verify.sh` slaagt met het inway-endpoint erbij; beide ketens valideren.
- [ ] `pki/out/uitvraag-org/inway/cert.pem` bevat 2 PEM-blokken.
- [ ] `docker compose config` valideert; `inway-uitvraag-org` boot `running` (niet `restarting`).
- [ ] `./run-smokes.sh` slaagt onverminderd.
- [ ] markdownlint schoon (of via CI bevestigd).
- [ ] Geen certs/keys in `git status`.

**Expliciet niet bewijsbaar in deze slag:** het inbound data-pad
(`externe consumer → uvrin → upstream`) — daarvoor is de upstream nodig.
