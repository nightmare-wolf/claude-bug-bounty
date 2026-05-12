---
name: burp-analysis
description: Burp Suite project file (.burp) deep analysis — extracts endpoints, session tokens, anti-bot headers, LLM/AI pipeline parameters, agent flows, IDOR surface, infrastructure fingerprinting, and generates a versioned verbose report with diff against previous reports. Use when asked to analyze a Burp file, review captured traffic, or generate a traffic-based assessment report.
---

# BURP TRAFFIC ANALYSIS SKILL

Analyze a Burp Suite project file and generate a comprehensive, versioned, verbose security assessment report. Each new report for the same target is numbered (#2, #3…) and compared against the previous version.

---

## WORKFLOW

### Step 1 — Locate the File

Ask the user:

```
Where is your Burp project file located?
(Example: C:\Users\You\Burp\2026-04-29-target.burp)

Where should the report be saved?
(Example: C:\Users\You\Documents\Assessments\target\)
```

If the user provides a path, proceed. If the path is locked (Burp still open), attempt xcopy bypass:

```powershell
$dst = "$env:TEMP\burp_work"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
cmd /c "xcopy /H /Y `"$burpPath`" `"$dst\`""
```

Check magic bytes to confirm format. Burp files may be proprietary binary (not SQLite in newer versions). Use `strings` extraction for binary analysis.

---

### Step 2 — Extract Intelligence

Run targeted `strings` + `grep` extraction passes over the binary. Never load 256MB+ into memory wholesale. Use piped grep patterns:

#### HTTP Structure
```bash
strings "$burpFile" | grep -oE "^(GET|POST|PUT|PATCH|DELETE) [^ ]+" | sort -u
strings "$burpFile" | grep -oE "Host: [^\r\n]+" | sort -u
strings "$burpFile" | grep -oE "/[a-zA-Z0-9/_-]{4,}" | sort -u | head -500
```

#### LLM / AI Parameters (ByteDance/Gauth pattern)
```bash
strings "$burpFile" | grep -oE "LlmModel\":[0-9]+" | sort -u
strings "$burpFile" | grep -oE "SceneType\":[0-9]+" | sort -u
strings "$burpFile" | grep -oE "CommandType\":[0-9]+" | sort -u
strings "$burpFile" | grep -oE "MessageType\":[0-9]+" | sort -u
strings "$burpFile" | grep -oE "BizCode\":\"[^\"]+\"" | sort -u
strings "$burpFile" | grep -oE "UserRole\":[0-9]+" | sort -u
strings "$burpFile" | grep -oE "SolutionType\":[0-9]+" | sort -u
strings "$burpFile" | grep -oE "\"InputText\":\"[^\"]{5,200}\"" | sort -u | head -20
strings "$burpFile" | grep -oE "\"AnswerText\":\"[^\"]{5,300}\"" | sort -u | head -15
strings "$burpFile" | grep -oE "\"ContentText\":\"[^\"]{5,200}\"" | sort -u | head -15
```

#### Session / Auth Tokens
```bash
strings "$burpFile" | grep -oE "sessionid=[a-f0-9]+" | sort -u
strings "$burpFile" | grep -oE "uid_tt=[a-f0-9]+" | sort -u | head -3
strings "$burpFile" | grep -oE "d_ticket=[a-f0-9]+" | sort -u | head -3
strings "$burpFile" | grep -oE "device_id=[0-9]+" | sort -u
strings "$burpFile" | grep -oE "msToken=[A-Za-z0-9_-]{20,}" | sort -u | head -5
strings "$burpFile" | grep -oE "X-Bogus=[^ &]+" | sort -u | wc -l
```

#### Infrastructure
```bash
strings "$burpFile" | grep -oE "[a-zA-Z0-9._-]+\.[a-z]{2,10}" | grep -v "^[0-9]" | sort -u | grep -v "image\|font\|css\|js\b" | head -100
strings "$burpFile" | grep -oE "Content-Security-Policy[^\r\n]+" | head -5
strings "$burpFile" | grep -oE "X-Tt-[A-Za-z-]+: [^\r\n]+" | sort -u | head -20
strings "$burpFile" | grep -oE "Reporting-Endpoints[^\r\n]+" | head -5
```

#### LLM Identity Clues
```bash
strings "$burpFile" | grep -iE "(trained by|base model|underlying model|gemini|claude|gpt|doubao|spark|llama|mistral|dreamina)" | head -20
```

#### Server-Side Leaks
```bash
strings "$burpFile" | grep -oE "[a-z]+\.(equals|startsWith|endsWith|contains)\([^)]+\)" | head -10
```

---

### Step 3 — Determine Report Version

Check the report output directory for existing reports:

```
Gauth_Burp_Analysis_Report.md      → This is #1 (or create #1)
Gauth_Burp_Analysis_Report_2.md   → Exists → create #3
Gauth_Burp_Analysis_Report_3.md   → Exists → create #4
```

Name the new report: `{Target}_Burp_Analysis_Report.md` for first, `_2.md`, `_3.md` etc. for subsequent.

---

### Step 4 — Generate Report

Write a verbose report covering all sections below. Every section must have findings — if a section has no new data, state "No change from Report #N" explicitly.

---

## REPORT TEMPLATE

```markdown
# {Target} — Burp Traffic Analysis Report
**Assessment:** {engagement_id}
**Source File:** {burp_filename} ({size}, {date})
**Analyst:** {analyst}
**Report Version:** #{N}
**Generated:** {date}
{if N > 1}**Compared Against:** Report #{N-1} — {key_delta_summary}

---

## Delta from Report #{N-1}   ← ONLY if N > 1

| Section | Change |
|---------|--------|
| New endpoints | +X |
| New session tokens | +X |
| New LLM behaviors | Describe |
| Closed findings | List resolved items |
| Newly confirmed findings | List |

---

## 1. Executive Summary
- What the capture covers
- Primary target / assessed attack surface
- Top 3 findings from THIS capture
- Primary blocker status

## 2. Domain Surface
- All unique domains/subdomains observed
- Regional variants
- Related infrastructure domains
- CDN/proxy layer

## 3. Infrastructure Notes
- Company/platform ownership (ByteDance, Cloudflare, AWS, etc.)
- CDN identification (Akamai, Cloudflare, Fastly)
- Trace headers and what they reveal
- CSP policy analysis (third-party connections, payment processors, analytics)
- Server technology indicators

## 4. LLM Endpoints — Primary Targets
- All SSE/streaming endpoints
- Request structure with annotated fields
- Client-controlled fields (injection vectors)
- Response format and headers

## 5. Supporting API Endpoints
- Auth endpoints
- Admin endpoints (flag as HIGH)
- File upload endpoints
- Config/debug endpoints
- User data endpoints

## 6. Session Identifiers Observed
- All cookie names and values
- Token rotation behavior
- Session expiry

## 7. Anti-Bot / Auth Tokens on LLM Endpoints
- Signature schemes (X-Bogus, X-Gnarly, etc.)
- Rotation frequency
- Bypass options

## 8. Observed Scene Values — LLM Flow Mapping
- All enum values: LlmModel, CommandType, SceneType, MessageType, etc.
- What each value controls
- Untested values to enumerate

## 9. LLM Output Content Observed in Traffic
- Captured model outputs
- Identity admissions
- Jailbreak attempts and results
- Behavioral patterns

## 10. LLM Thinking Process / Agent Pipeline Leak
- Agent/pipeline endpoint trees
- Multi-step reasoning flows
- Tool use endpoints
- Template endpoints (system prompt candidates)

## 11. LLM Identity Analysis
- Evidence table
- Most likely model architecture
- Verification strategy

## 12. Points of Interest for Active Testing
P1/P2/P3 ranked table with endpoint + attack description

## 13. Blockers
- What prevents automated testing
- Bypass options for each blocker

## 14. Recommended Approach
- Phased testing plan based on this capture
- Specific next steps

## 15. Leaked Server-Side Artifacts
- Code fragments
- Internal config values
- Error messages with implementation detail

## 16. Full Discovered API Surface
- Complete endpoint tree grouped by subsystem
```

---

## VERSIONED COMPARISON LOGIC

When Report #N is generated after Report #N-1 exists:

1. Read the previous report's endpoint list (Section 16)
2. Diff against new endpoint list: new endpoints = progress; missing endpoints = scope narrowing
3. Read previous report's "Blockers" section — note if any were resolved
4. Read previous report's "Points of Interest" — note which were tested and what was found
5. Add a **Delta** section at the top summarizing changes

The goal: each successive report should show measurable progress through the assessment — new findings confirmed, old blockers solved, new attack surface discovered.

---

## REPORT NAMING CONVENTION

```
{TargetName}_Burp_Analysis_Report.md       ← Report #1
{TargetName}_Burp_Analysis_Report_2.md    ← Report #2 (with Delta vs #1)
{TargetName}_Burp_Analysis_Report_3.md    ← Report #3 (with Delta vs #2)
```

Target name derived from the Burp filename. If the user provides a report name, use that.

---

## CRITICAL RULES

1. **Never summarize — be verbose.** Every endpoint gets documented, every header gets analyzed.
2. **Always state which data came from the Burp file vs. prior conversation context** — clearly attribute sources.
3. **Flag client-controlled fields** in every LLM request structure — these are the injection vectors.
4. **Admin endpoints are always P1** regardless of whether access was confirmed.
5. **SSE endpoints with `IsDone: false` streaming** are the primary LLM attack surface.
6. **If the file is locked**, use xcopy bypass. If xcopy fails, document the lock and proceed with conversation-context data only, noting the limitation.
7. **Session tokens observed in the report are real captured values** — remind the user these may still be valid and should be rotated if the engagement is complete.
