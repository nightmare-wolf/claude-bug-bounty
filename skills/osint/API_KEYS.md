# OSINT API Keys

Fill in the **API Key** column with your key for any source you want active. Leave a row
blank to skip that source — the OSINT engine degrades gracefully and just omits it, falling
back to a free source where one exists (see the **Free fallbacks** column).

When `/osint` runs, this file is the reference for which keyed sources are available. After
filling a key here, also export it as the matching **Env Var** (the engine reads env vars,
not this file directly), e.g. `export SHODAN_API_KEY="..."` in `~/.zshrc`.

> **Never commit your real keys.** Put them in `API_KEYS_FILLED.md` (git-ignored), not here.
> This file is the blank template that stays in the repo.

## Tier 1 — Free keys worth getting (real free tier, just sign up)

| Tool / Source | Env Var | API Key | Free tier | Track | Where to get it |
|---|---|---|---|---|---|
| Shodan | `SHODAN_API_KEY` |  | Free account (limited credits) | Infra | https://account.shodan.io |
| Censys **Platform** | `CENSYS_PLATFORM_TOKEN` |  | Free account — PAT only, **no org ID needed** | Infra | https://platform.censys.io → user icon → API Access |
| Censys org ID *(paid plans only)* | `CENSYS_ORG_ID` |  | Only for Starter/Enterprise | Infra | platform.censys.io (skip on free) |
| ipinfo | `IPINFO_TOKEN` |  | Free 50k/mo | Infra | https://ipinfo.io/account/token |
| Hunter.io | `HUNTER_API_KEY` |  | Free 25/mo | People | https://hunter.io/api-keys |
| DomScan | `DOMSCAN_API_KEY` |  | Free 10k credits/mo | Corp / Infra | https://domscan.net (key prefix `dsk_`) |
| GitHub | `GITHUB_TOKEN` |  | Free | Both | https://github.com/settings/tokens |
| BuiltWith | `BUILTWITH_API_KEY` |  | **Only ~10 free lookups**, then paid | Corp | https://api.builtwith.com |

## Tier 2 — Paid (engine skips and uses a free fallback instead)

These used to be free and are now paid. **Do not pay for them for this workflow** — the engine
substitutes a free source automatically.

| Tool / Source | Env Var | Now costs | Free fallback the engine uses |
|---|---|---|---|
| SecurityTrails | `SECURITYTRAILS_API_KEY` | ~$500/mo | **RDAP** (`rdap.org`) for WHOIS — keyless |
| OpenCorporates **API** | `OPENCORPORATES_API_KEY` | €220+/mo (web login is free) | **GLEIF** + national registries + manual web login |
| OpenSanctions **API** | `OPENSANCTIONS_API_KEY` | Paid hosted | **self-host `yente`** or free **bulk data** download (CC-licensed) |
| HaveIBeenPwned | `HIBP_API_KEY` | ~$60/yr | **Hudson Rock** free infostealer API (keyless) |

## No key needed (work out of the box)

| Tool / Source | Track | What it does |
|---|---|---|
| **RDAP** (`rdap.org`) | Infra / Corp | Structured WHOIS — registrar, dates, registrant org (replaces SecurityTrails) |
| **Hudson Rock** (`cavalier.hudsonrock.com`) | People / Corp | Free infostealer-infection exposure by email/domain/username/IP (replaces HIBP) |
| **ipwho.is** | Infra | Free no-key IP → ASN / org / geo (replaces ipinfo) |
| DNS SaaS fingerprint (`dig`) | Corp | MX / SPF / DMARC / verification TXT → vendor stack |
| BGPView | Infra / Corp | ASN / prefix / netblock ownership |
| GLEIF | Corp | LEI → legal name, parent / child (free OpenCorporates substitute) |
| OpenOwnership | Corp | Beneficial ownership register |
| DNSDumpster | Infra | DNS / netblock mapping |
| Shodan InternetDB | Infra | Keyless passive host services / CPEs |
| maigret | People | Username across 3000+ sites |
| sherlock | People | Username across 400+ sites |
| holehe | People | Which sites an email is registered on |
| socialscan | People | Account / username availability |
| PhoneInfoga | People | Phone carrier / region footprint |
| theHarvester (core) | Both | Emails / hosts from search engines |
| recon-ng (core) | Both | Modular recon marketplace |
| SpiderFoot (core) | Both | 200+ module aggregator |
| exiftool | Meta | Document metadata (author / GPS / software) |
| Google dorking | Both | Manual document / email / profile discovery |

## More free sources worth using manually (no engine wrapper yet)

| Source | Track | Use |
|---|---|---|
| **SEC EDGAR** (`data.sec.gov`) | Corp | US public-company filings, officers, ownership — free API, no key |
| **UK Companies House** | Corp | UK company registry — free API (free key at developer.company-information.service.gov.uk) |
| **OCCRP Aleph** (`aleph.occrp.org`) | Corp / People | Cross-border investigative dataset search — free account |
| **Wayback / CDX** (`web.archive.org`) | Both | Historical pages, past tech stack, deleted content — free |
| **AlienVault OTX** | Infra | Passive DNS, threat context — free key |
| **URLScan.io** | Infra / Corp | Page tech + domain relationships — free key |
| **PeeringDB** | Infra | Org → network / facility ownership — free |
| **bgp.he.net** (Hurricane Electric) | Infra | ASN / prefix browser — free, no key |
| **IntelligenceX** (`intelx.io`) | Both | Leak / pastebin / darkweb index — free tier key |

> **Minimum viable: none.** The free sources cover both tracks end to end. Worth getting for a
> coverage boost: **Shodan · Censys Platform PAT · GitHub token** (all genuinely free). Skip every
> Tier-2 paid source — the engine already falls back to RDAP / Hudson Rock / ipwho.is / GLEIF.
