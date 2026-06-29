---
description: People + corporate OSINT — Maltego-style entity transforms over free/open-source sources. Profiles humans (email/username/phone → social, breach exposure) and organizations (registry, beneficial ownership, sanctions/PEP, LEI, ASN/BGP, tech footprint). Builds a Mermaid entity graph and a versioned dossier. NOT subdomain/attack-surface recon (use /recon). Usage: /osint <email|username|company|domain|ip|phone> [--people|--corp|--both]
---

# /osint

Run an OSINT investigation on a person or organization and produce an entity-relationship
graph plus a versioned dossier. Wraps the `osint` skill and `tools/osint_engine.sh`.

## Usage

```
/osint jane.doe@target.com --people
/osint "Acme Holdings Ltd" --corp
/osint target.com --both
/osint janedoe                       # username — auto-detects people track
/osint 203.0.113.10                  # IP — infra-ownership track
/osint +14155550100                  # phone — people track
```

If no argument is given, ask the user for a seed (email / username / company / domain / IP /
phone) and which track to run.

## Guardrails — read first

- This is **OSINT, not recon.** Do **not** run subdomain enum, httpx, katana, nuclei, ffuf, or
  naabu here. If the user wants attack surface, route them to `/recon`.
- **Passive only.** Every source queries third-party databases, not the subject. Do not pivot
  into auth attempts or contacting individuals.
- **Confirm scope** before profiling employees/PII — many programs exclude personnel OSINT.
- **Breach data = count + source name only.** Never collect or paste plaintext credentials.
- **Sanctions/PEP hits are leads**, not verdicts — verify identifiers before reporting a match.

## What this does

1. Classifies the seed entity type (email / username / company / domain / ip / phone).
2. Picks the track: `--people`, `--corp`, or `--both` (auto-infers if omitted).
3. Runs the matching transforms from the `osint` skill (theHarvester, holehe, socialscan,
   maigret, sherlock, OpenCorporates, OpenOwnership, GLEIF, OpenSanctions, BGPView, Shodan,
   Censys Platform, RDAP, Hudson Rock, ipwho.is, exiftool, SpiderFoot/recon-ng for breadth).
4. Skips any source whose tool/API key is missing (degrades gracefully) and notes the gap.
5. **Claude joins the search (Track C):** uses `WebSearch`/`WebFetch` to cover what the CLI tools
   can't (news, LinkedIn, filings, leaks, archives) and to **execute the engine's emitted dork/
   history URLs**, then corroborates and folds the results into the same graph + dossier.
6. **For corporate runs:** fingerprints the company's **tool/SaaS/vendor stack (past + present)**
   via DNS records (MX/SPF/DMARC/verification TXT), GitHub org mining, and Wayback/BuiltWith
   history — each finding with a **source link + snippet** — and emits **tool-ownership dorks**.
7. **Always writes a `REPORT.md`** in the output dir (every run, any track) — for corporate runs
   pre-filled with the Tooling Inventory + Tool Ownership/Access map + a "For the Claude analyst" task list.
8. Dedupes entities and builds a Mermaid entity-relationship graph.
9. Promotes `REPORT.md` into a **versioned dossier** in the assessment directory (delta if one exists).

## Steps

### Step 1: Classify the seed

| Pattern | Entity | Default track |
|---|---|---|
| contains `@` | EMAIL | people |
| starts `+` / all digits | PHONE | people |
| valid IPv4/IPv6 | IP | infra-ownership |
| has a dot, looks like a host | DOMAIN | both |
| quoted multi-word / `Ltd`,`Inc`,`GmbH` | COMPANY | corp |
| else | USERNAME | people |

### Step 2: Surface API-key status

First read `skills/osint/API_KEYS.md` (template) and `API_KEYS_FILLED.md` if present (the user's
real, git-ignored keys). Export the matching env vars for any filled-in row. Then run
`./tools/osint_engine.sh --keys` and tell the user which sources are live vs skipped.

Only the **genuinely free** keys are worth requesting: **Shodan, Censys Platform PAT, GitHub
token** (all free). Do **not** ask the user to pay for SecurityTrails (~$500/mo), OpenCorporates
API (€220+/mo), OpenSanctions, or HIBP — the engine automatically falls back to the free
equivalents: **RDAP** (WHOIS), **GLEIF** (registry), **yente/bulk** (sanctions), **Hudson Rock**
(breach exposure), **ipwho.is** (IP/ASN).

### Step 3: Run the engine

```bash
./tools/osint_engine.sh --seed "<seed>" --track <people|corp|both>
# Output → osint/<track>/<slug>/   (per-source files + summary.json)
```

For breadth, optionally drive SpiderFoot (passive modules) or recon-ng as documented in the
skill. Verify any aggregator hit with its targeted single-purpose tool before trusting it.

On corporate/both runs the engine also produces, in the output dir:
- `REPORT.md` — always written; Tooling Inventory + Ownership/Access map pre-filled.
- `corp_tooling.tsv` — raw tooling rows (status · category · tool · source · snippet).
- `ownership_dorks.txt` + `past_tooling_pointers.txt` — ready-to-click ownership/history URLs.

### Step 3.5: Claude joins the search (Track C — do NOT skip)

You (Claude) are an active OSINT source, not just the engine's runner. The shell engine only hits
fixed APIs; you reach everything else with **`WebSearch`** and **`WebFetch`**. Now:

1. **Search the open web** for the seed using the entity-type query templates in the skill's
   **TRACK C** (news, LinkedIn, registry/court filings, job posts, leaks, blogs, archives).
2. **Execute the engine's emitted URLs** — `WebFetch`/`WebSearch` each line in `ownership_dorks.txt`
   (resolve to the named admin/owner) and `past_tooling_pointers.txt` (confirm past+present tooling).
   The bottom of `REPORT.md` lists these as "For the Claude analyst — run these next".
3. **Read & interpret** the best hits and the engine's JSON (`hudsonrock*.json`, `rdap_domain.json`).
4. **Corroborate** every link with ≥2 independent sources before asserting it.

Guardrails: passive only (search engines & archives, **never** probe the subject's own systems —
that's recon), confirm scope before naming individuals, attribution ≠ accusation, exposure =
metadata only. Fold your findings into the same graph and dossier with a source URL per claim.

### Step 4: Build the entity graph

Assemble unique entities into a Mermaid `graph TD`, edges labeled by the transform/source,
colored by class (person/org/infra/risk). Prune dead infra branches. See the skill's
**ENTITY-RELATIONSHIP GRAPH** section for the template.

### Step 5: Write the versioned dossier

A `REPORT.md` already exists (the engine always writes one). Promote it into the polished,
versioned dossier — add the Mermaid graph and narrative:

- No prior report → `{Subject}_OSINT_Dossier.md`
- One exists → `{Subject}_OSINT_Dossier_2.md` with a **delta vs prior** section.

Use the dossier template from the skill (Executive Summary → Entity Graph → People → Corporate
→ **Corporate Tooling Inventory** → **Tool Ownership/Access Map** → Infra Ownership →
Sanctions/PEP → Source Log → OPSEC Notes → Next Steps). For corporate subjects the Tooling
Inventory and Ownership map are mandatory, each tooling row carrying a source link + snippet.

## Output location

Dossier goes to the current assessment directory. If none exists, ask the user where to save.
Raw per-source output stays under `osint/<track>/<slug>/`.
