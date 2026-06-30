---
name: osint
description: People + corporate OSINT intelligence skill — Maltego-style entity transforms over free/open-source sources. Profiles humans (emails, usernames, social, breach exposure, phone) and organizations (company registries, beneficial ownership, sanctions/PEP, LEI, ASN/BGP ownership, tech footprint). Wraps theHarvester, SpiderFoot, recon-ng, maigret, sherlock, holehe, GHunt, PhoneInfoga, Hudson Rock (free infostealer exposure), OpenCorporates, OpenOwnership, OpenSanctions, GLEIF, DomScan (WHOIS + typosquatting/phishing-surface + domain reputation), Shodan, Censys Platform, RDAP (keyless WHOIS), DNSDumpster, BuiltWith, BGPView, ipwho.is, exiftool, Claude WebSearch/WebFetch, and Google dorking. Builds a Mermaid entity-relationship graph. Use for attribution, third-party/vendor due diligence, phishing-surface mapping, executive/employee enumeration, company ownership tracing, sanctions screening, or any "who/what is behind this" question. NOT for subdomain enum or attack-surface scanning of a domain — that is web2-recon.
---

# OSINT — PEOPLE & CORPORATE INTELLIGENCE

Open-source intelligence on **humans and organizations** using only free / open-source tooling.
This skill answers *"who and what is behind this entity, and how is it connected?"* — it does
**not** map a single domain's attack surface (that is `web2-recon`).

---

## OSINT vs RECON — DO NOT CONFUSE THEM

| | `web2-recon` | `osint` (this skill) |
|---|---|---|
| **Question** | "What is the attack surface of `target.com`?" | "Who/what is behind this entity and how is it connected?" |
| **Subjects** | One domain's hosts, URLs, params, ports | People, companies, owners, ASNs, brands, emails, usernames |
| **Examples** | subfinder, httpx, katana, nuclei, naabu, ffuf, gau | theHarvester, SpiderFoot, OpenCorporates, OpenSanctions, maigret, Shodan |
| **Output** | Live hosts + classified URL list | Entity-relationship graph + intel dossier |

**Hard rule:** never run subdomain enumeration, live-host probing, URL crawling, directory
fuzzing, or nuclei from this skill. Those belong to `web2-recon`. If you need them, hand off.
**No tool used by web2-recon is reused here.**

---

## WHEN TO USE

- Attribution: "who owns/operates this infrastructure, brand, or wallet-adjacent identity?"
- Phishing-surface mapping: employees, emails, and naming convention of a target org
- Executive / personnel enumeration for a bug bounty program's parent company
- Third-party / vendor / supply-chain due diligence
- Company ownership tracing (parent → subsidiary → beneficial owner)
- Sanctions / PEP screening of a counterparty (Web3 KYC, exchange listings)
- Breach-exposure check on an in-scope email or account
- Building the "Reporter background / context" section of a report

---

## SETUP — API KEYS

> **Key reference file:** `skills/osint/API_KEYS.md` holds a fill-in table of every keyed
> source. Check it at the start of every run to see which keys the user has provided, then
> export the matching env vars. Skip any source left blank.

Nothing here is required to start — the engine degrades gracefully, and where a once-free
source went paid it **falls back to a free source automatically**. Set what you have:

```bash
# ── No key required (work out of the box) ───────────────────────────────────
#   RDAP (rdap.org — WHOIS), Hudson Rock (free infostealer exposure), ipwho.is (IP/ASN),
#   DNS SaaS fingerprint (dig), BGPView, GLEIF, OpenOwnership (bulk), DNSDumpster,
#   sherlock, maigret, holehe, socialscan, PhoneInfoga, theHarvester (core),
#   recon-ng (core), SpiderFoot (core), exiftool, Google dorking, OSINT Framework

# ── Genuinely-free keys (recommended — real coverage boost) ─────────────────
export SHODAN_API_KEY=""           # free account, limited credits — internet asset intel
export CENSYS_PLATFORM_TOKEN=""    # free Censys PLATFORM account → PAT (platform.censys.io); no org ID on free
export IPINFO_TOKEN=""             # free 50k/mo — ASN/geo/org (else engine uses ipwho.is, free)
export HUNTER_API_KEY=""           # free 25/mo — email pattern + verification
export DOMSCAN_API_KEY=""          # free 10k/mo — WHOIS + typosquatting (phishing surface) + domain reputation
export GITHUB_TOKEN=""             # free — boosts GitHub org mining (tooling track)
export BUILTWITH_API_KEY=""        # ONLY ~10 free lookups then paid — DNS fingerprint covers most of this

# ── Now PAID — leave unset; the engine substitutes a free source ────────────
# SECURITYTRAILS_API_KEY   ~$500/mo   →  engine uses RDAP (rdap.org) for WHOIS
# OPENCORPORATES_API_KEY   €220+/mo   →  engine uses GLEIF + national registries (web login is free)
# OPENSANCTIONS_API_KEY    paid       →  self-host `yente` (free) or free bulk data download
# HIBP_API_KEY             ~$60/yr    →  engine uses Hudson Rock (free infostealer API)

# Persist:  echo 'export SHODAN_API_KEY="..."' >> ~/.zshrc
```

> **What to ask the user for:** only the genuinely-free keys move the needle — **Shodan,
> Censys Platform PAT, GitHub token** (all free). Do NOT ask them to pay for SecurityTrails,
> OpenCorporates API, OpenSanctions, or HIBP — the engine already falls back to RDAP, GLEIF,
> yente/bulk, and Hudson Rock. See the **API KEY CHECKLIST** at the bottom for the full
> "free / now-paid + fallback" breakdown.

> **Censys moved to the Platform.** `search.censys.io` now redirects to `platform.censys.io`.
> Auth is a single **Personal Access Token** (user icon → API Access → Create New Token); free
> accounts need only the PAT (no organization ID). The old `CENSYS_API_ID`/`CENSYS_API_SECRET`
> pair is legacy.

```bash
# Verify tooling is installed (engine auto-skips whatever is missing):
which theHarvester spiderfoot recon-ng maigret sherlock holehe socialscan \
      phoneinfoga exiftool shodan jq curl 2>/dev/null
# or: ./tools/external_arsenal.sh | grep osint
```

### Install notes (Python 3.14 toolchain quirks)

Most people-track tools install cleanly with `pipx`. Two gotchas seen on Python 3.14:

- **`shodan` CLI** imports the removed `pkg_resources`. Fix once after install:
  `pipx inject shodan "setuptools<81"` (re-adds the shim). Or install it under an older
  interpreter: `pipx install --python "$(brew --prefix python@3.10)/bin/python3.10" shodan`.
- **`spiderfoot`** is *not* on PyPI as `spiderfoot` — install via git clone + venv (its
  `requirements.txt` pins an lxml that won't build on 3.14, so relax that one pin):
  ```bash
  git clone https://github.com/smicallef/spiderfoot ~/tools/spiderfoot
  cd ~/tools/spiderfoot && python3 -m venv .venv && . .venv/bin/activate
  sed -E 's/^lxml.*/lxml>=5/' requirements.txt > /tmp/sf_reqs.txt && pip install -r /tmp/sf_reqs.txt
  # add a launcher so `spiderfoot` is on PATH:
  printf '#!/bin/bash\nexec "$HOME/tools/spiderfoot/.venv/bin/python" "$HOME/tools/spiderfoot/sf.py" "$@"\n' \
    > ~/.local/bin/spiderfoot && chmod +x ~/.local/bin/spiderfoot
  ```

General rule: if a `pipx` tool fails on the newest Python, reinstall it under 3.10/3.12
(`pipx install --python <py310> <tool>`) — that resolves most C-extension/`pkg_resources` breaks.

---

## OPSEC & LEGALITY — READ BEFORE RUNNING

OSINT touches **real people**. Treat it with more care than infrastructure scanning.

1. **Passive only by default.** Every source here queries third-party databases, *not* the
   subject. Do not pivot OSINT findings into authentication attempts, social engineering,
   or contacting individuals unless the program scope explicitly authorizes it.
2. **Stay in scope.** Personnel/PII enumeration is *out of scope* on many bug bounty
   programs. Confirm the policy allows it before profiling employees.
3. **Breach data:** use exposure **counts and source names** for risk signal — do not
   collect, store, or paste plaintext credentials into a report.
4. **Minimize + purge.** Keep only what supports the finding. Don't hoard dossiers on people.
5. **Attribution ≠ accusation.** Report "associated with" / "registered to," never
   "is guilty of." Corroborate from ≥2 independent sources before asserting a link.
6. **Sanctions/PEP hits are leads, not verdicts** — name collisions are common; verify DOB,
   jurisdiction, and identifiers before reporting a match.

---

## THE MALTEGO MODEL — ENTITIES, TRANSFORMS, GRAPH

This skill mimics Maltego's mental model without the GUI. You maintain a working **graph**:
**entities** (typed nodes) connected by **transforms** (a source that turns one entity into
related entities). Pivot breadth-first, dedupe, and render the result as a Mermaid graph.

### Entity types

`PERSON` · `EMAIL` · `USERNAME` · `PHONE` · `ORG/COMPANY` · `DOMAIN` · `IP` · `ASN` ·
`NETBLOCK` · `CERT` · `SOCIAL_PROFILE` · `DOCUMENT` · `BREACH` · `LEI` · `OWNER` ·
`SANCTION_ENTITY` · `TOOL/SAAS` · `WALLET/ADDRESS`

### Transform catalog (entity → transform → output)

| From entity | Transform (source) | To entity | Key? |
|---|---|---|---|
| DOMAIN | theHarvester (emails/names/hosts from search engines) | EMAIL, PERSON | free* |
| DOMAIN | Hunter.io (email pattern + people) | EMAIL, PERSON | free-tier |
| DOMAIN | **RDAP** (`rdap.org` — structured WHOIS, keyless) | OWNER, EMAIL | free |
| DOMAIN | **DomScan** (WHOIS + **typosquatting**/phishing surface + reputation) | OWNER, RISK, ORG | free 10k/mo |
| DOMAIN | ~~SecurityTrails~~ (now ~$500/mo — use RDAP instead) | OWNER, EMAIL, IP | paid |
| DOMAIN | BuiltWith (tech profile + relationships) | ORG, DOMAIN | ~10 free then paid |
| DOMAIN | **DNS SaaS fingerprint** (MX/SPF/DMARC/verification TXT → vendors) | TOOL/SAAS, ORG | free |
| ORG/DOMAIN | **GitHub org mining** (repos → languages, CI configs) | TOOL/SAAS, PERSON | free* |
| ORG/DOMAIN | **Wayback / StackShare / SecurityTrails history** (past tooling) | TOOL/SAAS (retired) | free/free-tier |
| TOOL/SAAS | **Ownership dork** (LinkedIn admin titles, CODEOWNERS, aliases) | PERSON, OWNER | free |
| DOMAIN | DNSDumpster / HackerTarget | IP, NETBLOCK | free |
| EMAIL | holehe (which sites that email is registered on) | SOCIAL_PROFILE | free |
| EMAIL | socialscan (account/username availability) | SOCIAL_PROFILE | free |
| EMAIL | **Hudson Rock** (infostealer-infection exposure, keyless) | BREACH | free |
| EMAIL | ~~HIBP~~ (now ~$60/yr — Hudson Rock covers exposure free) | BREACH | paid |
| EMAIL | GHunt (Google account → name, photo, reviews) | PERSON, SOCIAL_PROFILE | free** |
| USERNAME | maigret (3000+ sites) | SOCIAL_PROFILE, PERSON | free |
| USERNAME | sherlock (400+ sites) | SOCIAL_PROFILE | free |
| PERSON | CrossLinked / LinkedIn pattern → corp email format | EMAIL | free |
| PHONE | PhoneInfoga (carrier, region, footprint) | ORG, SOCIAL_PROFILE | free |
| ORG/COMPANY | ~~OpenCorporates API~~ (now €220+/mo; web login free) | OWNER, PERSON, ORG | paid API |
| ORG/COMPANY | GLEIF (LEI → legal name, parent/child) — free OpenCorporates substitute | LEI, ORG | free |
| ORG/COMPANY | OpenOwnership (beneficial ownership graph) | OWNER, PERSON | free |
| ORG/DOMAIN | **Hudson Rock** (corporate infostealer exposure, keyless) | BREACH, PERSON | free |
| PERSON/ORG | OpenSanctions: ~~hosted API~~ paid → **self-host `yente` / free bulk** | SANCTION_ENTITY | free (self-host) |
| DOMAIN/IP | BGPView (ASN, prefix, org owner, peers) | ASN, NETBLOCK, ORG | free |
| IP | Shodan InternetDB (keyless) / Censys **Platform** (free PAT) | ORG, CERT, DOMAIN | free / free-tier |
| IP | ipinfo (token) **or ipwho.is** (keyless fallback) | ORG, ASN | free |
| CERT | Censys cert search (SAN → siblings) | DOMAIN, ORG | free-tier |
| any | SpiderFoot (200+ module aggregator) | * | free*** |
| any | recon-ng (modular marketplace) | * | free*** |
| DOCUMENT | exiftool (author, software, GPS, timestamps) | PERSON, USERNAME | free |
| any | **Claude `WebSearch`** (live open-web search + reasoning) | PERSON, ORG, EMAIL, * | free |
| any | **Claude `WebFetch`** (read a page → extract the fact; execute emitted dorks) | PERSON, OWNER, TOOL | free |
| any | Google dorking | DOCUMENT, EMAIL, SOCIAL_PROFILE | free |

\* theHarvester core is free; some engines want keys.  ** GHunt needs a Google cookie; OpenSanctions self-host `yente` is free.  *** core free, individual modules may want API keys.

### Pivot discipline (so the graph stays finite)

- **Breadth-first, depth ≤ 3** from the seed unless something is high-value.
- **Dedupe** every new entity against the graph before transforming it again.
- **Stop a branch** when it only yields generic infra (CDN IPs, shared hosting, parked domains).
- **5-minute rule (OSINT variant):** if a seed produces no person, no org link, and no
  unique infra after ~5 min of pivoting, mark it cold and move on.

---

## TRACK A — PEOPLE OSINT

Goal: from a seed (name, email, username, or phone) build a person profile and their
account footprint. **Use exposure as risk signal; never collect credentials.**

```bash
SEED_EMAIL="jane.doe@target.com"
SEED_USER="janedoe"
OUT="osint/people/$(echo "$SEED_USER" | tr -cd 'a-z0-9')"
mkdir -p "$OUT"

# 1) Email → where is it registered?  (holehe = no key, passive)
holehe "$SEED_EMAIL" --only-used > "$OUT/holehe.txt" 2>/dev/null

# 2) Email/username availability across networks (socialscan = no key)
socialscan "$SEED_EMAIL" "$SEED_USER" > "$OUT/socialscan.txt" 2>/dev/null

# 3) Username → social profiles across thousands of sites (maigret = no key)
maigret "$SEED_USER" --no-progressbar --timeout 10 -T \
        --folderpath "$OUT/maigret" 2>/dev/null

# 4) Username → 400+ sites (sherlock = no key) — good cross-check vs maigret
sherlock "$SEED_USER" --timeout 10 --print-found \
         --folderpath "$OUT" 2>/dev/null

# 5) Google account intel from an email (GHunt — needs a Google cookie file once)
#    ghunt email "$SEED_EMAIL"   # → display name, profile photo, maps reviews, calendar

# 6) Exposure signal — count/metadata only, never plaintext
#    PRIMARY = Hudson Rock infostealer API (FREE, no key):
curl -s "https://cavalier.hudsonrock.com/api/json/v2/osint-tools/search-by-email?email=$SEED_EMAIL" \
  | jq '{message, stealer_count: (.stealers|length)}'   # infection COUNT only, no creds
#    HIBP is now ~$60/yr — only if the user already has a key:
#    curl -s -H "hibp-api-key: $HIBP_API_KEY" \
#      "https://haveibeenpwned.com/api/v3/breachedaccount/$SEED_EMAIL?truncateResponse=true" \
#      | jq -r '.[].Name'   # report breach NAMES + counts only

# 7) Corp email-format inference from a name (no creds, just the pattern)
#    CrossLinked scrapes public LinkedIn → builds first.last@domain style guesses
#    crosslinked -f '{first}.{last}@target.com' "Target Company" -o "$OUT/email_format.txt"
```

**People output:** account footprint (which platforms), likely real name, breach exposure
*signal*, and corp email naming convention — all feeding `SOCIAL_PROFILE`/`PERSON`/`EMAIL`
nodes in the graph.

---

## TRACK B — CORPORATE OSINT

Goal: from an org/brand/domain, establish legal identity, ownership chain, sanctions status,
and the network/tech footprint it controls.

```bash
COMPANY="Acme Holdings Ltd"
JURIS="gb"                      # ISO country for registry scoping
DOMAIN="acme.com"
OUT="osint/corp/$(echo "$DOMAIN" | tr -cd 'a-z0-9.')"
mkdir -p "$OUT"

# 1) Company registry — officers, status, filings
#    NOTE: OpenCorporates API is now PAID (€220+/mo). The web UI (opencorporates.com) is free to
#    browse. For a free API, prefer GLEIF (step 3) + national registries: SEC EDGAR (US public),
#    UK Companies House (free key), or the local company register. Keyless OpenCorporates returns
#    only limited results, kept here as a best-effort:
curl -s "https://api.opencorporates.com/v0.4/companies/search?q=$(printf %s "$COMPANY" | jq -sRr @uri)&jurisdiction_code=$JURIS${OPENCORPORATES_API_KEY:+&api_token=$OPENCORPORATES_API_KEY}" \
  | jq -r '.results.companies[]?.company | "\(.name) | \(.company_number) | \(.jurisdiction_code) | \(.current_status)"' \
  | tee "$OUT/opencorporates.txt"
#    US public company (free, no key):
#    curl -s "https://data.sec.gov/submissions/CIK##########.json" -H 'User-Agent: osint you@example.com'

# 2) Beneficial ownership graph  (OpenOwnership Register, free)
curl -s "https://register.openownership.org/search.json?q=$(printf %s "$COMPANY" | jq -sRr @uri)" \
  | jq -r '.[]?' 2>/dev/null | tee "$OUT/openownership.json" >/dev/null
#   Or download the bulk Beneficial Ownership Data Standard (BODS) statements — fully free.

# 3) Legal Entity Identifier → legal name + parent/child relationships  (GLEIF, free, no key)
curl -s "https://api.gleif.org/api/v1/lei-records?filter[entity.legalName]=$(printf %s "$COMPANY" | jq -sRr @uri)&page[size]=5" \
  | jq -r '.data[] | "\(.attributes.lei) | \(.attributes.entity.legalName.name) | \(.attributes.entity.legalAddress.country)"' \
  | tee "$OUT/gleif.txt"

# 4) Sanctions / PEP / watchlist screening  (OpenSanctions hosted, or self-host `yente` free)
curl -s "https://api.opensanctions.org/search/default?q=$(printf %s "$COMPANY" | jq -sRr @uri)" \
     ${OPENSANCTIONS_API_KEY:+-H "Authorization: ApiKey $OPENSANCTIONS_API_KEY"} \
  | jq -r '.results[] | "\(.caption) | \(.schema) | datasets=\(.datasets|join(","))"' \
  | tee "$OUT/opensanctions.txt"
# Self-host (no key, no rate limit): docker run -p 8000:8000 ghcr.io/opensanctions/yente

# 5) ASN / netblock ownership for the org's infrastructure  (BGPView, free, no key)
curl -s "https://api.bgpview.io/search?query_term=$(printf %s "$COMPANY" | jq -sRr @uri)" \
  | jq -r '.data.asns[]? | "AS\(.asn) | \(.name) | \(.description)"' \
  | tee "$OUT/bgpview_asns.txt"
# Then expand each ASN → prefixes it announces:
#   curl -s "https://api.bgpview.io/asn/AS12345/prefixes" | jq -r '.data.ipv4_prefixes[].prefix'

# 6) Tech footprint of the brand  (BuiltWith — free web lookup, key for API/relationships)
#    https://builtwith.com/$DOMAIN   (relationships tab links sibling sites by analytics IDs)
#    curl -s "https://api.builtwith.com/v21/api.json?KEY=$BUILTWITH_API_KEY&LOOKUP=$DOMAIN"

# 7) WHOIS → registrar, dates, registrant org  (RDAP — free, keyless; replaces SecurityTrails)
curl -s -L "https://rdap.org/domain/$DOMAIN" \
  | jq '{registrar: [.entities[]?|select(.roles[]?=="registrar")|.vcardArray[1][]?|select(.[0]=="fn")|.[3]][0],
         events: [.events[]? | "\(.eventAction): \(.eventDate)"]}' \
  | tee "$OUT/rdap_whois.json"
#    SecurityTrails (DNS/WHOIS *history*) is now ~$500/mo — only if the user already pays:
#    curl -s -H "APIKEY: $SECURITYTRAILS_API_KEY" "https://api.securitytrails.com/v1/domain/$DOMAIN/whois"
```

**Corporate output:** legal name + registry number, parent/subsidiary chain, beneficial
owners, sanctions/PEP status, owned ASNs/netblocks, and brand tech footprint — feeding
`ORG`/`OWNER`/`LEI`/`SANCTION_ENTITY`/`ASN` nodes.

---

## TRACK B+ — CORPORATE TOOLING & TECH-STACK INTELLIGENCE (past + present + ownership)

Goal: enumerate **every tool / software / SaaS / vendor a company uses — past AND present** —
each backed by a **source link + snippet**, then map **who owns/administers each tool**. This
runs automatically inside the corporate track (`corp_tooling()` in the engine) and **always
produces a `REPORT.md`** with a Tooling Inventory + Ownership/Access map.

### 1. DNS SaaS fingerprinting (keyless — strongest present-tooling signal)

A company's DNS records leak its SaaS stack because vendors require verification/SPF records.
The engine resolves `MX`, root `TXT`, and `_dmarc` TXT, then maps tokens → vendors:

| DNS signal | Reveals |
|---|---|
| `MX` host | Email provider (Google Workspace, Microsoft 365, Proofpoint, Mimecast, Zoho…) |
| SPF `include:` | Any SaaS that sends mail as the domain (Salesforce, Zendesk, Mailchimp, SendGrid, HubSpot, Marketo, Atlassian, Intercom…) |
| `_dmarc` `rua=`/`ruf=` | DMARC processor (Dmarcian, Valimail, Agari, Red Sift, MXToolbox…) |
| `*-site/domain-verification` TXT | SaaS sign-ups (Slack, Zoom, DocuSign, Adobe, Figma, Dropbox, Atlassian, Stripe, Notion, Miro, OneTrust, Canva, Webex…) |

```bash
# What the engine runs (reproduce manually):
dig +short MX  acme.com
dig +short TXT acme.com           # SPF includes + verification tokens
dig +short TXT _dmarc.acme.com    # DMARC processor
# Each matched record IS the source + snippet for that tool in the report.
```

### 2. Present + historical tech stack

- **Present:** GitHub org repos → languages + CI configs (`.github/workflows`); BuiltWith API
  (keyed) or the free `builtwith.com/<domain>` lookup; StackShare profile.
- **Past:** Wayback snapshots of the careers/jobs pages and StackShare profile; SecurityTrails
  **historical TXT records** (keyed) — retired verification tokens reveal SaaS since dropped.
  The engine emits ready-to-click Wayback/StackShare/BuiltWith pointer URLs every run.

### 3. Ownership / access mapping (who administers each tool)

For every discovered tool the engine emits a **ready-to-click dork** so you can find the human
who owns it — never auto-scraped, just URLs you click:

- LinkedIn title dorks: `site:linkedin.com/in "Salesforce Admin" "Acme"`, `"Okta"`, `"Workday"`…
- GitHub `CODEOWNERS` + maintainers + `.github/workflows` search across the org.
- Tool email aliases (`admin@`, `it@`, `helpdesk@`) and leaked contact sheets.

### 4. Every finding row carries provenance

The Tooling Inventory in `REPORT.md` is: **Tool · Status (present/past) · Category · Confidence
(# independent signals) · Source link · Snippet (the actual record/excerpt).** Confidence rises
when more than one signal (e.g. both an SPF include *and* a verification TXT) points to the same
vendor.

```bash
# Run it (corp tooling + always-on report are automatic on the corp/both tracks):
./tools/osint_engine.sh --seed acme.com --track corp
#   → osint/corp/<slug>/REPORT.md          (Tooling Inventory + Ownership map, always written)
#   → osint/corp/<slug>/corp_tooling.tsv   (raw rows: status·category·tool·source·snippet)
#   → osint/corp/<slug>/ownership_dorks.txt + past_tooling_pointers.txt
```

> **Scope note:** tool-ownership mapping enumerates named employees — confirm the program
> permits personnel OSINT before acting on those dorks. Discovering the *stack* (DNS/GitHub) is
> passive third-party data; clicking the people-dorks profiles individuals.

---

## INFRASTRUCTURE INTEL (ownership, not attack-surface)

This is the OSINT *ownership* angle on infrastructure — **who runs it**, not what's exploitable
on it. (Exploit-surface mapping stays in `web2-recon`.)

```bash
IP="203.0.113.10"

# Shodan host intel — open services as INTEL, org, hostnames, certs  (free-tier key)
shodan host "$IP" 2>/dev/null | tee "osint/infra/$IP.shodan.txt"
#   Or keyless InternetDB (no key, passive): https://internetdb.shodan.io/$IP
curl -s "https://internetdb.shodan.io/$IP" | jq '.'

# Censys PLATFORM host + cert pivots — SAN names reveal sibling domains  (free PAT)
#   platform.censys.io (free account → Personal Access Token). New Platform API:
#   curl -s -H "Authorization: Bearer $CENSYS_PLATFORM_TOKEN" \
#     "https://api.platform.censys.io/v3/global/asset/host/$IP"

# ipinfo (token) — ASN, org, geo;  or ipwho.is free/keyless fallback
if [ -n "${IPINFO_TOKEN:-}" ]; then
  curl -s "https://ipinfo.io/$IP/json?token=$IPINFO_TOKEN" | jq '.'
else
  curl -s "https://ipwho.is/$IP" | jq '{org: .connection.org, asn: .connection.asn, isp: .connection.isp}'
fi

# BGPView — IP → prefix → ASN → org owner, and peers
curl -s "https://api.bgpview.io/ip/$IP" \
  | jq -r '.data.prefixes[]? | "\(.prefix) | AS\(.asn.asn) \(.asn.name) | \(.asn.description)"'
```

---

## AGGREGATORS — SPIDERFOOT & RECON-NG

When you want one tool to fan out across many transforms automatically, drive an aggregator.
These overlap many single-purpose tools above; use them for **breadth**, then verify hits
with the targeted tool.

### SpiderFoot (200+ modules — closest free Maltego analogue)

```bash
# Headless scan via CLI (passive modules only = safe, no target contact)
spiderfoot -s "$SEED" -t EMAILADDR,DOMAIN_NAME,HUMAN_NAME,COMPANY_NAME \
           -m sfp_dnsresolve,sfp_whois,sfp_hunter,sfp_shodan,sfp_bgpview,sfp_opencorporates \
           -o csv > "osint/spiderfoot_$SEED.csv" 2>/dev/null

# Or run the web UI for the interactive graph (its built-in correlation view):
#   spiderfoot -l 127.0.0.1:5001   → open http://127.0.0.1:5001
# Set module API keys in Settings (Shodan, Hunter, SecurityTrails, etc.) — all optional.
```

### recon-ng (modular marketplace, recon-ng ≈ scripted Maltego)

```bash
# Non-interactive resource script
cat > /tmp/recon.rc <<'RC'
marketplace install all
keys add shodan_api <SHODAN_API_KEY>
keys add github_api <GITHUB_TOKEN>
workspaces create target
modules load recon/domains-hosts/hackertarget
options set SOURCE target.com
run
modules load recon/companies-multi/whois_miner
run
modules load recon/profiles-profiles/profiler
run
RC
recon-ng -r /tmp/recon.rc
# Export the workspace to feed the graph:  modules load reporting/csv; run
```

---

## TRACK C — CLAUDE AS AN OSINT ANALYST (web search + reasoning, not just orchestration)

**Claude is itself an OSINT transform, not only the thing that runs the shell engine.** Many
sources have no CLI/API wrapper — news, press releases, LinkedIn/job posts, court & registry
filings, blog/forum/social context, breach writeups, conference talks, data-broker pages,
archived snapshots. Claude reaches those with its **`WebSearch`** and **`WebFetch`** tools and,
crucially, **reasons over and corroborates** everything the engine returns. Run this *alongside*
the engine and merge the results into one graph + dossier.

### What Claude does that the engine can't

1. **Open-web search** — `WebSearch` for the entity across the live web (the engine only hits
   fixed APIs). Find real names, roles, affiliations, events, mentions, leaks.
2. **Execute the engine's emitted dorks** — `ownership_dorks.txt` and `past_tooling_pointers.txt`
   are *URLs*. Claude turns them into findings: `WebFetch` / `WebSearch` each one and extract the
   named admin, the StackShare stack, the Wayback careers snapshot, etc.
3. **Read & interpret** — `WebFetch` a promising result and pull the specific fact (the director's
   name, the parent company, the tool an employee says they administer). Interpret JSON the engine
   saved (`hudsonrock*.json`, `rdap_domain.json`) into plain findings.
4. **Corroborate** — require **≥2 independent sources** before asserting a link; Claude is the one
   that judges whether two sources are truly independent.
5. **Synthesize** — dedupe entities, assign confidence (# sources), and write the narrative,
   graph, and Next-Steps.

### Claude search-plan templates (run with `WebSearch`, then `WebFetch` the hits)

| Seed | Searches Claude runs |
|---|---|
| **Person / name** | `"Full Name" <company>`; `"Full Name" linkedin`; `"Full Name" (CTO OR founder OR director)`; `"Full Name" email OR contact`; `"Full Name" conference OR talk OR podcast` |
| **Email** | the address in quotes; the local-part as a username; `"email" breach OR leak OR dump`; the domain's email-format pattern |
| **Username** | `"handle"` across `site:github.com`, `site:reddit.com`, `site:x.com`, `site:keybase.io`; reuse of the handle on forums |
| **Company** | `"Company" (CEO OR founder OR "board of directors")`; `"Company" acquisition OR subsidiary OR "parent company"`; `"Company" data breach`; `"Company" lawsuit OR SEC OR filing`; `"Company" layoffs OR funding` |
| **Company tooling/owner** | execute each `ownership_dorks.txt` URL; `site:linkedin.com/in "<Vendor> Admin" "<Company>"`; `"<Company>" "we use" <vendor>`; `"<Company>" careers <tech>` (past + present) |
| **Domain** | `"domain" owner OR registrant`; `site:domain (team OR about OR leadership)`; news mentioning the domain; Wayback of `/about`, `/team`, `/careers` |
| **Phone** | the number in several formats; `"number" (spam OR scam OR business)`; reverse-lookup result pages |

### Hard rules for Claude's participation

- **Passive & third-party only.** Search engines and archives, *not* the subject's own systems.
  Never use `WebFetch` to probe the target's infrastructure for vulnerabilities — that is recon,
  and it is out of scope for this skill. Reading a company's *public* About/Team page is fine.
- **Confirm scope** before naming individuals (personnel OSINT is excluded on many programs).
- **Attribution ≠ accusation** — "associated with", corroborated by ≥2 sources; never "is guilty of".
- **Breach/exposure = metadata only** — counts, source names, infection dates; never paste creds.
- **Cite every claim** — each finding row carries the source URL Claude read.

### How it fits the run

```
engine (shell)  ─┐
                 ├─►  Claude merges →  Mermaid graph  +  versioned dossier
Claude WebSearch/WebFetch + executed dorks ─┘
```

Claude runs its searches, executes the engine's dork/pointer URLs, fetches and reads the best
results, then folds the new `PERSON/EMAIL/ORG/TOOL/OWNER` entities into the same graph with source
links and confidence. The engine's `REPORT.md` ends with a **"For the Claude analyst — run these
next"** block listing exactly which dorks/pointers to execute.

---

## DOCUMENT METADATA & GOOGLE DORKING

```bash
# Pull public docs, then strip metadata for authorship/software/GPS leaks
exiftool -Author -Creator -Producer -Software -GPSLatitude -GPSLongitude \
         -CreateDate -ModifyDate ./downloads/*.pdf ./downloads/*.docx ./downloads/*.jpg

# Google dorks (run manually in a browser — do not automate scraping aggressively)
#   site:target.com filetype:pdf                  → leaked internal docs
#   site:target.com (employee | staff | "@target.com")
#   intext:"@target.com" filetype:xlsx            → contact spreadsheets
#   site:linkedin.com/in "Target Company"         → employee enumeration
#   site:github.com "target.com"                  → repos referencing the org
#   "target.com" site:pastebin.com                → leaked pastes
#   site:trello.com OR site:s3.amazonaws.com "Target Company"
```

For curated dork lists and the full source map, see the **OSINT Framework**
(https://osintframework.com) and `skills/security-arsenal/REFERENCES.md`.

---

## ENTITY-RELATIONSHIP GRAPH (Mermaid — Maltego-style output)

Render the working graph as Mermaid so it shows inline in the report/terminal. Group by
entity type, label edges with the transform that produced them.

```mermaid
graph TD
  SEED["DOMAIN: acme.com"]
  SEED -->|theHarvester| E1["EMAIL: jane.doe@acme.com"]
  SEED -->|SecurityTrails WHOIS| O1["OWNER: Acme Holdings Ltd"]
  SEED -->|BGPView| AS1["ASN: AS64500 Acme Net"]
  E1 -->|holehe| S1["SOCIAL: GitHub /janedoe"]
  E1 -->|maigret| S2["SOCIAL: Twitter @janedoe"]
  O1 -->|OpenCorporates| P1["PERSON: J. Doe (Director)"]
  O1 -->|OpenOwnership| OW1["OWNER: Doe Family Trust (75%)"]
  O1 -->|GLEIF| LEI1["LEI: 5493...  parent: Acme Group"]
  O1 -->|OpenSanctions| SAN1["SANCTION: no match ✓"]
  AS1 -->|BGPView prefixes| NB1["NETBLOCK: 203.0.113.0/24"]
  NB1 -->|Shodan/Censys| C1["CERT org=Acme → sibling: acme-staging.com"]

  classDef person fill:#fde,stroke:#a3a;
  classDef org fill:#def,stroke:#36a;
  classDef infra fill:#efe,stroke:#3a3;
  classDef risk fill:#fee,stroke:#a33;
  class P1,E1,S1,S2 person;
  class O1,OW1,LEI1 org;
  class AS1,NB1,C1 infra;
  class SAN1 risk;
```

**Build rules:** one node per unique entity (dedupe!), edge label = the transform/source,
color by class, flag risk nodes (sanctions/breach) in red. Keep it to the entities that
actually support a conclusion — prune dead infra branches.

---

## REPORT — VERSIONED OSINT DOSSIER

Write a numbered, versioned dossier to the assessment directory (same convention as
`burp-analysis` / `red-team-llm`).

> **A report is ALWAYS produced.** The engine writes a machine-built `REPORT.md` into the output
> dir on *every* run (any track) — for corporate runs it is pre-filled with the Tooling Inventory
> and Tool Ownership/Access map. Use that `REPORT.md` as the raw input and promote it into the
> polished, versioned `{Subject}_OSINT_Dossier.md` below (add the Mermaid graph + narrative).

- No prior report → `{Subject}_OSINT_Dossier.md`
- One exists → `{Subject}_OSINT_Dossier_2.md` (include a **delta vs prior** section)

### Dossier template

```markdown
# OSINT Dossier — {Subject}
**Date:** {date}  ·  **Track:** People | Corporate | Both  ·  **Analyst:** {user}
**Seed(s):** {email/username/company/domain}

## 1. Executive Summary
- What the subject is, top 3 findings, confidence per finding (High/Med/Low + # sources)

## 2. Entity Graph
[Mermaid graph from the section above]

## 3. People Findings
| Entity | Type | Source(s) | Detail | Confidence |
|---|---|---|---|---|
(account footprint, real-name links, breach EXPOSURE signal — no credentials)

## 4. Corporate Findings
| Entity | Registry/Source | Number/LEI | Status | Detail |
|---|---|---|---|---|
(legal identity, ownership chain, beneficial owners, sanctions/PEP, owned ASNs)

## 4a. Corporate Tooling & Tech-Stack Inventory (present + past)
| Tool / Vendor | Status (present/past) | Category | Confidence (# sources) | Source link | Snippet |
|---|---|---|---|---|---|
(every SaaS/vendor/software — each row MUST carry a source link + the actual record/excerpt;
pull straight from the engine's `corp_tooling.tsv` / `REPORT.md`)

## 4b. Tool Ownership / Access Map
| Tool | Owner / Admin (name, title) | Evidence (LinkedIn/CODEOWNERS/alias) | Source link |
|---|---|---|---|
(who administers each tool — resolve the engine's `ownership_dorks.txt` URLs to named people
only if the program permits personnel OSINT)

## 5. Infrastructure Ownership
| IP/ASN/Netblock | Owner Org | Source | Note |
|---|---|---|---|
(BGPView / Shodan / Censys / ipinfo — ownership, NOT exploit surface)

## 6. Sanctions / PEP Screening
| Name searched | Match? | List/Dataset | Verifier (DOB/juris/id) |
|---|---|---|---|

## 7. Source Log & Reproducibility
| Transform | Tool | Key used? | Timestamp | Result file |
|---|---|---|---|---|

## 8. OPSEC / Handling Notes
- PII minimized? credentials excluded? in-scope confirmed?

## 9. Recommended Pivots / Next Steps
- Cold branches, unverified links worth a second source, handoff-to-recon items
```

---

## API KEY CHECKLIST — SURFACE THIS TO THE USER

When the user asks "what keys do you need?", present this:

**Genuinely free — worth getting:**

| Tool / Source | Key env var | Cost | Track | Priority |
|---|---|---|---|---|
| Shodan | `SHODAN_API_KEY` | Free account (limited) | Infra | **High** |
| Censys **Platform** | `CENSYS_PLATFORM_TOKEN` | Free account, PAT only (no org ID) | Infra | **High** |
| GitHub | `GITHUB_TOKEN` | Free | Both (GitHub org mining, recon-ng) | **High** |
| ipinfo | `IPINFO_TOKEN` | Free 50k/mo (else ipwho.is, free) | Infra | Med |
| Hunter.io | `HUNTER_API_KEY` | Free 25/mo | People | Med |
| DomScan | `DOMSCAN_API_KEY` | Free 10k/mo | Corp/Infra (WHOIS, typosquatting, reputation) | Med |
| BuiltWith | `BUILTWITH_API_KEY` | ~10 free lookups then paid | Corp | Low |

**Now PAID — do NOT ask the user to buy; the engine uses the free fallback:**

| ~~Tool~~ | Env var | Now costs | Free fallback (automatic) |
|---|---|---|---|
| SecurityTrails | `SECURITYTRAILS_API_KEY` | ~$500/mo | **RDAP** (`rdap.org`) |
| OpenCorporates API | `OPENCORPORATES_API_KEY` | €220+/mo (web free) | **GLEIF** + national registries |
| OpenSanctions API | `OPENSANCTIONS_API_KEY` | paid hosted | **self-host `yente`** / free bulk |
| HaveIBeenPwned | `HIBP_API_KEY` | ~$60/yr | **Hudson Rock** (free) |

**No key needed:** RDAP · Hudson Rock · ipwho.is · DNS SaaS fingerprint · BGPView · GLEIF ·
OpenOwnership · DNSDumpster · maigret · sherlock · holehe · socialscan · PhoneInfoga ·
theHarvester(core) · recon-ng(core) · SpiderFoot(core) · exiftool · Shodan InternetDB.
**Extra free (manual):** SEC EDGAR · UK Companies House · OCCRP Aleph · Wayback · AlienVault OTX ·
URLScan · PeeringDB · bgp.he.net · IntelligenceX(free tier).

> Minimum viable: **none** (free tools cover both tracks end to end). Best ROI to ask for:
> **Shodan + Censys Platform PAT + GitHub token** (all free). Skip every paid source above —
> RDAP / GLEIF / yente / Hudson Rock already substitute for them.

---

## QUICK ROUTING

| You have… | Start with | Then pivot to |
|---|---|---|
| An email | holehe → socialscan → GHunt | maigret on derived username, breach signal |
| A username | maigret + sherlock | holehe on derived emails, profile scrape |
| A company name | OpenCorporates → GLEIF → OpenOwnership | OpenSanctions, BGPView for its ASNs |
| A company's tool/SaaS stack | DNS SaaS fingerprint → GitHub org mining | Wayback/StackShare (past), ownership dorks |
| A domain (ownership) | RDAP WHOIS → BGPView | DNS SaaS fingerprint, Censys Platform certs |
| An IP / ASN | BGPView → ipinfo/ipwho.is → Shodan InternetDB | reverse to org → GLEIF |
| A phone number | PhoneInfoga | socialscan/maigret on derived handle |
| A document | exiftool | author → maigret, dorking |
| "Just go wide" | SpiderFoot (passive modules) or recon-ng | verify each hit with its targeted tool |
| **Anything the tools miss** | **Claude `WebSearch`** (news, LinkedIn, filings, leaks) | **`WebFetch`** the best hits + execute the engine's emitted dorks |
