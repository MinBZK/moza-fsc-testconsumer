**Status:** Concept

# Ontwerp — FSC peer `uitvraag-org` aansluiten op de FSC-federatie (#781)

> Oorspronkelijk de consumer-tegenhanger van de provider-peer in
> [`moza-fsc-org-a`](https://github.com/MinBZK/moza-fsc-org-a) (#780), sinds de inway-uitbreiding
> (2026-07-20) bidirectioneel. Sluit aan op dezelfde testfederatie van
> [`moza-fsc-testnet`](https://github.com/MinBZK/moza-fsc-testnet) (repo A — directory + group-CA).
> Verwant: epic #737. Vervolg (buiten dit ontwerp): het omleiden van `berichtenuitvraag` via de
> outway, het afnemer-contract en het echte data-pad + txlog-hardening.

## Aanleiding

`moza-fsc-testnet` (repo A) levert de generieke FSC-infra: de **directory** (group-anker), de
group-config/CA en een neutrale `example-consumer`-peer als kopieer-template. `moza-fsc-org-a`
(repo provider) zet de **aanbiedende** kant neer: magazijn-a publiceert `berichtenmagazijn`.

Deze repo zet oorspronkelijk de **afnemende** kant neer: een **peer** (`uitvraag-org`) die
zich als afnemer op de federatie aansluit, zodat het uitvraag-systeem (`berichtenuitvraag`) via een
lokale **outway** de dienst `berichtenmagazijn` bij magazijn-a aanroept. Sinds de inway-uitbreiding
(2026-07-20) is de peer **bidirectioneel**: naast de outway (afname) draait er nu ook een **inway**
(aanbod). De peer bestaat uit de OpenFSC-componenten **manager + outway + inway + controller +
txlog** met een eigen managed Postgres, co-located met de achterliggende uitvraag-app.

Gemodelleerd naar de provider-peer in `moza-fsc-org-a` (die op repo A's `example-provider` is
gemodelleerd); deze repo bevat **uitsluitend FSC-infra** (PKI + deploy), niet de uitvraag-applicatie.

> **Niet voor productie.** Test-PKI en test-federatie (`moza-fbs-test`). Sleutels/certs horen
> **niet** in git — zie `.gitignore`.

## Identiteit

| Parameter | Waarde | Herkomst |
|-----------|--------|----------|
| Peer-naam (`subject.O`) | `uitvraag-org` | dit ontwerp |
| Peer-OIN = Peer ID (`subject.serialNumber`) | `00000000000000000020` | gereserveerde test-consumer-OIN, repo A (`example-consumer`) |
| Group ID | `moza-fbs-test` | repo A directory-deploy |
| Directory-OIN | `00000000000000000010` | repo A directory-deploy |
| Endpoints (PKI) | `manager`, `outway`, `inway`, `controller`, `txlog` | dit ontwerp |
| FSC-images (pin) | `v1.43.7` (manager/outway/inway/controller/txlog/directory-ui) | repo A |
| ZAD-project / deployment | `mpfuc-84g` / `test` | dit ontwerp |
| ZAD-component-prefix | `uvr*` (`uvrmgr`/`uvrout`/`uvrin`/`uvrctl`/`uvrtxlog`/`uvrpg`) | dit ontwerp |

**Peer ID = geldige OIN** (uit cert `subject.serialNumber`), peer-naam uit `subject.organization`.
De OIN staat in **lockstep** met elke `pki/peers/uitvraag-org/<endpoint>/csr.json`.

## Wat dit wel/niet is

- **GEEN fork** van de FSC-software. Dit is een **deploy- en configuratie-repo** die
  [OpenFSC](https://gitlab.com/rinis-oss/fsc/open-fsc) (EUPL-1.2, RINIS) consumeert via haar
  container-images (`manager`, `outway`, `inway`, `controller`, `txlog-api`, gepind op `v1.43.7`).
- **WEL**: onze test-PKI, peer-configuratie, ZAD-deploy (`upsert-peer.sh` + workflow), runbooks.
- **Migratie-wrappers:** ZAD ondersteunt geen init-containers/args → de migratie zit in het image
  zelf. manager/controller/txlog draaien elk een wrapper-image
  `ghcr.io/minbzk/moza-fsc-testnet/{manager,controller,txlog}-migrate` (`migrate up && serve`); de
  outway en de inway hebben geen DB en gebruiken het stock-image.

## Scope

**In scope:** de peer voor `uitvraag-org` (OIN `00000000000000000020`), volledige pariteit
met de provider-repo: PKI-laag, lokale compose-proof (announce), ZAD-deploy + cert-runbooks,
CI-workflow, docs.

**Buiten scope (vervolg):**

- **Discover + data-pad lokaal.** De lokale proof is *announce-only* (zie hieronder). Discover van
  `berichtenmagazijn` en het echte data-pad `outway → inway → berichtenmagazijn` bewijs je op ZAD
  tegen de échte directory + echte magazijn-a-peer.
- **Contract (ServiceConnectionGrant).** Het afnemer-contract naar `berichtenmagazijn`.
- **txlog-hardening / e2e-verantwoording.**
- **De `berichtenuitvraag`-app** verandert niet; integratie is config-only (`Magazijnregister`-URL
  → lokale outway i.p.v. direct op het magazijn).

## Architectuur

Gespiegeld op de provider-peer in `moza-fsc-org-a`. Per peer een eigen set FSC-componenten; de
peer draait in een **eigen ZAD-project** (project-isolatie). De uitvraag-app draait apart
en bereikt de outway intra-project.

### Componenten van de peer

| Component | ZAD-ref | Rol |
|-----------|---------|-----|
| manager | `uvrmgr` | announce bij de directory + contract-/token-uitgifte; `manager-migrate`-wrapper migreert de peer-DB bij boot. Géén `AUTO_SIGN_GRANTS` (dat is directory-only). |
| outway | `uvrout` | egress-proxy vóór de uitvraag-app; registreert zich bij de controller (`:9443`) en praat met de manager op de authenticated interne poort (`:9443`) — `fsc-outway serve` eist beide (`manager-internal-address` + `controller-registration-api-address`). Géén inbound router-route (de outway is client, geen ingress). |
| inway | `uvrin` | ingress-proxy vóór een aangeboden dienst; registreert zich bij de controller (`:9443`) en leest z'n config bij de manager op de internal-unauthenticated poort (`:9444`). Mesh-ingress: eigen `:443`-route (SNI-passthrough). Kent géén upstream-env — de upstream is de `endpoint_url` bij service-publicatie. |
| controller | `uvrctl` | beheer-UI: afnemer-toegang aanvragen + contracten beheren/inspecteren (Administration/Registration-API, `AUTHN_TYPE=none`); `controller-migrate`-wrapper migreert bij boot. |
| txlog | `uvrtxlog` | transaction-log API (internal-PKI mTLS, eigen DB). Verplicht: een niet-directory-manager faalt hard op een lege `TX_LOG_API_ADDRESS`. Manager, outway én inway wijzen ernaar. |
| DB | `uvrpg` (self-hosted Postgres, één DB, geïsoleerde migratie-tellers) | system-of-record manager + controller + txlog. |

**Verschillen t.o.v. de provider-peer (magazijn-a):**

- **outway én inway.** De peer was aanvankelijk consumer-only (alleen egress). Sinds de
  inway-uitbreiding (2026-07-20) is hij bidirectioneel: `uvrout` neemt af, `uvrin` biedt aan.
  Beide registreren zich bij de controller; de inway heeft daarnaast een inbound SNI-route en
  een GROUP-cert. Verschil met magazijn-a blijft: er is nog géén gepubliceerde dienst
  (`CreateService` volgt zodra de upstream bekend is).
- **manager zonder `AUTO_SIGN_GRANTS`.** Er is nog géén gepubliceerde dienst (zie boven); er is dus
  niets auto te signen. Auto-sign van servicePublication is een directory-eigenschap.
- **controller in beheer-rol.** Aan de provider-kant (magazijn-a) maakt de controller de dienst aan
  en registreert hij de inway; bij deze peer is hij vooralsnog puur een beheer-UI bovenop de
  manager-API (afnemer-contracten aanvragen/inspecteren) — dat verandert zodra de eigen dienst
  gepubliceerd wordt. Niet vereist voor het data-pad, wél gewenst als beheerscherm.

### Certificaat-topologie (per endpoint, uit repo A)

Elk endpoint (`manager`/`outway`/`inway`/`controller`/`txlog`) krijgt twee ketens:

- **GROUP** (extern, door de group-intermediate getekend) → `TLS_GROUP_CERT/KEY` (+ hergebruikt
  voor `TLS_GROUP_TOKEN_*` en `TLS_GROUP_CONTRACT_*`). De OIN staat 1:1 in `serialnumber` van de
  `csr.json`. De controller heeft géén group-cert nodig (spreekt geen mesh, alleen de eigen manager
  op de internal-PKI) — parallel aan de provider-controller.
- **INTERNAL** (per-peer self-signed CA) → `TLS_CERT/KEY` (+ `TLS_INTERNAL_UNAUTHENTICATED_*`),
  voor de mTLS tussen manager ↔ controller ↔ outway ↔ inway ↔ txlog.

De PKI-scripts (`gen-csr.sh`/`issue.sh`/`verify.sh`/`gen-crl.sh`/`zad-bundle.sh`) zijn 1:1 uit
`moza-fsc-org-a`/repo A; alleen de peer-identiteit (naam `uitvraag-org`, OIN, endpoint-lijst
`manager/outway/inway/controller/txlog`) in `gen-csr.sh` wijkt af.

### Onboarding-flow

```text
uitvraag-org                                 centrale kern (directory)
  manager ───announce────────────────────►  directory-manager (peers.peers, :443)
  controller ──(beheer-UI: contract aanvragen/inspecteren)──► eigen manager (:9443)
  outway ──register + config──────────────►  eigen controller (:9443) + manager (:9443)
  inway ──register + config───────────────►  eigen controller (:9443) + manager (:9444)
```

1. **Cert** — group-cert voor OIN `00000000000000000020` (lokaal `issue.sh`).
2. **Deploy** — peer-componenten (lokaal compose → ZAD-upsert).
3. **Announce** — manager verschijnt in `peers.peers` met `manager_address` op `:443`.

Discover (`berichtenmagazijn` vindbaar) en het contract/data-pad volgen op ZAD (vervolg).

## Levering — twee fasen

### Fase 1 — Lokale compose-proof (*announce-only*, A1)

Zelfstandige harness (mirror van org-a's `deploy/local`, single-peer): directory + peer
(manager + outway + inway + controller + txlog + postgres) + SNI-router + directory-ui. Bewijst:

- de peer **boot** (alle componenten `Up`, geen restart-loop);
- **announce** — `smoke-announce.sh` pollt de directory-DB tot de consumer-OIN met `manager_address`
  op `:443` in `peers.peers` staat;
- de **controller-UI** is bereikbaar (host-poort `8090`).

Bewust *geen* lokale discover-smoke: deze compose heeft geen provider die `berichtenmagazijn`
publiceert (ook al draait sinds de inway-uitbreiding wél een eigen inway mee), dus lokaal
discoveren is betekenisloos. Discover bewijzen we tegen de échte directory op ZAD (Fase 2).

> **outway boot zonder contract.** In deze fase routeert de outway nog niets (geen contract). Hij
> mag niet crash-loopen; de acceptatie asserteert dat geen component in een restart-loop zit.

### Fase 2 — ZAD

`upsert-peer.sh` (`validate`/`plan`/`apply`) tegen de ZAD v2 Operations Manager API, in een **eigen
ZAD-project**. Componenten `uvrpg` (self-hosted Postgres + init-schema's), `uvrmgr`, `uvrctl`,
`uvrout`, `uvrin`, `uvrtxlog`. Cert-attachments + "Publicatie op het web" (passthrough) zijn UI-only (zie
`deploy/zad/cert-manifest.md`). CI (`zad-deploy-peer.yml`): PR → alleen `plan` (geen secrets),
`main` → `apply`.

**Self-hosted Postgres met geïsoleerde migratie-tellers** (exact als org-a): manager + txlog
isoleren hun `schema_migrations`-teller via een eigen `search_path`-schema (`manager`/`txlog`,
aangemaakt door `deploy/zad/postgres-init.sql`); de controller draait **zonder** search_path (maakt
z'n eigen `controller`-schema, teller in `public`).

## ZAD — hard geleerde lessen (overgenomen uit `moza-fsc-org-a`)

Deze punten gelden 1:1 (zelfde v2-API, zelfde OpenFSC-images):

- **Component-env wordt alleen bij CREATIE toegepast** — runtime-env wijzig je in de UI; de workflow
  is betrouwbaar voor images/refs. Component niet verwijderen om env te wijzigen (kost de
  cert-attachments).
- **Geen `$DEPLOYMENT_NAME`-substitutie** — `upsert-peer.sh` lost alle inter-component-hostnamen
  concreet op in `env_vars`; de DB-DSN is concreet sinds de self-hosted `uvrpg`.
- **txlog is verplicht** voor een niet-directory-manager.
- **Cert-mount-valkuilen** — internal-pad = internal-cert; group-pad = group-cert **inclusief**
  intermediate. `TLS_GROUP_ROOT_CERT` = group-root; internal-`TLS_ROOT_CERT` = internal-CA-root.
- **Multi-poort-fix** — interne FSC-edges lopen over de cluster-Service-DNS `<deployment>-<comp>:<poort>`
  (9443/9444, txlog 8443), niet over de `:443`-ingress; de internal-certs dragen die Service-DNS als
  SAN. Alleen de externe mesh (manager `SELF_ADDRESS`) loopt op `:443` (SNI-passthrough).

## Open punten (genoteerd, niet-blokkerend)

- **ZAD-project** is `mpfuc-84g` (deployment `test`) — ingebakken als default in `upsert-peer.sh`,
  `pki/gen-csr.sh` en de workflow (override via `ZAD_PROJECT` / `vars.ZAD_PROJECT_ID_UITVRAAG`). De
  **API-key-secret** `ZAD_API_KEY_FSCUITVRAAG` + `ZAD_PG_PASSWORD` worden nog gezet; de `apply`-stap
  slaat zichzelf over (main blijft groen) tot het secret er is. PR-`plan` werkt zonder.
- **Discover + data-pad** — vervolg (op ZAD, tegen echte directory + magazijn-a).
- **Contract (ServiceConnectionGrant)** — vervolg (via de manager-API of de controller-UI).
- **outway-env-namen** — verifiëren tegen de `federatedserviceconnectivity/outway`-image bij de
  eerste host-run (`outway serve --help` / OpenFSC `helm/charts`-outway-values); cert-paden en
  hostnamen liggen vast.
