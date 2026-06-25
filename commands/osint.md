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
   Censys, SecurityTrails, BuiltWith, exiftool, SpiderFoot/recon-ng for breadth).
4. Skips any source whose tool/API key is missing (degrades gracefully) and notes the gap.
5. Dedupes entities and builds a Mermaid entity-relationship graph.
6. Writes a **versioned dossier** to the assessment directory (with a delta if one exists).

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

First read `skills/osint/API_KEYS.md` — the user fills in keys there. Export the matching env
vars for any filled-in row. Then run `./tools/osint_engine.sh --keys` and tell the user which
sources are live vs skipped. If high-value keys are missing (Shodan, Censys,
SecurityTrails, GitHub token), mention them — the user has offered to obtain keys.

### Step 3: Run the engine

```bash
./tools/osint_engine.sh --seed "<seed>" --track <people|corp|both>
# Output → osint/<track>/<slug>/   (per-source files + summary.json)
```

For breadth, optionally drive SpiderFoot (passive modules) or recon-ng as documented in the
skill. Verify any aggregator hit with its targeted single-purpose tool before trusting it.

### Step 4: Build the entity graph

Assemble unique entities into a Mermaid `graph TD`, edges labeled by the transform/source,
colored by class (person/org/infra/risk). Prune dead infra branches. See the skill's
**ENTITY-RELATIONSHIP GRAPH** section for the template.

### Step 5: Write the versioned dossier

- No prior report → `{Subject}_OSINT_Dossier.md`
- One exists → `{Subject}_OSINT_Dossier_2.md` with a **delta vs prior** section.

Use the dossier template from the skill (Executive Summary → Entity Graph → People → Corporate
→ Infra Ownership → Sanctions/PEP → Source Log → OPSEC Notes → Next Steps).

## Output location

Dossier goes to the current assessment directory. If none exists, ask the user where to save.
Raw per-source output stays under `osint/<track>/<slug>/`.
