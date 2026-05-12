---
description: Analyze a Burp Suite project file (.burp) — extracts all endpoints, LLM/AI parameters, session tokens, anti-bot headers, infrastructure fingerprints, and generates a verbose versioned report with diff against prior reports. Usage: /burp-analyze [path/to/file.burp]
---

# /burp-analyze

Analyze a Burp Suite project file and generate a comprehensive, versioned security assessment report. If a prior report exists for the same target, the new report is numbered (#2, #3…) and includes a Delta section comparing findings.

## Usage

```
/burp-analyze
/burp-analyze C:\Users\You\Burp\2026-04-29-target.burp
/burp-analyze C:\Users\You\Burp\2026-04-29-target.burp --out C:\Assessments\Target\
```

If no path is given, you will be asked where the file is and where to save the report.

## What This Does

1. Locates and copies the Burp file (handles locked/open files via xcopy)
2. Extracts intelligence using targeted `strings + grep` passes — never loads full binary into memory
3. Maps: all endpoints, LLM parameters, session tokens, anti-bot schemes, infrastructure, agent pipelines
4. Determines report version by checking for existing reports in the output directory
5. Generates a verbose numbered report (Sections 1–16)
6. If Report #N-1 exists: reads it and prepends a Delta section showing progress

## Steps

### Step 1: Ask for File Location (if not provided)

```
Where is your Burp project file?
Where should the report be saved?
What is the target/engagement name (used in report filename)?
```

### Step 2: Copy File (handle lock)

```powershell
$dst = "$env:TEMP\burp_work"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
cmd /c "xcopy /H /Y `"$burpPath`" `"$dst\`""
```

If xcopy fails, proceed with conversation-context data only and note the limitation.

### Step 3: Extract Intelligence

Run in parallel (background bash tasks):

```bash
# Endpoints
strings "$f" | grep -oE "/[a-zA-Z0-9/_-]{4,80}" | sort -u > /tmp/endpoints.txt

# LLM parameters
strings "$f" | grep -oE "(LlmModel|SceneType|CommandType|MessageType|UserRole|SolutionType|BizCode|ChatModule|WebScene|QuoteType)\":[^,}]+" | sort -u

# Session identifiers
strings "$f" | grep -oE "(sessionid|uid_tt|d_ticket|device_id|odin_tt|msToken|sid_tt|sid_guard)=[^\s;&]+" | sort -u

# Infrastructure / headers
strings "$f" | grep -oE "(Host|X-Tt-[A-Za-z-]+|Content-Security-Policy|Reporting-Endpoints|X-Request-Source|X-Web-Domain): [^\r\n]+" | sort -u

# Anti-bot token count
strings "$f" | grep -oE "X-Bogus=[^ &]+" | sort -u | wc -l

# LLM inputs/outputs
strings "$f" | grep -oE '"(InputText|ContentText|AnswerText)":"[^"]{5,300}"' | sort -u | head -30

# LLM identity clues
strings "$f" | grep -iE "(trained by|base model|underlying|gemini|claude|gpt|doubao|spark|dreamina|llama|mistral)" | head -20

# Server-side code leaks
strings "$f" | grep -oE "[a-z]+\.(equals|startsWith|endsWith|contains)\([^)]+\)" | head -10
```

### Step 4: Determine Report Version

```bash
# Check for existing reports
ls "$reportDir" | grep -E "Burp_Analysis_Report(_[0-9]+)?\.md" | sort
```

- No reports found → this is **Report #1**, filename: `{Target}_Burp_Analysis_Report.md`
- Report #1 exists, #2 does not → this is **Report #2**, filename: `{Target}_Burp_Analysis_Report_2.md`
- Report #N exists → create **Report #N+1**

### Step 5: Read Previous Report (if N > 1)

Read the previous report and extract:
- Endpoint list from Section 16
- Blocker status from Section 13
- Points of Interest from Section 12
- Key findings

### Step 6: Generate Report

Write the full report using the `burp-analysis` skill template. All 16 sections required. For Report #N > 1, prepend a **Delta** section.

## Report Sections

1. Executive Summary
2. Domain Surface
3. Infrastructure Notes
4. LLM Endpoints — Primary Targets
5. Supporting API Endpoints
6. Session Identifiers Observed
7. Anti-Bot / Auth Tokens on LLM Endpoints
8. Observed Scene Values — LLM Flow Mapping
9. LLM Output Content Observed in Traffic
10. LLM Thinking Process / Agent Pipeline Leak
11. LLM Identity Analysis
12. Points of Interest for Active Testing (P1/P2/P3)
13. Blockers
14. Recommended Approach
15. Leaked Server-Side Artifacts
16. Full Discovered API Surface

## Versioning & Delta

When generating Report #2+, the **Delta section** at the top contains:

| Category | Change |
|----------|--------|
| New endpoints discovered | +N |
| Endpoints no longer observed | -N |
| Blockers resolved | List |
| Findings confirmed since last report | List |
| New attack surface | Describe |
| Recommended next step change | Old → New |

## Report Naming Convention

```
{Target}_Burp_Analysis_Report.md      ← Report #1
{Target}_Burp_Analysis_Report_2.md   ← Report #2 (Delta vs #1)
{Target}_Burp_Analysis_Report_3.md   ← Report #3 (Delta vs #2)
```

Target name is derived from the Burp filename unless the user specifies otherwise.

## Output

A numbered `.md` report in the specified output directory, containing all findings, all endpoints, all observed tokens, infrastructure analysis, LLM pipeline mapping, and a prioritized testing plan.
