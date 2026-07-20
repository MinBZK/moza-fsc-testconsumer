# Ontwerp — inway toevoegen aan de consumer-peer `uitvraag-org`

**Datum:** 2026-07-20
**Status:** goedgekeurd, klaar voor implementatieplan

## Aanleiding

`uitvraag-org` is opgezet als **consumer-only** peer: manager + outway + controller + txlog, géén
inway. Zie `docs/design.md` ("outway i.p.v. inway"). De peer moet nu óók diensten kunnen
**aanbieden** en wordt daarmee **bidirectioneel**: `uvrout` (egress) blijft, `uvrin` (ingress) komt
erbij.

Dit ontwerp draait die eerdere keuze niet terug — de outway blijft nodig voor het afnemer-pad naar
`berichtenmagazijn`. Het is een uitbreiding, geen vervanging.

## Uitgangspunten (vastgesteld tijdens brainstorm)

| Beslissing | Keuze | Reden |
|------------|-------|-------|
| Upstream-dienst | **nog niet bekend** — later invullen | De inway kent geen upstream-env; uitstel is goedkoop (zie hieronder) |
| Scope | **lokale proof én ZAD** | Voorkomt dat `deploy/local` uit sync loopt met ZAD |
| Manager-poort | **`:9444` unauthenticated** | Exact org-a's bewezen inway-config op v1.43.7 |
| Componentnaam | **`uvrin`** | Symmetrisch met `uvrout`; org-a's `mgzinway` past niet in het naam-idioom hier |

### De upstream is géén inway-env-var

OpenFSC kent geen `upstream` op de inway. De upstream-URL is de `endpoint_url` die bij
**service-publicatie** op de controller Administration-API wordt meegegeven — zie
`../moza-fsc-org-a/deploy/zad/upsert-peer.sh:138` en `deploy/local/publish-service.sh` in org-a.

Gevolg: de inway-component kan nu **volledig** worden opgeleverd. Alleen de service-publicatie
schuift op tot de upstream bekend is.

## Architectuur

De inway is een ingress vóór een aangeboden dienst. Hij:

- luistert op `0.0.0.0:8443`, extern bereikbaar via de `:443`-ingress (SNI-passthrough,
  "Publicatie op het web" modus 2 — net als `uvrmgr`);
- registreert zich bij de controller (`CONTROLLER_REGISTRATION_API_ADDRESS`, `:9443`);
- leest z'n service-/contract-config bij de manager op de **internal-unauthenticated** poort
  (`MANAGER_INTERNAL_UNAUTHENTICATED_ADDRESS`, `:9444`);
- logt transacties bij `uvrtxlog` (`:8443`);
- heeft **geen DB** → stock-image `fsc-inway:v1.43.7`, **geen** migratie-wrapper.

### Certificaat-topologie

Twee ketens, identiek aan de andere endpoints (zie `pki/README.md`):

- **GROUP** (extern/mesh) — group-intermediate → `TLS_GROUP_CERT/KEY` op
  `out/uitvraag-org/inway/*`. Mount het bestand **inclusief** aangehechte intermediate (2 PEM-blokken).
- **INTERNAL** (component-tot-component) — per-peer internal-CA → `TLS_CERT/KEY` op
  `internal/uitvraag-org/inway/*`. SAN's: `test-uvrin` + svc-FQDN + de ingress-hostname.

Verwisselen van deze twee is de bekendste faalmodus (`certificate is signed by 'Intermediate CA'
and not by provided root CA`) — zie `deploy/zad/cert-manifest.md`.

## Wijzigingen per bestand

### PKI

`pki/gen-csr.sh:38` — endpoint toevoegen aan de lijst:

```bash
ENDPOINTS=( "manager:uvrmgr" "outway:uvrout" "inway:uvrin" "controller:uvrctl" "txlog:uvrtxlog" )
```

Daarna regenereren:

```bash
cd pki && ./issue.sh && ./gen-crl.sh && ./verify.sh && ./zad-bundle.sh uitvraag-org
```

**Geen `-f`.** Er komt alleen een endpoint bij; de bestaande vier hebben geldige SAN's en hoeven
niet opnieuw uitgegeven. `-f` zou de per-peer internal-CA en alle bestaande group-/internal-leafs
her-genereren met verse sleutels, waardoor de cert-attachments van álle vijf componenten opnieuw
handmatig in de ZAD-UI geüpload moeten worden — onnodige schade voor het toevoegen van één
endpoint. Een kale `./issue.sh` geeft precies de ontbrekende `inway`-certs uit en laat de rest met
rust (zie `pki/issue.sh`: bestaande `cert.pem`/`key.pem` worden zonder `-f` overgeslagen).

Additief — bestaande certs blijven geldig. `zad-bundle.sh` pikt het nieuwe endpoint op via de
bestaande pad-patronen; controleer dat `inway` in de bundle-output verschijnt.

### ZAD — `deploy/zad/upsert-peer.sh`

Vier plekken, gemodelleerd op het bestaande `uvrout`-blok:

1. **Hostnamen** (bij regel ~115/128):
   ```bash
   UVRIN_HOST_DISPLAY="uvrin-${DEPLOYMENT}-${PROJECT}.${BASE_DOMAIN}"
   UVRIN_SVC="${DEPLOYMENT}-uvrin"
   ```
2. **`UVRIN_ENV`** — org-a's inway-blob met `uitvraag-org`-paden:
   ```bash
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
   UVRIN_ALIASES=""
   ```
3. **Component-body + deployment**: `INWAY_IMAGE` (stock, `${IMAGE_TAG}`),
   `UVRIN_BODY="$(component_body uvrin "${INWAY_IMAGE}" '[8443]' "${UVRIN_ENV}" '[]' "${UVRIN_ALIASES}")"`
   (let op de zesde positie: `component_body` is `$5=services_json $6=aliases`),
   en `uvrin` toevoegen aan de `DEPLOY_BODY`-componentenlijst.
4. **`post "uvrin" "/components" "${UVRIN_BODY}"`** + de `plan`-output uitbreiden met de
   `uvrin`-sectie en de ingress-hostname.

### Lokale proof — `deploy/local/`

- `docker-compose.yaml`: service `inway-uitvraag-org` (org-a's `inway-magazijn-a`-blok, met
  `magazijn-a`→`uitvraag-org` en de `&uvr-*`-anchors), cert-mounts op `out/uitvraag-org/inway/*`
  resp. `internal/uitvraag-org/inway/*`, netwerk-alias `inway.uitvraag-org.fsc-test.local`.
- `haproxy.cfg`: SNI-route + backend voor `inway.uitvraag-org.fsc-test.local` naar
  `inway-uitvraag-org:8443`.

### Documentatie

- `deploy/zad/cert-manifest.md` — `uvrin`-tabel (group-root, group cert/key, internal-root,
  internal cert/key), zelfde vorm als de `uvrout`-tabel.
- `deploy/zad/verify-zad.md` — verificatiestap voor `uvrin` + wat er straks nodig is voor
  service-publicatie (zie "Vervolgstap" hieronder).
- `docs/design.md` — componententabel uitbreiden; de sectie "Verschillen t.o.v. de provider-peer"
  bijwerken: de peer is niet langer consumer-only.
- `CLAUDE.md` — identiteitstabel (endpoints), images-regel, componentenoverzicht.
- `deploy/local/README.md`, `pki/README.md` — endpointlijsten.

## Handmatige stappen (niet te scripten)

Uit de ZAD-lessen in `CLAUDE.md`: component-env wordt **alleen bij creatie** toegepast, en
cert-attachments zijn **UI-only per component**. Voor `uvrin` betekent dat na de eerste
`upsert-peer.sh apply`:

1. In de ZAD-UI de vijf cert-bijlagen op `/etc/fsc/...` koppelen aan `uvrin` (paden in
   `cert-manifest.md`).
2. "Publicatie op het web" op **modus 2** (SNI-passthrough) zetten voor `uvrin`.

Deze stappen worden in `cert-manifest.md` vastgelegd zodat ze eenmalig en reproduceerbaar zijn.

## Wat buiten scope blijft

- **Service-publicatie**: `CreateService` + het `servicePublication`-contract, en daarmee
  `publish-service.sh` / `smoke-discover.sh`. Vereist de upstream-URL.
- **`AUTO_SIGN_GRANTS`** blijft leeg — dat is een directory-eigenschap, niet iets voor een
  aanbiedende peer.

## Verificatie / definition of done

Na deze slag is aantoonbaar:

- `./deploy/zad/upsert-peer.sh plan` toont een valide `### component uvrin`-sectie; exit 0.
- `pki/verify.sh` slaagt met het `inway`-endpoint erbij; beide ketens valideren.
- `uvrin` boot op ZAD zonder cert-ketenfouten en registreert zich bij `uvrctl`.
- De lokale compose start `inway-uitvraag-org` gezond op.

**Nog niet bewijsbaar:** het inbound data-pad (`externe consumer → uvrin → upstream`) — daarvoor is
de upstream nodig.

## Vervolgstap (apart traject)

Zodra de aangeboden dienst en haar upstream bekend zijn:

1. `ZAD_UITVRAAG_UPSTREAM_URL` introduceren in `upsert-peer.sh` (cross-project ingress-URL, naar
   analogie van org-a's `ZAD_MAGAZIJNA_UPSTREAM_URL`).
2. Service aanmaken + publiceren via de `uvrctl` Administration-API.
3. Smoke-test voor het inbound data-pad.

## Risico's

- **Manager-poort `:9444`.** We kopiëren org-a's bewezen config. Als `fsc-inway serve` in deze
  opstelling toch de authenticated `:9443` eist (zoals de outway sinds commit `e7300c5`), faalt de
  boot met een duidelijke env-fout — dan omzetten naar `MANAGER_INTERNAL_ADDRESS`. Bewust
  geaccepteerd: de kopie is de goedkoopste weg naar een werkende component.
- **Cert-mount-verwisseling** is de historisch duurste faalmodus. `cert-manifest.md` strikt volgen.
- **Re-`apply` werkt env niet bij.** Wijzigt er later iets aan `UVRIN_ENV`, dan moet dat via de UI
  of door de component opnieuw aan te maken (kost de attachments).
