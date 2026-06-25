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
#   Infra  : BGPView · Shodan(InternetDB keyless) · ipinfo · SecurityTrails
#   Meta   : exiftool · (SpiderFoot / recon-ng driven from the skill, not here)
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

urlenc() { jq -sRr @uri <<< "${1:-}"; }
slug()   { echo "${1:-}" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9.@_-' | cut -c1-60; }

# ── API-key status ──────────────────────────────────────────────────────────
_key_status() {
  printf "\n%-22s %-28s %s\n" "SOURCE" "ENV VAR" "STATUS"
  printf "%-22s %-28s %s\n" "------" "-------" "------"
  local rows=(
    "Shodan|SHODAN_API_KEY"
    "Censys ID|CENSYS_API_ID"
    "Censys Secret|CENSYS_API_SECRET"
    "SecurityTrails|SECURITYTRAILS_API_KEY"
    "BuiltWith|BUILTWITH_API_KEY"
    "ipinfo|IPINFO_TOKEN"
    "Hunter.io|HUNTER_API_KEY"
    "GitHub|GITHUB_TOKEN"
    "OpenCorporates|OPENCORPORATES_API_KEY"
    "OpenSanctions|OPENSANCTIONS_API_KEY"
    "HaveIBeenPwned|HIBP_API_KEY"
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
  ok  "No key needed: BGPView · GLEIF · OpenOwnership · DNSDumpster · maigret · sherlock · holehe · socialscan · PhoneInfoga · theHarvester(core) · exiftool · Shodan InternetDB"
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

  # Breach EXPOSURE signal — names + count only, never plaintext
  if [[ "$etype" == email && -n "${HIBP_API_KEY:-}" ]]; then
    log "HIBP — breach exposure signal (names only)..."
    curl -s -H "hibp-api-key: $HIBP_API_KEY" -H "user-agent: osint-engine" \
      "https://haveibeenpwned.com/api/v3/breachedaccount/$(urlenc "$seed")?truncateResponse=true" \
      | jq -r '.[].Name' > "$out/breach_names.txt" 2>/dev/null || true
    n=$(wc -l < "$out/breach_names.txt" 2>/dev/null | tr -d ' ' || echo 0)
    [ "${n:-0}" -gt 0 ] && hit "HIBP: exposed in $n breaches (names only)" || ok "HIBP: no breach"
  elif [[ "$etype" == email ]]; then
    skip "HIBP_API_KEY unset — breach exposure check skipped (count+source only when set)"
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

# ── Infra-ownership transforms (who runs it — NOT exploit surface) ───────────
infra_track() {
  local seed="$1" out="$2" etype="$3"
  log "Infra-ownership track on '$seed' (type=$etype)"

  if [[ "$etype" == domain && -n "${SECURITYTRAILS_API_KEY:-}" ]]; then
    log "SecurityTrails — WHOIS/owner + DNS history..."
    curl -s -H "APIKEY: $SECURITYTRAILS_API_KEY" \
      "https://api.securitytrails.com/v1/domain/$seed/whois" > "$out/securitytrails_whois.json" 2>/dev/null || true
    ok "SecurityTrails → securitytrails_whois.json"
  elif [[ "$etype" == domain ]]; then
    skip "SECURITYTRAILS_API_KEY unset — WHOIS/DNS history skipped"
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

    log "ipinfo — ASN/org/geo..."
    curl -s "https://ipinfo.io/$seed/json${IPINFO_TOKEN:+?token=$IPINFO_TOKEN}" > "$out/ipinfo.json" 2>/dev/null || true
    [ -s "$out/ipinfo.json" ] && hit "ipinfo: $(jq -r '.org // "?"' "$out/ipinfo.json" 2>/dev/null)" || true

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
  corp)   corp_track   "$SEED" "$OUT_DIR" ;;
  infra)  infra_track  "$SEED" "$OUT_DIR" "$ETYPE" ;;
  both)
    people_track "$SEED" "$OUT_DIR" "$ETYPE"
    corp_track   "$SEED" "$OUT_DIR"
    infra_track  "$SEED" "$OUT_DIR" "$ETYPE"
    ;;
  *) err "unknown track: $TRACK"; exit 2 ;;
esac

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
