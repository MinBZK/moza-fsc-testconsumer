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

Zie `deploy/zad/README.md`. Kort: eigen ZAD-project `mpfuc-84g` (deployment `test`) + eigen API-key
(secret `ZAD_API_KEY_FSCUITVRAAG`); `upsert-peer.sh` beheert deployment + componenten + images;
cert-attachments + "Publicatie op het web" zijn UI-only.

## Licentie

[EUPL v1.2](LICENSE).
