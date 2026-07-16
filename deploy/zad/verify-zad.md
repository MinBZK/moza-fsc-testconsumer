# Verificatie ná apply — uitvraag-org-peer op ZAD

> Draaiboek: wat een mens ná een geslaagde `upsert-peer.sh apply` + cert-attachments (zie
> `cert-manifest.md`) nog controleert.

## Volgorde

1. `upsert-peer.sh apply` gedraaid → deployment + componenten bestaan in het eigen ZAD-project,
   elk met zijn `ports`-array (uvrmgr `8443,9443,9444`; uvrctl `8080,9443,9444`; uvrout/uvrtxlog
   `8443`) zodat de interne mTLS-poorten een cluster-Service (`test-<comp>:<poort>`) krijgen.
2. Cert-attachments gemount (zie `cert-manifest.md`) + "Publicatie op het web"
   (passthrough-TLS, modus 2) op uvrmgr/uvrout ingesteld in de ZAD-UI.
3. Componenten herstart en boot-logs foutloos (zie `cert-manifest.md`, laatste sectie) — in het
   bijzonder GEEN `x509: certificate signed by unknown authority` meer op de controller: die
   bereikt de manager nu intern op `test-uvrmgr:9443` (interne-PKI) i.p.v. de `:443`-group-ingress.

## (a) Announce — consumer-OIN vindbaar in de directory

Verwacht gedrag (analoog aan `deploy/local/smoke-announce.sh`, maar tegen de
ZAD-directory-DB i.p.v. de lokale compose-postgres):

```bash
# Via de uvrmgr-mesh-host (:443), met de group-cert als client-cert:
curl -sS --cert <group-cert> --key <group-key> --cacert <group-root> \
  "https://<dirmgr-host-op-ZAD>/v1/peers" | jq '.[] | select(.id == "00000000000000000020")'
```

Verwacht: één entry met `id: "00000000000000000020"` en een `manager_address` die eindigt op
`:443` en het uvrmgr-hostpatroon (`uvrmgr-<deployment>-<project>.<base-domain>`) bevat.

Alternatief (UI): log in op de directory-UI (repo A's `dirui`-component) en zoek de peer op OIN.

## (b) Discover + data-pad — vervolg op ZAD

Buiten scope van deze levering: `berichtenmagazijn` discoveren in de catalogus en het echte
data-pad (`uvrout → inway → berichtenmagazijn`) bewijs je op ZAD tegen de échte directory + de
draaiende magazijn-a-peer (`moza-fsc-org-a`). Dat vereist een geaccepteerd afnemer-contract
(ServiceConnectionGrant) — nog niet onderdeel van dit ontwerp.

## Acceptatiecriteria — afvinklijst

- [ ] Peer (echte OIN) draait op ZAD: manager + controller + outway + txlog + DB (project-isolatie)
- [ ] Peer heeft een geldige group-cert (getekend onder fsc-testnet's group-CA)
- [ ] Peer meldt zich aan bij de directory (announce)
- [ ] Discover + contract + data-pad: vervolgwerk (zie hierboven), niet in deze afvinklijst

Elk vinkje vereist een mens met ZAD-toegang, gegenereerde certs en een draaiende peer.
