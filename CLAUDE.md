# CLAUDE.md — Projectcontext voor AI-assistentie

## Project

**uitvraag-org-fsc-peer** — de **FSC consumer-peer** van de uitvraag-organisatie, die als
**afnemer** aansluit op de gedeelde FSC-testfederatie van
[MinBZK/moza-fsc-testnet](https://github.com/MinBZK/moza-fsc-testnet) (repo A — directory + group-CA)
en straks via een lokale outway de dienst `berichtenmagazijn` bij
[moza-fsc-org-a](https://github.com/MinBZK/moza-fsc-org-a) (de provider-peer) aanroept.

- **Gerelateerd:** [moza-fsc-testnet](https://github.com/MinBZK/moza-fsc-testnet) (infra + directory),
  [moza-fsc-org-a](https://github.com/MinBZK/moza-fsc-org-a) (de provider-peer),
  [moza-poc-fbs-berichtenbox](https://github.com/MinBZK/moza-poc-fbs-berichtenbox) (de uitvraag-app).
- Deze repo bevat **uitsluitend FSC-infra** (PKI + deploy) voor één peer, niet de uitvraag-applicatie.

## Taal

Communicatie in het **Nederlands**. Code/technische termen in het Engels waar gangbaar.
Vaste FSC/infra-idiomen niet vertalen: inway, outway, manager, controller, directory, peer, grant,
contract, trust-anchor, passthrough, SNI, txlog, announce.

## Wat dit wel/niet is

- **GEEN fork** van de FSC-software. Dit is een **deploy- en configuratie-repo** die
  [OpenFSC](https://gitlab.com/rinis-oss/fsc/open-fsc) (EUPL-1.2, RINIS) consumeert via haar
  container-images (`manager`, `outway`, `controller`, `txlog-api`, gepind op `v1.43.7`).
- **WEL**: onze test-PKI, peer-configuratie, ZAD-deploy (`upsert-peer.sh` + workflow), runbooks.
- **Migratie-wrappers:** ZAD ondersteunt geen init-containers/args → de migratie zit in het image
  zelf. manager/controller/txlog draaien elk een wrapper-image
  `ghcr.io/minbzk/moza-fsc-testnet/{manager,controller,txlog}-migrate` (`migrate up && serve`); de
  outway heeft geen DB en gebruikt het stock-image. Override per image met
  `ZAD_{MANAGER,CONTROLLER,TXLOG}_IMAGE` of enkel de tag met `ZAD_{MANAGER,CONTROLLER,TXLOG}_TAG`.

## Identiteit

| Parameter | Waarde |
|-----------|--------|
| Peer-naam | `uitvraag-org` |
| Peer-OIN = Peer ID (`subject.serialNumber`) | `00000000000000000020` |
| Group ID | `moza-fbs-test` |
| Directory-OIN | `00000000000000000010` (draait in repo A) |
| Endpoints | `manager`, `outway`, `controller`, `txlog` |
| ZAD-project / deployment | `mpfuc-84g` / `test` |

**Peer ID = geldige OIN** (uit cert `subject.serialNumber`), peer-naam uit `subject.organization`.

## Kernbeslissingen

- **Trust-anchor = de test-CA van het testnet, GÉÉN PKIoverheid.** De group-leaf moet ketenen
  naar fsc-testnet's group-root. Kopieer daarom fsc-testnet's `ca/{root,intermediate}.pem` (+ keys)
  in `pki/ca/` en draai **niet** `init-ca.sh` (dat maakt een verse, vreemde CA — enkel voor de
  geïsoleerde lokale proof). De per-peer INTERNAL-CA blijft wél lokaal/self-signed.
- **Project-isolatie:** de peer draait in een eigen ZAD-project (`mpfuc-84g`) met een eigen
  API-key (secret `ZAD_API_KEY_FSCUITVRAAG`). De uitvraag-app draait apart en wordt cross-project
  via de ingress-URL bereikt.
- **Twee cert-ketens per endpoint:** GROUP (extern, mesh) via de group-intermediate; INTERNAL
  (component-tot-component) via de per-peer internal-CA. Zie `pki/README.md`.

## ZAD — hard geleerde lessen (lees dit vóór je aan de deploy sleutelt)

De ZAD Operations Manager v2-API heeft niet-triviaal gedrag. Deze punten kostten veel debug-tijd:

- **Component-env wordt alleen bij CREATIE toegepast.** Een `POST /components` (of re-`:upsert-
  deployment`) werkt de env/aliases van een BESTAANDE component **niet** bij. Gevolg: runtime-env
  wijzig je in de **UI**, niet via de API. De workflow is betrouwbaar voor images/refs. Wil je env
  echt via de API zetten, dan moet de component opnieuw aangemaakt worden — maar dat kost de
  cert-attachments (UI-only per component), dus in de praktijk: **env in de UI**.
- **Geen `$DEPLOYMENT_NAME`-substitutie gebruiken.** De deployment is vast (`test`), dus
  `upsert-peer.sh` lost alle inter-component-hostnamen concreet op en zet ze in `env_vars`. Sinds de
  self-hosted Postgres (`uvrpg`, 2026-07-15) is óók de DB-DSN concreet — geen ZAD `$DATABASE_*` /
  aliases meer nodig.
- **DB = self-hosted `uvrpg`, niet ZAD-managed.** Eén Postgres-component, één database met
  geïsoleerde golang-migrate-tellers per component (anders skipt een migratie → `42P01` op
  `controller.services`). **manager + txlog** isoleren via een eigen `search_path`-schema
  (`manager`/`txlog`, vooraf aangemaakt door `deploy/zad/postgres-init.sql`, init-attachment op
  `/docker-entrypoint-initdb.d`). De **controller is de uitzondering**: mét `search_path` liep migratie
  #1 dirty vast — die draait ZONDER (`ZAD_CTL_SCHEMA=""`), maakt z'n eigen `controller`-schema aan en
  houdt z'n teller in `public`. Init-script maakt daarom alléén `manager` + `txlog` aan. Wachtwoord via
  `ZAD_PG_PASSWORD` (verplicht bij `apply`, niet committen). manager/controller/txlog migreren bij boot
  via hun eigen wrapper-image (`{manager,controller,txlog}-migrate`, `migrate up && serve`).
- **txlog is verplicht.** Een niet-directory manager faalt hard op een lege `TX_LOG_API_ADDRESS`
  (`tx-log-api-address is required...`). Er draait dus een `uvrtxlog`-component (eigen managed
  Postgres, internal-PKI mTLS).
- **Cert-mount-valkuilen** (UI-only attachments op `/etc/fsc/...`, zie `deploy/zad/cert-manifest.md`):
  - Internal-pad → de **internal**-cert (getekend door de per-peer internal-CA). Group-cert daar
    mounten geeft `certificate is signed by 'Intermediate CA' and not by provided root CA`.
  - Group-pad → de **group**-cert **inclusief** aangehechte intermediate (`out/.../cert.pem` bevat
    2 blokken: leaf + intermediate). Een leaf-only mount geeft dezelfde keten-fout op de root.
  - `TLS_GROUP_ROOT_CERT` = de group-root; internal-`TLS_ROOT_CERT` = de internal-CA-root. Niet
    verwisselen.
- **Mesh + interne poorten (OPGELOST 2026-07-13):** de externe/mesh-API loopt over de `:443`-ingress
  (SNI-passthrough, "Publicatie op het web" modus 2). De interne FSC-API's (`:9443`/`:9444`) lopen
  sinds de ZAD-multi-poort-fix over de cluster-Service-DNS `test-<comp>:<poort>` (elke poort uit de
  component-`ports`-array krijgt een eigen ClusterIP-Service) — NIET meer via de `:443`-ingress. De
  internal-certs dragen daarom `test-<comp>` (+ svc-FQDN) als SAN. Zie `docs/zad-fsc-mesh-blocker.md`
  (resolutie) + `deploy/zad/upsert-peer.sh`.

## Repo-structuur

```text
pki/                 test-PKI: group- + internal-certs per endpoint (cfssl) + zad-bundle
deploy/local/        docker-compose-proof: directory + peer + SNI-router + smokes
deploy/zad/          ZAD-rollout: upsert-peer.sh + cert-/verificatie-runbooks
docs/                design.md (ontwerp + ZAD-bevindingen)
.github/workflows/   zad-deploy-peer.yml (deployt de peer op elke PR-push)
```

## Conventies

- **Secrets nooit committen.** Sleutels/certs/`.env` blijven buiten git (`.gitignore`:
  `pki/ca`, `pki/out`, `pki/internal`, `pki/zad-upload`, `deploy/local/.env`). Alleen scripts,
  CA-configs, `csr.json`'s en `.example`-templates in de repo.
- **Git:** nooit direct naar `main` pushen — feature branch + PR. Branch-prefix `feature/`,
  `fix/`, `chore/`. **Geen reviewer toevoegen** bij het aanmaken van een PR. Geen
  auto-close-keyword (`Closes #N`) in PR-bodies als het issue moet openblijven.
- Toekomstig werk markeren met `TODO(#nnn)` naar het GitHub-issue.
- **CI:** `lint.yml` (markdownlint + yamllint + actionlint), `codeql.yml` (Actions-analyse),
  `scorecard.yml` (OpenSSF supply-chain). Actions SHA-gepind; Dependabot houdt ze bij.
- **AI-verantwoording:** AI-bijdragen markeren met een `Co-Authored-By`-trailer; zie `DISCLAIMER.md`.
- `gh` CLI voor GitHub-operaties.
- **Bestandsnamen:** geen spaties; `kebab-case`/`snake_case` (docs/config) of
  `PascalCase`/`camelCase` (code).

## Build & test

```bash
# PKI (vereist cfssl): issue.sh roept gen-csr.sh aan -> csr-SAN's uit de ZAD-topologie-env.
cd pki && ./issue.sh && ./gen-crl.sh && ./verify.sh && ./zad-bundle.sh uitvraag-org
# Projectwissel = env-var-only: export ZAD_PROJECT=... (evt. ZAD_DEPLOYMENT/-BASE_DOMAIN), dan
# ./issue.sh -f (regenereert csr's) + zad-bundle + upsert-peer — beide lezen dezelfde ZAD_*-vars.

# Lokale proof (vereist Docker):
cd deploy/local && cp .env.example .env && docker compose up -d && ./run-smokes.sh

# ZAD dry-run (jq-only, geen netwerk):
./deploy/zad/upsert-peer.sh plan
```

## Referenties

- [FSC Core-spec (Logius)](https://gitdocumentatie.logius.nl/publicatie/fsc/core/) — mTLS verplicht, poorten 443/8443
- [OpenFSC](https://gitlab.com/rinis-oss/fsc/open-fsc) · [docs.open-fsc.nl](https://docs.open-fsc.nl)
- [moza-fsc-testnet](https://github.com/MinBZK/moza-fsc-testnet) — directory + group-CA
