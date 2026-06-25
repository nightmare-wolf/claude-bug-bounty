# OSINT API Keys

Fill in the **API Key** column with your key for any source you want active. Leave a row
blank to skip that source — the OSINT engine degrades gracefully and just omits it.

When `/osint` runs, this file is the reference for which keyed sources are available. After
filling a key in here, also export it as the matching **Env Var** (the engine reads env vars,
not this file directly), e.g. `export SHODAN_API_KEY="..."` in `~/.zshrc`.

## Keys required

| Tool / Source | Env Var | API Key | Cost | Track | Where to get it |
|---|---|---|---|---|---|
| Shodan | `SHODAN_API_KEY` |  | Free account (limited) | Infra | https://account.shodan.io |
| Censys (ID) | `CENSYS_API_ID` |  | Free tier | Infra | https://search.censys.io/account/api |
| Censys (Secret) | `CENSYS_API_SECRET` |  | Free tier | Infra | https://search.censys.io/account/api |
| SecurityTrails | `SECURITYTRAILS_API_KEY` |  | Free 50/mo | Infra / Corp | https://securitytrails.com/app/account |
| BuiltWith | `BUILTWITH_API_KEY` |  | Free tier (web lookup keyless) | Corp | https://api.builtwith.com |
| ipinfo | `IPINFO_TOKEN` |  | Free 50k/mo | Infra | https://ipinfo.io/account/token |
| Hunter.io | `HUNTER_API_KEY` |  | Free 25/mo | People | https://hunter.io/api-keys |
| GitHub | `GITHUB_TOKEN` |  | Free | Both (recon-ng / theHarvester) | https://github.com/settings/tokens |
| OpenCorporates | `OPENCORPORATES_API_KEY` |  | Free for researchers (apply) | Corp | https://opencorporates.com/api_accounts/new |
| OpenSanctions | `OPENSANCTIONS_API_KEY` |  | Hosted key, or self-host `yente` free | Corp | https://www.opensanctions.org/api |
| HaveIBeenPwned | `HIBP_API_KEY` |  | Paid (small) | People | https://haveibeenpwned.com/API/Key |

## No key needed (work out of the box)

BGPView · GLEIF · OpenOwnership · DNSDumpster · Shodan InternetDB · maigret · sherlock ·
holehe · socialscan · PhoneInfoga · theHarvester (core) · recon-ng (core) · SpiderFoot (core) ·
exiftool · Google dorking

> Minimum viable: **none** — the free sources cover both tracks. Best ROI to fill in first:
> **Shodan · Censys · SecurityTrails · GitHub token**. Add **OpenCorporates · OpenSanctions**
> when the corporate / ownership / sanctions track is in play.
