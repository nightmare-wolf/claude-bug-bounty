---
description: Run full recon pipeline on a target — subdomain enum (Chaos API + subfinder), live host discovery (dnsx + httpx), URL crawl (katana + waybackurls + gau), gf pattern classification, nuclei scan. Outputs to recon/<target>/ directory. Usage: /recon target.com
---

# /recon

Run the full recon pipeline on a target and produce a prioritized attack surface.

## What This Does

1. Enumerates subdomains (Chaos API + subfinder + assetfinder) — **passive**
2. Resolves DNS and finds live hosts (dnsx + httpx) — **active**
3. Crawls URLs (katana) — **active** / historical URLs (waybackurls + gau) — **passive**
4. Classifies URLs by bug class (gf patterns) — passive text processing
5. Runs nuclei for known CVEs and misconfigs — **active**
6. Outputs prioritized attack surface summary

## Usage

```
/recon target.com
```

Or with specific focus:
```
/recon target.com --focus api
/recon target.com --focus auth
/recon target.com --fast     (skip historical URLs)
```

## Rate Limit Configuration

**Always set these before running active steps.** Active recon without rate limits
can trigger WAF bans, exhaust server resources, and put the target into a
degraded or unavailable state — which is out-of-scope behaviour on most programs.

```bash
# Conservative defaults — safe for nearly all targets
RATE_HTTP=50        # httpx: max HTTP requests/sec to live hosts
RATE_CRAWL=10       # katana: max requests/sec during crawl
RATE_NUCLEI=15      # nuclei: max requests/sec (templates can be noisy)
THREADS_HTTP=25     # httpx: concurrent threads
THREADS_CRAWL=5     # katana: concurrent crawlers
THREADS_NUCLEI=5    # nuclei: concurrent template runs
CRAWL_DELAY=100     # katana: milliseconds between requests per crawler

# Increase only if the target is a large program that has explicitly
# asked for aggressive testing, or you have explicit written permission:
# RATE_HTTP=150 RATE_CRAWL=30 RATE_NUCLEI=30
```

## Steps

### Step 1: Subdomain Enumeration — PASSIVE

Queries external APIs and databases only. Does not touch the target directly.
No rate limiting against the target is needed here.

```bash
TARGET="$1"
mkdir -p recon/$TARGET

# Chaos API (ProjectDiscovery — most comprehensive)
curl -s "https://dns.projectdiscovery.io/dns/$TARGET/subdomains" \
  -H "Authorization: $CHAOS_API_KEY" \
  | jq -r '.[]' > recon/$TARGET/subdomains.txt

# subfinder + assetfinder (passive, queries public sources only)
subfinder -d $TARGET -silent | anew recon/$TARGET/subdomains.txt
assetfinder --subs-only $TARGET | anew recon/$TARGET/subdomains.txt

echo "[+] Subdomains: $(wc -l < recon/$TARGET/subdomains.txt)"
```

### Step 2: Live Host Discovery — ACTIVE

Sends HTTP probes directly to target infrastructure. Rate limit enforced.

```bash
# DNS resolution — high rate is fine (queries resolvers, not the target)
cat recon/$TARGET/subdomains.txt \
  | dnsx -silent -r /etc/resolv.conf -t 50 \
  | tee recon/$TARGET/resolved.txt

# HTTP probing — rate limited to avoid overwhelming the target
cat recon/$TARGET/resolved.txt \
  | httpx -silent \
          -status-code -title -tech-detect \
          -rate-limit $RATE_HTTP \
          -threads $THREADS_HTTP \
  | tee recon/$TARGET/live-hosts.txt

echo "[+] Live hosts: $(wc -l < recon/$TARGET/live-hosts.txt)"
```

### Step 3: URL Crawl — ACTIVE (crawl) / PASSIVE (historical)

```bash
# --- ACTIVE: katana deep crawl — rate limited ---
# Crawls the live target. Delay + thread cap prevent request floods.
cat recon/$TARGET/live-hosts.txt | awk '{print $1}' \
  | katana -d 3 -jc -kf all -silent \
           -rate-limit $RATE_CRAWL \
           -c $THREADS_CRAWL \
           -delay $CRAWL_DELAY \
  | anew recon/$TARGET/urls.txt

# --- PASSIVE: historical URLs — no rate limit needed ---
# Queries Wayback Machine and Common Crawl, not the live target.
echo $TARGET | waybackurls | anew recon/$TARGET/urls.txt
gau $TARGET --subs | anew recon/$TARGET/urls.txt

echo "[+] Total URLs: $(wc -l < recon/$TARGET/urls.txt)"
```

### Step 4: Classify URLs — PASSIVE

Local text processing only. No network requests.

```bash
cat recon/$TARGET/urls.txt | gf xss       > recon/$TARGET/xss-candidates.txt
cat recon/$TARGET/urls.txt | gf ssrf      > recon/$TARGET/ssrf-candidates.txt
cat recon/$TARGET/urls.txt | gf idor      > recon/$TARGET/idor-candidates.txt
cat recon/$TARGET/urls.txt | gf sqli      > recon/$TARGET/sqli-candidates.txt
cat recon/$TARGET/urls.txt | gf redirect  > recon/$TARGET/redirect-candidates.txt
cat recon/$TARGET/urls.txt | gf lfi       > recon/$TARGET/lfi-candidates.txt

cat recon/$TARGET/urls.txt | grep -E "/api/|/v1/|/v2/|/graphql|/rest/" \
  > recon/$TARGET/api-endpoints.txt

echo "[+] IDOR candidates: $(wc -l < recon/$TARGET/idor-candidates.txt)"
echo "[+] SSRF candidates: $(wc -l < recon/$TARGET/ssrf-candidates.txt)"
echo "[+] API endpoints:   $(wc -l < recon/$TARGET/api-endpoints.txt)"
```

### Step 5: Nuclei Scan — ACTIVE

Sends active payloads to the target. Most likely step to trigger a WAF or cause
a brief DOS if uncapped. Rate limiting is mandatory.

```bash
nuclei -l recon/$TARGET/live-hosts.txt \
  -t ~/nuclei-templates/ \
  -severity critical,high,medium \
  -rate-limit $RATE_NUCLEI \
  -c $THREADS_NUCLEI \
  -bs 5 \
  -o recon/$TARGET/nuclei.txt

echo "[+] Nuclei findings: $(wc -l < recon/$TARGET/nuclei.txt)"
```

## Output

After running, you will have in `recon/<target>/`:
```
subdomains.txt          # All discovered subdomains
live-hosts.txt          # Live hosts with status/title/tech
urls.txt                # All crawled URLs
api-endpoints.txt       # API-specific paths
idor-candidates.txt     # URLs with ID parameters
ssrf-candidates.txt     # URLs with URL parameters
xss-candidates.txt      # URLs with reflection candidates
nuclei.txt              # Known CVE/misconfig findings
```

## What to Do Next

1. Review `live-hosts.txt` — open interesting ones in browser
2. Check `nuclei.txt` — any high/critical findings?
3. Review `api-endpoints.txt` — start IDOR testing
4. Check for admin panels: grep live-hosts for `/admin`, `/jenkins`, `/grafana`
5. Run `/hunt target.com` to start active vulnerability testing

## 5-Minute Rule

If after running this pipeline:
- All hosts return 403 or static pages
- No API endpoints visible
- No interesting parameters in URLs
- nuclei returns 0 medium/high findings

**→ Move on to a different target.**
