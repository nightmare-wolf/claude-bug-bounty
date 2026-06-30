#!/bin/bash
# =============================================================================
# OSINT Engine — people + corporate intelligence over FREE / open-source sources
#
# Maltego-style transforms. Profiles HUMANS and ORGANIZATIONS — NOT a domain's
# attack surface (that is tools/recon_engine.sh). No web2-recon tool is used here.
#
# Wraps (each auto-skipped if missing tool or API key):
#   People : holehe · socialscan · maigret · sherlock · theHarvester · PhoneInfoga
#   Corp   : OpenCorporates · OpenOwnership · GLEIF · OpenSanctions(yente)
#   Tooling: DNS SaaS fingerprint (MX/SPF/DMARC/verification TXT, keyless) ·
#            GitHub org mining · BuiltWith/SecurityTrails history · ownership dorks
#   Infra  : BGPView · Shodan(InternetDB keyless) · ipinfo · SecurityTrails
#   Meta   : exiftool · (SpiderFoot / recon-ng driven from the skill, not here)
#
# EVERY run ends by writing REPORT.md (any track) — corporate runs include a
# Tooling Inventory (tool · present/past · source link · snippet · confidence)
# and a Tool Ownership/Access map.
#
# Usage:
#   ./tools/osint_engine.sh --seed jane@acme.com --track people
#   ./tools/osint_engine.sh --seed "Acme Holdings Ltd" --track corp
#   ./tools/osint_engine.sh --seed acme.com --track both
#   ./tools/osint_engine.sh --seed 203.0.113.10        # IP → infra-ownership
#   ./tools/osint_engine.sh --keys                      # API-key status only
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/external_arsenal.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; MAG='\033[0;35m'; NC='\033[0m'
log()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
hit()  { echo -e "${MAG}[OSINT]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1" >&2; }
skip() { echo -e "${YELLOW}[skip]${NC} $1"; }

urlenc() { printf '%s' "${1:-}" | jq -sRr @uri; }
slug()   { echo "${1:-}" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9.@_-' | cut -c1-60; }

# ── API-key status ──────────────────────────────────────────────────────────
_key_status() {
  printf "\n%-22s %-28s %s\n" "SOURCE" "ENV VAR" "STATUS"
  printf "%-22s %-28s %s\n" "------" "-------" "------"
  local rows=(
    "Shodan (free acct)|SHODAN_API_KEY"
    "Censys Platform PAT|CENSYS_PLATFORM_TOKEN"
    "Censys org ID (paid only)|CENSYS_ORG_ID"
    "BuiltWith (10 free lookups)|BUILTWITH_API_KEY"
    "ipinfo (free 50k/mo)|IPINFO_TOKEN"
    "Hunter.io (free 25/mo)|HUNTER_API_KEY"
    "DomScan (free 10k/mo)|DOMSCAN_API_KEY"
    "GitHub (free)|GITHUB_TOKEN"
    "SecurityTrails (PAID ~\$500/mo)|SECURITYTRAILS_API_KEY"
    "OpenCorporates (PAID API)|OPENCORPORATES_API_KEY"
    "OpenSanctions (PAID / self-host)|OPENSANCTIONS_API_KEY"
    "HaveIBeenPwned (~\$60/yr)|HIBP_API_KEY"
  )
  for r in "${rows[@]}"; do
    IFS='|' read -r name var <<< "$r"
    if [ -n "${!var:-}" ]; then
      printf "${GREEN}%-22s${NC} %-28s ${GREEN}SET${NC}\n" "$name" "$var"
    else
      printf "${YELLOW}%-22s${NC} %-28s ${YELLOW}unset (free fallback where possible)${NC}\n" "$name" "$var"
    fi
  done
  echo ""
  ok  "No key needed: RDAP(whois) · Hudson Rock(infostealer exposure) · ipwho.is(IP/ASN) · BGPView · GLEIF · OpenOwnership · DNSDumpster · maigret · sherlock · holehe · socialscan · PhoneInfoga · theHarvester(core) · exiftool · Shodan InternetDB · DNS SaaS fingerprint"
  echo ""
  warn "Now PAID (engine falls back to a free source): SecurityTrails→RDAP · ipinfo→ipwho.is · HIBP→Hudson Rock · OpenCorporates API→GLEIF+web · OpenSanctions API→self-host yente or free bulk data · Censys→Platform free PAT"
}

# ── Entity classification ───────────────────────────────────────────────────
classify() {
  local s="$1"
  if [[ "$s" == *@* ]]; then echo email; return; fi
  if [[ "$s" =~ ^\+?[0-9][0-9\ \-]{6,}$ ]]; then echo phone; return; fi
  if [[ "$s" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then echo ip; return; fi
  if [[ "$s" =~ (Ltd|Inc|LLC|GmbH|Corp|Holdings|Group|S\.A\.|Limited|PLC|Pty) ]]; then echo company; return; fi
  if [[ "$s" == *.* && "$s" != *" "* ]]; then echo domain; return; fi
  if [[ "$s" == *" "* ]]; then echo company; return; fi
  echo username
}

# ── People transforms ───────────────────────────────────────────────────────
people_track() {
  local seed="$1" out="$2" etype="$3"
  log "People track on '$seed' (type=$etype)"

  local user="$seed"
  [[ "$etype" == email ]] && user="${seed%@*}"

  if [[ "$etype" == email ]]; then
    if _have holehe; then
      log "holehe — which sites is $seed registered on..."
      holehe "$seed" --only-used > "$out/holehe.txt" 2>/dev/null || true
      n=$(grep -cE '\[\+\]|@' "$out/holehe.txt" 2>/dev/null || echo 0)
      [ "${n:-0}" -gt 0 ] && hit "holehe: $n site signals" || ok "holehe: nothing/used-only empty"
    else skip "holehe not installed — pipx install holehe"; fi
  fi

  if _have socialscan; then
    log "socialscan — account/username availability..."
    socialscan "$seed" "$user" > "$out/socialscan.txt" 2>/dev/null || true
    ok "socialscan → socialscan.txt"
  else skip "socialscan not installed — pip install socialscan"; fi

  if _have maigret; then
    log "maigret — username across 3000+ sites (may take a minute)..."
    maigret "$user" --no-progressbar --timeout 10 -T --folderpath "$out/maigret" 2>/dev/null || true
    ok "maigret → $out/maigret/"
  else skip "maigret not installed — pipx install maigret"; fi

  if _have sherlock; then
    log "sherlock — username across 400+ sites..."
    ( cd "$out" && sherlock "$user" --timeout 10 --print-found >/dev/null 2>&1 ) || true
    ok "sherlock → $out/$user.txt"
  else skip "sherlock not installed — pipx install sherlock-project"; fi

  if [[ "$etype" == phone ]] && _have phoneinfoga; then
    log "PhoneInfoga — carrier/region footprint..."
    phoneinfoga scan -n "$seed" > "$out/phoneinfoga.txt" 2>/dev/null || true
    ok "phoneinfoga → phoneinfoga.txt"
  fi

  # Breach / exposure EXPOSURE signal — names + count only, never plaintext.
  # Hudson Rock infostealer API is FREE + keyless (primary). HIBP is optional (paid).
  if [[ "$etype" == email ]]; then
    log "Hudson Rock — infostealer-infection exposure (free, no key, metadata only)..."
    curl -s "https://cavalier.hudsonrock.com/api/json/v2/osint-tools/search-by-email?email=$(urlenc "$seed")" \
      > "$out/hudsonrock.json" 2>/dev/null || true
    if jq -e . "$out/hudsonrock.json" >/dev/null 2>&1; then
      local hrn; hrn=$(jq -r '(.stealers // []) | length' "$out/hudsonrock.json" 2>/dev/null || echo 0)
      if [ "${hrn:-0}" -gt 0 ]; then
        warn "Hudson Rock: email seen in $hrn infostealer infection(s) — see hudsonrock.json (counts/metadata, NO credentials)"
      else
        ok "Hudson Rock: $(jq -r '.message // "no infostealer exposure"' "$out/hudsonrock.json" 2>/dev/null)"
      fi
    else skip "Hudson Rock: no/invalid response"; fi
  fi

  if [[ "$etype" == email && -n "${HIBP_API_KEY:-}" ]]; then
    log "HIBP — breach exposure signal (names only, paid key present)..."
    curl -s -H "hibp-api-key: $HIBP_API_KEY" -H "user-agent: osint-engine" \
      "https://haveibeenpwned.com/api/v3/breachedaccount/$(urlenc "$seed")?truncateResponse=true" \
      | jq -r '.[].Name' > "$out/breach_names.txt" 2>/dev/null || true
    n=$(wc -l < "$out/breach_names.txt" 2>/dev/null | tr -d ' ' || echo 0)
    [ "${n:-0}" -gt 0 ] && hit "HIBP: exposed in $n breaches (names only)" || ok "HIBP: no breach"
  elif [[ "$etype" == email ]]; then
    skip "HIBP_API_KEY unset — HIBP now ~\$60/yr; Hudson Rock (free) used above for exposure"
  fi
}

# ── Corporate transforms ────────────────────────────────────────────────────
corp_track() {
  local seed="$1" out="$2"
  log "Corporate track on '$seed'"
  local q; q=$(urlenc "$seed")

  log "OpenCorporates — registry (officers/status)..."
  curl -s "https://api.opencorporates.com/v0.4/companies/search?q=${q}${OPENCORPORATES_API_KEY:+&api_token=$OPENCORPORATES_API_KEY}" \
    | jq -r '.results.companies[]?.company | "\(.name) | \(.company_number) | \(.jurisdiction_code) | \(.current_status)"' \
    > "$out/opencorporates.txt" 2>/dev/null || true
  n=$(wc -l < "$out/opencorporates.txt" 2>/dev/null | tr -d ' ' || echo 0)
  [ "${n:-0}" -gt 0 ] && hit "OpenCorporates: $n company matches" || skip "OpenCorporates: no match (or key needed for full results)"

  log "GLEIF — LEI / legal name / parent..."
  curl -s "https://api.gleif.org/api/v1/lei-records?filter%5Bentity.legalName%5D=${q}&page%5Bsize%5D=5" \
    | jq -r '.data[]? | "\(.attributes.lei) | \(.attributes.entity.legalName.name) | \(.attributes.entity.legalAddress.country)"' \
    > "$out/gleif.txt" 2>/dev/null || true
  n=$(wc -l < "$out/gleif.txt" 2>/dev/null | tr -d ' ' || echo 0)
  [ "${n:-0}" -gt 0 ] && hit "GLEIF: $n LEI records" || ok "GLEIF: no LEI match"

  log "OpenOwnership — beneficial ownership register..."
  curl -s "https://register.openownership.org/search.json?q=${q}" \
    > "$out/openownership.json" 2>/dev/null || true
  [ -s "$out/openownership.json" ] && ok "OpenOwnership → openownership.json" || skip "OpenOwnership: empty"

  log "OpenSanctions — sanctions/PEP/watchlist screening..."
  curl -s "https://api.opensanctions.org/search/default?q=${q}" \
       ${OPENSANCTIONS_API_KEY:+-H "Authorization: ApiKey $OPENSANCTIONS_API_KEY"} \
    | jq -r '.results[]? | "\(.caption) | \(.schema) | \(.datasets|join(","))"' \
    > "$out/opensanctions.txt" 2>/dev/null || true
  n=$(wc -l < "$out/opensanctions.txt" 2>/dev/null | tr -d ' ' || echo 0)
  if [ "${n:-0}" -gt 0 ]; then warn "OpenSanctions: $n POSSIBLE matches — VERIFY identifiers (name collisions common)"; else ok "OpenSanctions: no match"; fi

  log "BGPView — ASNs owned by the org..."
  curl -s "https://api.bgpview.io/search?query_term=${q}" \
    | jq -r '.data.asns[]? | "AS\(.asn) | \(.name) | \(.description)"' \
    > "$out/bgpview_asns.txt" 2>/dev/null || true
  n=$(wc -l < "$out/bgpview_asns.txt" 2>/dev/null | tr -d ' ' || echo 0)
  [ "${n:-0}" -gt 0 ] && hit "BGPView: $n ASNs match the org name" || ok "BGPView: no ASN owned under that name"
}

# ── Corporate tooling / tech-stack fingerprint (past + present + ownership) ──
# Discovers SaaS/vendors/software a company uses, each with a source + snippet,
# plus ready-to-click ownership dorks (who administers which tool). Keyless-first
# (DNS fingerprint is the strongest free signal); GitHub + history layered on top.
_emit_tool() { # status  category  tool  source  snippet  → corp_tooling.tsv
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$(printf '%s' "${5:-}" | tr '\t\n' '  ')" >> "$TOOL_TSV"
}

corp_tooling() {
  local seed="$1" out="$2" etype="$3"
  TOOL_TSV="$out/corp_tooling.tsv"
  local DORKS="$out/ownership_dorks.txt"
  : > "$TOOL_TSV"; : > "$DORKS"
  log "Corporate tooling / tech-stack fingerprint (past + present + ownership)"

  # derive a domain + company slug from the seed
  local domain="" company="$seed"
  if [[ "$etype" == domain ]]; then domain="$seed"; company="${seed%%.*}"; fi

  # ── DNS SaaS fingerprint (keyless — strongest present-tooling signal) ──
  # token (substring, lowercased)  |  vendor/tool  |  category
  local map=(
    # MX → email/security provider
    "aspmx.l.google.com|Google Workspace|Email/Identity"
    "googlemail.com|Google Workspace|Email/Identity"
    "mail.protection.outlook.com|Microsoft 365 (Exchange Online)|Email/Identity"
    "pphosted.com|Proofpoint|Email security"
    "ppe-hosted.com|Proofpoint Essentials|Email security"
    "mimecast.com|Mimecast|Email security"
    "messagelabs.com|Broadcom/Symantec MessageLabs|Email security"
    "zoho.com|Zoho Mail|Email/Productivity"
    "zohomail|Zoho Mail|Email/Productivity"
    "secureserver.net|GoDaddy Email|Email"
    "barracudanetworks.com|Barracuda|Email security"
    "mailgun.org|Mailgun|Transactional email"
    # SPF include → SaaS that sends as the domain
    "_spf.google.com|Google Workspace|Email/Identity"
    "spf.protection.outlook.com|Microsoft 365|Email/Identity"
    "_spf.salesforce.com|Salesforce|CRM"
    "_spf.pardot.com|Salesforce Pardot|Marketing"
    "mail.zendesk.com|Zendesk|Support/Helpdesk"
    "servers.mcsv.net|Mailchimp|Marketing email"
    "spf.mandrillapp.com|Mailchimp Mandrill|Transactional email"
    "sendgrid.net|SendGrid (Twilio)|Transactional email"
    "_spf.hubspotemail.net|HubSpot|Marketing/CRM"
    "mktomail.com|Marketo (Adobe)|Marketing automation"
    "_spf.qualtrics.com|Qualtrics|Surveys/XM"
    "_spf.atlassian.net|Atlassian|DevOps/Collaboration"
    "stspg-customer.com|Atlassian Statuspage|Status page"
    "amazonses.com|Amazon SES|Transactional email"
    "spf.mailjet.com|Mailjet|Transactional email"
    "_spf.intercom.io|Intercom|Support/Messaging"
    "spf.constantcontact.com|Constant Contact|Marketing email"
    "mail.zoho.com|Zoho|Productivity"
    "spf.freshemail.io|Freshworks|Support/CRM"
    "_spf.docusign.net|DocuSign|E-signature"
    "spf.smtp.workato.com|Workato|Integration/iPaaS"
    "et._spf.pardot.com|Salesforce Marketing Cloud|Marketing"
    # DMARC rua/ruf → DMARC processor
    "dmarcian|Dmarcian|DMARC processor"
    "valimail|Valimail|DMARC processor"
    "agari|Agari (Fortra)|DMARC processor"
    "rep.redsift.cloud|Red Sift OnDMARC|DMARC processor"
    "ondmarc|Red Sift OnDMARC|DMARC processor"
    "mxtoolbox.com|MXToolbox|DMARC monitoring"
    "dmarc.postmarkapp.com|Postmark|DMARC monitoring"
    # *-site/domain-verification TXT → SaaS sign-up
    "google-site-verification|Google (Workspace/Search Console)|Identity/SEO"
    "ms-domain-verification|Microsoft 365|Identity"
    "facebook-domain-verification|Meta/Facebook Business|Marketing/Social"
    "atlassian-domain-verification|Atlassian|DevOps/Collaboration"
    "docusign=|DocuSign|E-signature"
    "adobe-idp-site-verification|Adobe (SSO/Creative Cloud)|Identity/Creative"
    "adobe-sign-verification|Adobe Sign|E-signature"
    "slack-domain-verification|Slack|Collaboration"
    "zoom-domain-verification|Zoom|Conferencing"
    "dropbox-domain-verification|Dropbox|File storage"
    "stripe-verification|Stripe|Payments"
    "notion-domain-verification|Notion|Docs/Wiki"
    "miro-verification|Miro|Whiteboard/Collaboration"
    "figma|Figma|Design"
    "citrix-verification-code|Citrix|Remote access/VDI"
    "workplace-domain-verification|Meta Workplace|Collaboration"
    "mongodb-site-verification|MongoDB Atlas|Database"
    "pardot|Salesforce Pardot|Marketing"
    "have-i-been-pwned-verification|Have I Been Pwned|Security monitoring"
    "yandex-verification|Yandex|Productivity/SEO"
    "logmein-verification-code|GoTo/LogMeIn|Remote access"
    "webexdomainverification|Cisco Webex|Conferencing"
    "canva-site-verification|Canva|Design"
    "onetrust|OneTrust|Privacy/GRC"
    "twilio-domain-verification|Twilio|Comms/API"
    "shopify|Shopify|E-commerce"
    "wrike-verification|Wrike|Project management"
    "smartsheet|Smartsheet|Project management"
    "box-domain-verification|Box|File storage"
    "asana-domain-verification|Asana|Project management"
    "loom-site-verification|Loom|Video"
    "calendly|Calendly|Scheduling"
    "_amazonses|Amazon SES|Transactional email"
    "klaviyo|Klaviyo|Marketing"
    "gitlab|GitLab|DevOps/Source"
    "github-verification|GitHub|Source hosting"
    "sentry|Sentry|Error monitoring"
    "segment.com|Segment (Twilio)|Analytics/CDP"
  )

  if [[ -n "$domain" ]] && _have dig; then
    log "DNS SaaS fingerprint on $domain (MX / SPF / DMARC / verification TXT)"
    local recs="$out/dns_records.txt"; : > "$recs"
    { dig +short MX "$domain"; dig +short TXT "$domain"; dig +short TXT "_dmarc.$domain"; } 2>/dev/null \
      | sed '/^$/d' >> "$recs"
    local line lc m tok vend cat
    while IFS= read -r line; do
      lc=$(echo "$line" | tr 'A-Z' 'a-z')
      for m in "${map[@]}"; do
        IFS='|' read -r tok vend cat <<< "$m"
        if [[ "$lc" == *"$tok"* ]]; then
          _emit_tool "present" "$cat" "$vend" "DNS record on $domain  (dig +short TXT/MX $domain)" "$line"
          hit "tooling: $vend  [$cat]  ← ${line:0:70}"
        fi
      done
    done < "$recs"
    n=$(wc -l < "$TOOL_TSV" 2>/dev/null | tr -d ' ' || echo 0)
    ok "DNS fingerprint: ${n:-0} vendor signal(s) → corp_tooling.tsv"
  elif [[ -n "$domain" ]]; then
    skip "dig not found — DNS SaaS fingerprint skipped (brew install bind / apt install dnsutils)"
  fi

  # ── GitHub org mining (present tech via repo languages + CI) ──
  local ghcand
  ghcand=$(echo "$company" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9-')
  if [[ -n "$ghcand" ]]; then
    log "GitHub org mining — candidate handle '$ghcand'"
    local ghhdr=(); [ -n "${GITHUB_TOKEN:-}" ] && ghhdr=(-H "Authorization: Bearer $GITHUB_TOKEN")
    curl -s ${ghhdr[@]+"${ghhdr[@]}"} "https://api.github.com/orgs/$ghcand" > "$out/github_org.json" 2>/dev/null || true
    if jq -e '.login' "$out/github_org.json" >/dev/null 2>&1; then
      hit "GitHub org: https://github.com/$ghcand"
      _emit_tool "present" "Source hosting/CI" "GitHub (org: $ghcand)" "https://github.com/$ghcand" "$(jq -r '.login + " · " + ((.public_repos|tostring)) + " public repos"' "$out/github_org.json" 2>/dev/null)"
      curl -s ${ghhdr[@]+"${ghhdr[@]}"} "https://api.github.com/orgs/$ghcand/repos?per_page=100&sort=pushed" > "$out/github_repos.json" 2>/dev/null || true
      jq -r '.[]?.language // empty' "$out/github_repos.json" 2>/dev/null | sort | uniq -c | sort -rn > "$out/github_langs.txt" 2>/dev/null || true
      local cnt lang
      while read -r cnt lang; do
        [ -z "${lang:-}" ] && continue
        _emit_tool "present" "Language/stack" "$lang" "https://github.com/$ghcand (repo languages)" "$cnt repo(s) in $lang"
      done < "$out/github_langs.txt"
      echo "GitHub CODEOWNERS / maintainers | https://github.com/search?q=org%3A$ghcand+filename%3ACODEOWNERS&type=code" >> "$DORKS"
      echo "GitHub Actions / CI configs | https://github.com/search?q=org%3A$ghcand+path%3A.github%2Fworkflows&type=code" >> "$DORKS"
    else
      skip "no public GitHub org at github.com/$ghcand (try the real org handle)"
    fi
  fi

  # ── Corporate breach/credential exposure (Hudson Rock, free + keyless) ──
  if [[ -n "$domain" ]]; then
    log "Hudson Rock — corporate infostealer exposure for $domain (free, no key)..."
    curl -s "https://cavalier.hudsonrock.com/api/json/v2/osint-tools/search-by-domain?domain=$domain" \
      > "$out/hudsonrock_domain.json" 2>/dev/null || true
    if jq -e 'type=="object"' "$out/hudsonrock_domain.json" >/dev/null 2>&1; then
      local emp ext; emp=$(jq -r '.total // .totalStealers // "?"' "$out/hudsonrock_domain.json" 2>/dev/null)
      ext=$(jq -r '.employees // .total_employees // "?"' "$out/hudsonrock_domain.json" 2>/dev/null)
      hit "Hudson Rock domain: infections=$emp employees-exposed=$ext → hudsonrock_domain.json (metadata only, NO credentials)"
    else skip "Hudson Rock domain: no/invalid response"; fi
  fi

  # ── DomScan domain intelligence (keyed: DOMSCAN_API_KEY, free 10k/mo) ──
  if [[ -n "$domain" && -n "${DOMSCAN_API_KEY:-}" ]]; then
    log "DomScan — WHOIS + typosquatting (phishing surface) + reputation..."
    local DSU="https://domscan.net/v1" DSA="Authorization: Bearer $DOMSCAN_API_KEY"
    curl -s -H "$DSA" "$DSU/whois?domain=$domain"      > "$out/domscan_whois.json" 2>/dev/null || true
    curl -s -H "$DSA" "$DSU/typos?domain=$domain"      > "$out/domscan_typos.json" 2>/dev/null || true
    curl -s -H "$DSA" "$DSU/reputation?domain=$domain" > "$out/domscan_reputation.json" 2>/dev/null || true
    if jq -e 'has("is_newly_registered")' "$out/domscan_whois.json" >/dev/null 2>&1; then
      ok "DomScan WHOIS: registrar=$(jq -r '.registrar // "?"' "$out/domscan_whois.json" 2>/dev/null) age=$(jq -r '.domain_age_years // "?"' "$out/domscan_whois.json" 2>/dev/null)y newly_registered=$(jq -r '.is_newly_registered' "$out/domscan_whois.json" 2>/dev/null)"
    fi
    if jq -e '.registered_typos' "$out/domscan_typos.json" >/dev/null 2>&1; then
      local nt; nt=$(jq -r '(.registered_typos // []) | length' "$out/domscan_typos.json" 2>/dev/null || echo 0)
      if [ "${nt:-0}" -gt 0 ]; then
        warn "DomScan: $nt REGISTERED typosquat domain(s) (threat=$(jq -r '.threat_level // "?"' "$out/domscan_typos.json" 2>/dev/null)) — phishing surface → domscan_typos.json"
      else ok "DomScan typos: none registered (threat=$(jq -r '.threat_level // "?"' "$out/domscan_typos.json" 2>/dev/null))"; fi
    fi
    [ -s "$out/domscan_reputation.json" ] && jq -e '.reputation_score' "$out/domscan_reputation.json" >/dev/null 2>&1 \
      && hit "DomScan reputation: $(jq -r '.reputation_score' "$out/domscan_reputation.json" 2>/dev/null)/100 grade $(jq -r '.grade // "?"' "$out/domscan_reputation.json" 2>/dev/null) (risk=$(jq -r '.risk_level // "?"' "$out/domscan_reputation.json" 2>/dev/null))"
  elif [[ -n "$domain" ]]; then
    skip "DOMSCAN_API_KEY unset — DomScan whois/typosquatting/reputation skipped (free 10k/mo: domscan.net)"
  fi

  # ── Ownership / access mapping (dork emitter) ──
  log "Emitting tool-ownership dork URLs"
  if [ -s "$TOOL_TSV" ]; then
    cut -f3 "$TOOL_TSV" | sort -u | while IFS= read -r vend; do
      [ -z "${vend:-}" ] && continue
      echo "$vend admin/owner | https://www.google.com/search?q=$(urlenc "site:linkedin.com/in \"$vend\" \"$company\"")" >> "$DORKS"
    done
  fi
  {
    echo "All employees (LinkedIn) | https://www.google.com/search?q=$(urlenc "site:linkedin.com/in \"$company\"")"
    [ -n "$domain" ] && echo "Leaked email/contact sheets | https://www.google.com/search?q=$(urlenc "intext:\"@$domain\" filetype:xlsx OR filetype:csv")"
    [ -n "$domain" ] && echo "Tool email aliases (admin@/it@) | https://www.google.com/search?q=$(urlenc "\"@$domain\" (admin OR it OR helpdesk OR support)")"
  } >> "$DORKS"
  ok "ownership dorks → ownership_dorks.txt"

  # ── Past tooling discovery (historical signal) ──
  log "Past-tooling discovery pointers (Wayback / StackShare / BuiltWith)"
  {
    echo "StackShare profile (present+past stack) | https://stackshare.io/search/q?q=$(urlenc "$company")"
    echo "BuiltWith profile + history | https://builtwith.com/${domain:-$company}"
    [ -n "$domain" ] && echo "Wayback — careers/jobs snapshots | https://web.archive.org/web/*/$domain/careers*"
    [ -n "$domain" ] && echo "Wayback — all snapshots | https://web.archive.org/web/*/$domain*"
    echo "Job posts (tech requirements) | https://www.google.com/search?q=$(urlenc "\"$company\" (careers OR jobs) (experience OR proficient OR stack)")"
  } > "$out/past_tooling_pointers.txt"
  ok "past-tooling pointers → past_tooling_pointers.txt"

  # SecurityTrails historical TXT records → past SaaS (keyed)
  if [[ -n "$domain" && -n "${SECURITYTRAILS_API_KEY:-}" ]]; then
    log "SecurityTrails — historical TXT records (mine for retired SaaS)..."
    curl -s -H "APIKEY: $SECURITYTRAILS_API_KEY" \
      "https://api.securitytrails.com/v1/history/$domain/dns/txt" > "$out/securitytrails_txt_history.json" 2>/dev/null || true
    [ -s "$out/securitytrails_txt_history.json" ] && ok "SecurityTrails TXT history → securitytrails_txt_history.json" \
      || skip "SecurityTrails TXT history: empty"
  fi
  # BuiltWith API — present tech stack (keyed)
  if [[ -n "$domain" && -n "${BUILTWITH_API_KEY:-}" ]]; then
    log "BuiltWith API — current tech profile..."
    curl -s "https://api.builtwith.com/v21/api.json?KEY=$BUILTWITH_API_KEY&LOOKUP=$domain" > "$out/builtwith.json" 2>/dev/null || true
    if [ -s "$out/builtwith.json" ]; then
      jq -r '.Results[]?.Result.Paths[]?.Technologies[]? | "\(.Name)|\(.Tag)"' "$out/builtwith.json" 2>/dev/null \
        | sort -u | while IFS='|' read -r tname ttag; do
            [ -z "${tname:-}" ] && continue
            _emit_tool "present" "${ttag:-tech}" "$tname" "https://builtwith.com/$domain (BuiltWith API)" "BuiltWith: $tname"
          done
      ok "BuiltWith API → builtwith.json (merged into tooling inventory)"
    fi
  fi
}

# ── Always-on report builder (REPORT.md every run, any track) ────────────────
gen_report() {
  local out="$1" seed="$2" etype="$3" track="$4"
  local R="$out/REPORT.md"
  local now; now=$(date '+%Y-%m-%d %H:%M %Z' 2>/dev/null || echo "")
  {
    echo "# OSINT Report — $seed"
    echo
    echo "**Date:** $now  ·  **Entity type:** \`$etype\`  ·  **Track:** \`$track\`"
    echo "**Raw output dir:** \`$out\`"
    echo
    echo "> Auto-generated by \`osint_engine.sh\`. Passive sources only. Breach data = counts/names,"
    echo "> never credentials. Sanctions/PEP hits are leads — verify identifiers. Confirm scope before reporting PII."
    echo

    if [ -s "$out/corp_tooling.tsv" ]; then
      echo "## Corporate Tooling & Tech-Stack Inventory (present + past)"
      echo
      echo "Every row is a discovered tool/vendor/SaaS. **Confidence = number of independent signals** for that tool."
      echo
      echo "| Tool / Vendor | Status | Category | Confidence | Source | Snippet |"
      echo "|---|---|---|---|---|---|"
      awk -F'\t' '
        { key=$3; cnt[key]++;
          if (!(key in seen)) { seen[key]=1; stat[key]=$1; cat[key]=$2; src[key]=$4; snip[key]=$5; ord[++n]=key } }
        END { for (i=1;i<=n;i++){ k=ord[i];
                printf "| %s | %s | %s | %d | %s | `%s` |\n", k, stat[k], cat[k], cnt[k], src[k], snip[k] } }
      ' "$out/corp_tooling.tsv" | sort -t'|' -k5 -rn
      echo
    fi

    if [ -s "$out/ownership_dorks.txt" ]; then
      echo "## Tool Ownership / Access Map"
      echo
      echo "Who administers each tool — run these to map owners (LinkedIn admin titles, CODEOWNERS, email aliases)."
      echo
      echo "| Target | Dork URL |"
      echo "|---|---|"
      while IFS='|' read -r label url; do
        [ -z "${label:-}" ] && continue
        printf "| %s | %s |\n" "$(echo "$label"|sed 's/^ *//;s/ *$//')" "$(echo "$url"|sed 's/^ *//;s/ *$//')"
      done < "$out/ownership_dorks.txt"
      echo
    fi

    if [ -s "$out/past_tooling_pointers.txt" ]; then
      echo "## Past Tooling — Historical Discovery Pointers"
      echo
      echo "| Source | URL |"
      echo "|---|---|"
      while IFS='|' read -r label url; do
        [ -z "${label:-}" ] && continue
        printf "| %s | %s |\n" "$(echo "$label"|sed 's/^ *//;s/ *$//')" "$(echo "$url"|sed 's/^ *//;s/ *$//')"
      done < "$out/past_tooling_pointers.txt"
      echo "_(SecurityTrails TXT history + BuiltWith API also mined when keys are set.)_"
      echo
    fi

    if [ -f "$out/holehe.txt" ] || [ -d "$out/maigret" ] || [ -f "$out/breach_names.txt" ] || [ -f "$out/socialscan.txt" ] || [ -f "$out/hudsonrock.json" ]; then
      echo "## People Findings"
      echo
      [ -f "$out/holehe.txt" ]       && echo "- **holehe** site signals: $(grep -cE '\[\+\]|@' "$out/holehe.txt" 2>/dev/null || echo 0)  (\`holehe.txt\`)"
      [ -f "$out/socialscan.txt" ]   && echo "- **socialscan** account/username availability  (\`socialscan.txt\`)"
      [ -d "$out/maigret" ]          && echo "- **maigret** profiles across 3000+ sites  (\`maigret/\`)"
      [ -f "$out/breach_names.txt" ] && echo "- **HIBP breach exposure:** $(wc -l < "$out/breach_names.txt" 2>/dev/null | tr -d ' ') breach(es) — names only, no credentials  (\`breach_names.txt\`)"
      [ -f "$out/hudsonrock.json" ]  && echo "- **Hudson Rock** infostealer exposure: $(jq -r '(.stealers // []) | length' "$out/hudsonrock.json" 2>/dev/null || echo 0) infection(s) — metadata only  (\`hudsonrock.json\`)"
      [ -f "$out/phoneinfoga.txt" ]  && echo "- **PhoneInfoga** carrier/region footprint  (\`phoneinfoga.txt\`)"
      echo
    fi

    if [ -s "$out/opencorporates.txt" ] || [ -s "$out/gleif.txt" ] || [ -s "$out/opensanctions.txt" ] || [ -s "$out/bgpview_asns.txt" ]; then
      echo "## Corporate Identity & Ownership"
      echo
      [ -s "$out/opencorporates.txt" ] && { echo "**OpenCorporates registry matches:**"; echo '```'; head -10 "$out/opencorporates.txt"; echo '```'; }
      [ -s "$out/gleif.txt" ]          && { echo "**GLEIF (LEI · legal name · country):**"; echo '```'; head -5 "$out/gleif.txt"; echo '```'; }
      [ -s "$out/opensanctions.txt" ]  && { echo "**OpenSanctions — VERIFY (leads only, name collisions common):**"; echo '```'; head -10 "$out/opensanctions.txt"; echo '```'; }
      [ -s "$out/bgpview_asns.txt" ]   && { echo "**Owned ASNs (BGPView):**"; echo '```'; head -10 "$out/bgpview_asns.txt"; echo '```'; }
      echo
    fi

    if [ -s "$out/hudsonrock_domain.json" ] && jq -e 'type=="object"' "$out/hudsonrock_domain.json" >/dev/null 2>&1; then
      echo "## Corporate Credential Exposure (Hudson Rock — free)"
      echo
      echo "- Infostealer infections: **$(jq -r '.total // .totalStealers // "?"' "$out/hudsonrock_domain.json" 2>/dev/null)**  ·  employees exposed: **$(jq -r '.employees // .total_employees // "?"' "$out/hudsonrock_domain.json" 2>/dev/null)**  (metadata only, no credentials — \`hudsonrock_domain.json\`)"
      echo
    fi

    if [ -s "$out/domscan_typos.json" ] || [ -s "$out/domscan_reputation.json" ] || [ -s "$out/domscan_whois.json" ]; then
      echo "## Domain Intelligence (DomScan)"
      echo
      if jq -e '.reputation_score' "$out/domscan_reputation.json" >/dev/null 2>&1; then
        echo "- **Reputation:** $(jq -r '.reputation_score' "$out/domscan_reputation.json" 2>/dev/null)/100  grade $(jq -r '.grade // "?"' "$out/domscan_reputation.json" 2>/dev/null)  ·  risk $(jq -r '.risk_level // "?"' "$out/domscan_reputation.json" 2>/dev/null)  (\`domscan_reputation.json\`)"
      fi
      if jq -e 'has("is_newly_registered")' "$out/domscan_whois.json" >/dev/null 2>&1; then
        echo "- **WHOIS:** registrar $(jq -r '.registrar // "?"' "$out/domscan_whois.json" 2>/dev/null)  ·  age $(jq -r '.domain_age_years // "?"' "$out/domscan_whois.json" 2>/dev/null)y  ·  newly-registered: $(jq -r '.is_newly_registered' "$out/domscan_whois.json" 2>/dev/null)  (\`domscan_whois.json\`)"
      fi
      if jq -e '.registered_typos' "$out/domscan_typos.json" >/dev/null 2>&1; then
        local dtn; dtn=$(jq -r '(.registered_typos // []) | length' "$out/domscan_typos.json" 2>/dev/null || echo 0)
        echo "- **Typosquatting / phishing surface:** $dtn registered look-alike domain(s)  ·  threat $(jq -r '.threat_level // "?"' "$out/domscan_typos.json" 2>/dev/null)  (\`domscan_typos.json\`)"
        if [ "${dtn:-0}" -gt 0 ]; then
          echo
          echo "  | Registered typosquat | (verify before reporting) |"
          echo "  |---|---|"
          jq -r '.registered_typos[]? | "  | \(.domain // .fqdn // .) |  |"' "$out/domscan_typos.json" 2>/dev/null | head -15
        fi
      fi
      echo
    fi

    if [ -s "$out/ipinfo.json" ] || [ -s "$out/ipwho.json" ] || [ -s "$out/bgpview_ip.txt" ] || [ -s "$out/shodan_internetdb.json" ] || [ -s "$out/rdap_domain.json" ]; then
      echo "## Infrastructure Ownership"
      echo
      [ -s "$out/rdap_domain.json" ]       && echo "- **RDAP** WHOIS (free): registrar $(jq -r '[.entities[]?|select(.roles[]?=="registrar")|.vcardArray[1][]?|select(.[0]=="fn")|.[3]][0] // "?"' "$out/rdap_domain.json" 2>/dev/null)  (\`rdap_domain.json\`)"
      [ -s "$out/ipinfo.json" ]            && echo "- **ipinfo** org: $(jq -r '.org // "?"' "$out/ipinfo.json" 2>/dev/null)"
      [ -s "$out/ipwho.json" ]             && echo "- **ipwho.is** (free): $(jq -r '.connection.org // .connection.isp // "?"' "$out/ipwho.json" 2>/dev/null) (AS$(jq -r '.connection.asn // "?"' "$out/ipwho.json" 2>/dev/null))"
      [ -s "$out/bgpview_ip.txt" ]         && { echo "- **BGPView** prefix → ASN → owner:"; echo '```'; head -5 "$out/bgpview_ip.txt"; echo '```'; }
      [ -s "$out/shodan_internetdb.json" ] && echo "- **Shodan InternetDB** (keyless): \`shodan_internetdb.json\`"
      echo
    fi

    echo "## For the Claude analyst — run these next (Track C)"
    echo
    echo "Claude is an active OSINT source, not just the runner. With \`WebSearch\` / \`WebFetch\`:"
    echo
    echo "1. **Search the open web** for \`$seed\` — news, LinkedIn, filings, leaks, blogs, archives"
    echo "   (see the Claude search-plan templates in the \`osint\` skill, Track C)."
    if [ -s "$out/ownership_dorks.txt" ]; then
      echo "2. **Execute the ownership dorks** in \`ownership_dorks.txt\` — resolve each URL to the named"
      echo "   admin/owner (LinkedIn title, CODEOWNERS, alias). $(wc -l < "$out/ownership_dorks.txt" 2>/dev/null | tr -d ' ') queued."
    fi
    if [ -s "$out/past_tooling_pointers.txt" ]; then
      echo "3. **Execute the history pointers** in \`past_tooling_pointers.txt\` — fetch the Wayback /"
      echo "   StackShare / BuiltWith pages to confirm past + present tooling."
    fi
    echo "4. **Corroborate** every link with ≥2 independent sources, then fold the new"
    echo "   PERSON/EMAIL/ORG/TOOL/OWNER entities into the Mermaid graph + dossier, each with a source URL."
    echo
    echo "_Passive only: search engines & archives, never the subject's own systems. Confirm scope before naming people._"
    echo

    echo "## Raw Source Files"
    echo
    find "$out" -maxdepth 2 -type f ! -name REPORT.md 2>/dev/null | sort | sed 's/^/- `/; s/$/`/'
    echo
    echo "---"
    echo "_Build the Mermaid entity graph and the versioned dossier from these sources + Claude's web findings — see the \`osint\` skill._"
  } > "$R" 2>/dev/null || true
  ok "REPORT.md written → $R"
}

# ── Infra-ownership transforms (who runs it — NOT exploit surface) ───────────
infra_track() {
  local seed="$1" out="$2" etype="$3"
  log "Infra-ownership track on '$seed' (type=$etype)"

  if [[ "$etype" == domain ]]; then
    log "RDAP — structured WHOIS (registrar / dates / registrant org, free + keyless)..."
    curl -s -L "https://rdap.org/domain/$seed" > "$out/rdap_domain.json" 2>/dev/null || true
    if jq -e 'type=="object"' "$out/rdap_domain.json" >/dev/null 2>&1; then
      local rorg; rorg=$(jq -r '[.entities[]?|select(.roles[]?=="registrant")|.vcardArray[1][]?|select(.[0]=="fn")|.[3]][0] // (.entities[]?.vcardArray[1][]?|select(.[0]=="fn")|.[3]) // "registrant redacted"' "$out/rdap_domain.json" 2>/dev/null | head -1)
      hit "RDAP: registrar=$(jq -r '.entities[]?|select(.roles[]?=="registrar")|.vcardArray[1][]?|select(.[0]=="fn")|.[3]' "$out/rdap_domain.json" 2>/dev/null|head -1)  registrant=${rorg:-?}  → rdap_domain.json"
    else skip "RDAP: no structured record (try whois CLI)"; fi

    if [ -n "${SECURITYTRAILS_API_KEY:-}" ]; then
      log "SecurityTrails — WHOIS + DNS history (paid key present)..."
      curl -s -H "APIKEY: $SECURITYTRAILS_API_KEY" \
        "https://api.securitytrails.com/v1/domain/$seed/whois" > "$out/securitytrails_whois.json" 2>/dev/null || true
      ok "SecurityTrails → securitytrails_whois.json"
    else
      skip "SecurityTrails skipped — now PAID (~\$500/mo); RDAP (above) used for WHOIS instead"
    fi
  fi

  if [[ "$etype" == ip ]]; then
    log "Shodan InternetDB (keyless, passive) — services/CPEs/hostnames..."
    curl -s "https://internetdb.shodan.io/$seed" > "$out/shodan_internetdb.json" 2>/dev/null || true
    [ -s "$out/shodan_internetdb.json" ] && ok "InternetDB → shodan_internetdb.json"

    if _have shodan && [ -n "${SHODAN_API_KEY:-}" ]; then
      log "Shodan host — full intel..."
      shodan host "$seed" > "$out/shodan_host.txt" 2>/dev/null || true
      ok "shodan → shodan_host.txt"
    fi

    if [ -n "${IPINFO_TOKEN:-}" ]; then
      log "ipinfo — ASN/org/geo (token present)..."
      curl -s "https://ipinfo.io/$seed/json?token=$IPINFO_TOKEN" > "$out/ipinfo.json" 2>/dev/null || true
      [ -s "$out/ipinfo.json" ] && hit "ipinfo: $(jq -r '.org // "?"' "$out/ipinfo.json" 2>/dev/null)" || true
    else
      log "ipwho.is — ASN/org/geo (free, no key)..."
      curl -s "https://ipwho.is/$seed" > "$out/ipwho.json" 2>/dev/null || true
      [ -s "$out/ipwho.json" ] && hit "ipwho.is: $(jq -r '.connection.org // .connection.isp // "?"' "$out/ipwho.json" 2>/dev/null) (AS$(jq -r '.connection.asn // "?"' "$out/ipwho.json" 2>/dev/null))" || skip "ipwho.is: no response"
    fi

    log "BGPView — IP → prefix → ASN → owner..."
    curl -s "https://api.bgpview.io/ip/$seed" \
      | jq -r '.data.prefixes[]? | "\(.prefix) | AS\(.asn.asn) \(.asn.name) | \(.asn.description)"' \
      > "$out/bgpview_ip.txt" 2>/dev/null || true
    [ -s "$out/bgpview_ip.txt" ] && ok "BGPView → bgpview_ip.txt"
  fi

  if [[ "$etype" == domain ]] && _have theHarvester; then
    log "theHarvester — emails/people/hosts from search engines (passive)..."
    theHarvester -d "$seed" -b duckduckgo,crtsh,otx -l 200 -f "$out/theharvester" >/dev/null 2>&1 || true
    ok "theHarvester → $out/theharvester.*"
  fi
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
SEED=""; TRACK="auto"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --seed)  shift; SEED="${1:-}" ;;
    --track) shift; TRACK="${1:-auto}" ;;
    --people) TRACK="people" ;;
    --corp)   TRACK="corp" ;;
    --both)   TRACK="both" ;;
    --keys)   _key_status; exit 0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) [ -z "$SEED" ] && SEED="$1" || { err "unknown arg: $1"; exit 2; } ;;
  esac
  shift
done

[ -z "$SEED" ] && { err "--seed required (email|username|company|domain|ip|phone)"; _key_status; exit 2; }
_have jq || { err "jq is required"; exit 3; }

ETYPE=$(classify "$SEED")
if [ "$TRACK" = "auto" ]; then
  case "$ETYPE" in
    email|username|phone) TRACK="people" ;;
    company)              TRACK="corp" ;;
    ip)                   TRACK="infra" ;;
    domain)               TRACK="both" ;;
  esac
fi

OUT_DIR="${OSINT_OUT_DIR:-$(pwd)/osint/$TRACK/$(slug "$SEED")}"
mkdir -p "$OUT_DIR"
log "Seed='$SEED'  type=$ETYPE  track=$TRACK"
log "Output → $OUT_DIR"
echo ""

case "$TRACK" in
  people) people_track "$SEED" "$OUT_DIR" "$ETYPE" ;;
  corp)   corp_track   "$SEED" "$OUT_DIR"
          corp_tooling "$SEED" "$OUT_DIR" "$ETYPE" ;;
  infra)  infra_track  "$SEED" "$OUT_DIR" "$ETYPE" ;;
  both)
    people_track "$SEED" "$OUT_DIR" "$ETYPE"
    corp_track   "$SEED" "$OUT_DIR"
    corp_tooling "$SEED" "$OUT_DIR" "$ETYPE"
    infra_track  "$SEED" "$OUT_DIR" "$ETYPE"
    ;;
  *) err "unknown track: $TRACK"; exit 2 ;;
esac

# ── ALWAYS write a report at the end of every run (any track) ────────────────
gen_report "$OUT_DIR" "$SEED" "$ETYPE" "$TRACK"

# ── Summary index for the dossier builder ───────────────────────────────────
{
  echo "{"
  echo "  \"seed\": \"$SEED\","
  echo "  \"entity_type\": \"$ETYPE\","
  echo "  \"track\": \"$TRACK\","
  echo "  \"output_dir\": \"$OUT_DIR\","
  echo "  \"files\": ["
  find "$OUT_DIR" -maxdepth 2 -type f 2>/dev/null | sed 's/.*/    "&"/' | paste -sd',' -
  echo "  ]"
  echo "}"
} > "$OUT_DIR/summary.json" 2>/dev/null || true

echo ""
ok "OSINT pass complete → $OUT_DIR/"
warn "Reminder: passive sources only · breach data = counts/names not credentials · verify sanctions hits · confirm scope before reporting PII"
