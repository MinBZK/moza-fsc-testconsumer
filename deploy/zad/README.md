# ZAD-deploy — consumer-peer uitvraag-org

ZAD-rollout van de FSC-consumer-peer `uitvraag-org` (manager `uvrmgr`, controller `uvrctl`, outway
`uvrout`, txlog `uvrtxlog`) in een **eigen ZAD-project** (`mpfuc-84g`, deployment `test`).
De consumer publiceert geen dienst en heeft geen upstream-app: de outway bereikt de aanbiedende
peer straks rechtstreeks over de FSC-mesh, niet cross-project. Bouwt voort op `pki/`
(certs) en `deploy/local/` (lokale compose-proof van dezelfde peer); zie die README's voor het
cert-contract resp. de lokale smokes.

> **Group-CA komt uit repo A (fsc-testnet), niet uit `init-ca.sh`.** Om aan te sluiten op de
> échte directory moet uitvraag-org's group-leaf ketenen naar fsc-testnet's group-root. Draai
> daarom voor ZAD **niet** `pki/init-ca.sh` (dat maakt een verse, vreemde CA); zet in plaats
> daarvan fsc-testnet's `ca/root.pem` + `ca/intermediate.pem` (+ keys) in `pki/ca/` en draai
> alleen `issue.sh`. Zie `pki/README.md`.

## Inhoud

| Bestand | Rol |
|---------|-----|
| `upsert-peer.sh` | `validate`/`plan`/`apply` tegen de ZAD v2 Operations Manager API — één bron voor CLI + de workflow. |
| `cert-manifest.md` | Runbook: welk cert-bestand op welk `/etc/fsc/...`-pad, per component (UI-only bijlagen). |
| `verify-zad.md` | Runbook: announce ná een geslaagde apply, + de acceptatiecriteria. |
| `../../.github/workflows/zad-deploy-peer.yml` | SHA-gepinde workflow die `upsert-peer.sh apply` aanroept (deployt naar `test` op push/PR). |

## Volgorde

1. **Certs** — `pki/init-ca.sh` → `pki/issue.sh` → `pki/verify.sh`
   (vereist `cfssl`; zie `pki/README.md`).
2. **Bundle** — `pki/zad-bundle.sh uitvraag-org` (hangt af van stap 1) →
   upload-klare cert-set in `pki/zad-upload/uitvraag-org/`.
3. **Deployment `test` moet bestaan** in het eigen project — de raw v2-API `:upsert-deployment`
   maakt géén NIEUWE deployment aan (geeft wel 202 maar het deployment verschijnt niet); het UPDATET
   alleen een bestaand deployment. `test` is doorgaans het default-deployment van een nieuw project
   en bestaat dus al. Zo niet: maak het éénmalig handmatig (leeg) aan in de Operations Manager-UI.
   De workflow zet daarna de componenten + images.
4. **`upsert-peer.sh plan [deployment] [tag]`** (dry-run, wél uitvoerbaar — alleen `jq`, geen
   netwerk) — toont de deployment- + vijf component-bodies zonder te muteren.
5. **`upsert-peer.sh validate`** (vereist `ZAD_API_KEY`) — read-only auth-check tegen
   de ZAD-API.
6. **`upsert-peer.sh apply [deployment] [tag]`** (vereist `ZAD_API_KEY`) — upsert het
   deployment + de vijf componenten, pollt de resulterende tasks.
7. **UI-mount** (zie `cert-manifest.md`) — cert-attachments + "Publicatie op het web"
   (passthrough-TLS) zijn UI-only; de v2-API dekt dit niet.
8. **`verify-zad.md`** — announce.

## Env-vars

| Variabele | Default | Rol |
|-----------|---------|-----|
| `ZAD_API_KEY` | — (verplicht bij `apply`) | Auth tegen de ZAD v2-API; **de key van het eigen project**, niet de key van een ander project. **Niet** inline zetten (`export`, niet `ZAD_API_KEY=... ./upsert-peer.sh ...` — dat komt in de shell-history). |
| `ZAD_PROJECT` | `mpfuc-84g` | Eigen ZAD-project van de peer (los van het app-project). Bepaalt óók de namespace (`rig-prd-<project>`) in de cert-SAN's — `pki/gen-csr.sh` leest dezelfde var, dus een projectwissel is env-var-only (her-uitgeven + opnieuw uploaden). |
| `ZAD_DEPLOYMENT` | `test` | Default voor het `[deployment]`-argument (het CLI-arg wint). Gedeeld met `pki/gen-csr.sh` zodat cert-SAN's en deploy-adressen sporen. |
| `ZAD_BASE` | `https://zad.rijksapp.nl` | Basis-URL van de ZAD v2 Operations Manager API. |
| `ZAD_BASE_DOMAIN` | `rig.prd1.gn2.quattro.rijksapps.nl` | Base-domain voor de per-component mesh-hostnamen. |
| `ZAD_MANAGER_TAG` / `ZAD_CONTROLLER_TAG` / `ZAD_TXLOG_TAG` | = het `tag`-argument | Losse tag-override per migrate-wrapper (ghcr `{manager,controller,txlog}-migrate`), los van de OpenFSC stock-tag voor de outway. |
| `ZAD_MANAGER_IMAGE` / `ZAD_CONTROLLER_IMAGE` / `ZAD_TXLOG_IMAGE` | ghcr `…/{manager,controller,txlog}-migrate:<tag>` | Volledige image-override per wrapper — zet dit als het ghcr-pad afwijkt. manager/controller/txlog draaien een wrapper (`migrate up && serve`); de outway heeft geen DB en gebruikt het stock-image. |
| `ZAD_DIRECTORY_MANAGER_HOST` | `dirmgr-test-mft-tp9.<base-domain>` | Repo A's directory-manager-host op ZAD — pas aan als de directory op een andere deployment/project draait. |
| `ZAD_PG_SSLMODE` | `disable` | SSL-mode voor de `uvrpg`-DSN (intra-cluster plaintext, zoals berichtenbox-JDBC). |
| `ZAD_PG_PASSWORD` | — (verplicht bij `apply`) | Wachtwoord voor de self-hosted Postgres (`uvrpg`). **Niet** committen; `export` (niet inline). Komt zowel in `POSTGRES_PASSWORD` als in de component-DSN's. |
| `ZAD_PG_USER` / `ZAD_PG_DB` | `fsc` / `fsc` | Rol resp. database van `uvrpg`. |
| `ZAD_MGR_SCHEMA` / `ZAD_TXLOG_SCHEMA` | `manager` / `txlog` | `search_path`-schema voor de migratie-teller van manager resp. txlog (isolatie). Moeten sporen met `postgres-init.sql` (dat die twee aanmaakt). Leeg = geen search_path. |
| `ZAD_CTL_SCHEMA` | _(leeg)_ | De controller draait **zonder** search_path — die maakt z'n eigen `controller`-schema aan; mét search_path loopt migratie #1 dirty vast. Alleen zetten als je weet wat je doet. |
| `ZAD_POSTGRES_IMAGE` | `docker.io/library/postgres:17` | Image voor de `uvrpg`-component. |

De workflow leest de ZAD-key uit het secret `ZAD_API_KEY_FSCUITVRAAG` (de key van het eigen
project), niet `ZAD_API_KEY` direct — dat blijft de scriptinterne naam, gezet via `env:` in de
workflow. Zet in GitHub dus **een secret `ZAD_API_KEY_FSCUITVRAAG`** en (optioneel) de var voor
de ZAD-project-id (naam volgt zodra het project bestaat — zie het open punt in `docs/design.md`).
