# =============================================================================
# Bug Bounty Tool Installer — Windows (PowerShell)
# Installs security tools via winget, Scoop, Go, or direct GitHub download.
# Usage: .\install_tools.ps1 [-WithCicdScanner]
# =============================================================================

param(
    [switch]$WithCicdScanner
)

$ErrorActionPreference = "Continue"

function Write-Ok   { param($m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Err  { param($m) Write-Host "[-] $m" -ForegroundColor Red }
function Write-Warn { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Info { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Bug Bounty Tool Installer (Windows)"
Write-Host "=============================================" -ForegroundColor Cyan

# ── Helper: check if a command exists ────────────────────────────────────────
function Test-Command { param($cmd) return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# ── Helper: download and extract GitHub release binary ───────────────────────
function Install-GithubRelease {
    param(
        [string]$Repo,        # e.g. "projectdiscovery/subfinder"
        [string]$ToolName,    # e.g. "subfinder"
        [string]$AssetPattern # e.g. "subfinder_*_windows_amd64.zip"
    )

    Write-Info "Downloading $ToolName from github.com/$Repo ..."

    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1

        if (-not $asset) {
            Write-Err "${ToolName}: no matching asset '$AssetPattern' in latest release"
            return $false
        }

        $tmpZip  = Join-Path $env:TEMP "$ToolName.zip"
        $tmpDir  = Join-Path $env:TEMP "$ToolName-extract"
        $destDir = "$env:USERPROFILE\tools\bin"

        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Invoke-WebRequest $asset.browser_download_url -OutFile $tmpZip -ErrorAction Stop
        Expand-Archive $tmpZip -DestinationPath $tmpDir -Force

        # Find the binary inside the extracted folder
        $binary = Get-ChildItem -Path $tmpDir -Filter "$ToolName.exe" -Recurse | Select-Object -First 1
        if (-not $binary) {
            # Some zips have no .exe suffix naming
            $binary = Get-ChildItem -Path $tmpDir -Filter $ToolName -Recurse | Select-Object -First 1
        }

        if ($binary) {
            Copy-Item $binary.FullName (Join-Path $destDir "$ToolName.exe") -Force
            Write-Ok "$ToolName installed to $destDir\$ToolName.exe"
        } else {
            Write-Err "${ToolName}: binary not found in extracted archive"
        }

        Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        Write-Err "$ToolName download failed: $_"
        return $false
    }
}

# ── Ensure ~/tools/bin is in PATH ─────────────────────────────────────────────
$userToolsDir = "$env:USERPROFILE\tools\bin"
New-Item -ItemType Directory -Force -Path $userToolsDir | Out-Null

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$userToolsDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$userToolsDir", "User")
    $env:PATH += ";$userToolsDir"
    Write-Warn "Added $userToolsDir to PATH. Restart your terminal to apply."
}

# ── Check for Scoop (optional, for easier installs) ────────────────────────────
$hasScoop = Test-Command "scoop"
if (-not $hasScoop) {
    Write-Warn "Scoop not found. Some tools will be downloaded directly from GitHub."
    Write-Warn "  Install Scoop for easier management: https://scoop.sh"
}

# ── Check for Go (needed for go-install tools) ─────────────────────────────────
$hasGo = Test-Command "go"
if (-not $hasGo) {
    Write-Warn "Go not found. Attempting to install via winget..."
    winget install GoLang.Go --silent 2>$null
    $hasGo = Test-Command "go"
    if ($hasGo) {
        Write-Ok "Go installed"
        # Refresh PATH for go
        $env:PATH += ";$env:USERPROFILE\go\bin;$env:ProgramFiles\Go\bin"
    } else {
        Write-Err "Go install failed. Download from https://golang.org/dl/ and retry."
    }
}

# ── Tools via Scoop (if available) ────────────────────────────────────────────
if ($hasScoop) {
    Write-Host ""
    Write-Info "Installing tools via Scoop..."

    # Add security bucket
    scoop bucket add extras 2>$null | Out-Null
    scoop bucket add nirsoft 2>$null | Out-Null

    $scoopTools = @("nmap", "nuclei", "ffuf")
    foreach ($tool in $scoopTools) {
        if (Test-Command $tool) {
            Write-Ok "$tool already installed ($(Get-Command $tool | Select-Object -ExpandProperty Source))"
        } else {
            Write-Info "Installing $tool via Scoop..."
            scoop install $tool 2>$null
            if (Test-Command $tool) {
                Write-Ok "$tool installed"
            } else {
                Write-Err "$tool failed via Scoop — will try direct download"
            }
        }
    }
}

# ── Tools via winget (nmap as fallback) ────────────────────────────────────────
if (-not (Test-Command "nmap")) {
    Write-Info "Installing nmap via winget..."
    winget install Nmap.Nmap --silent 2>$null
    if (Test-Command "nmap") {
        Write-Ok "nmap installed"
    } else {
        Write-Warn "nmap install failed. Download from https://nmap.org/download.html"
    }
}

# ── ProjectDiscovery tools (direct GitHub download) ───────────────────────────
Write-Host ""
Write-Info "Installing ProjectDiscovery tools..."

$pdTools = @(
    @{ Repo = "projectdiscovery/subfinder";  Name = "subfinder"; Pattern = "subfinder_*_windows_amd64.zip" },
    @{ Repo = "projectdiscovery/httpx";      Name = "httpx";     Pattern = "httpx_*_windows_amd64.zip" },
    @{ Repo = "projectdiscovery/nuclei";     Name = "nuclei";    Pattern = "nuclei_*_windows_amd64.zip" },
    @{ Repo = "projectdiscovery/ffuf";       Name = "ffuf";      Pattern = "ffuf_*_windows_amd64.zip" },
    @{ Repo = "owasp-amass/amass";           Name = "amass";     Pattern = "amass_windows_amd64*.zip" }
)

foreach ($t in $pdTools) {
    if (Test-Command $t.Name) {
        Write-Ok "$($t.Name) already installed"
    } else {
        Install-GithubRelease -Repo $t.Repo -ToolName $t.Name -AssetPattern $t.Pattern | Out-Null
    }
}

# ── Go-based tools ─────────────────────────────────────────────────────────────
if ($hasGo) {
    Write-Host ""
    Write-Info "Installing Go-based tools..."

    $goPath = if ($env:GOPATH) { $env:GOPATH } else { "$env:USERPROFILE\go" }
    $goBin  = Join-Path $goPath "bin"

    if ($env:PATH -notlike "*$goBin*") {
        $env:PATH += ";$goBin"
    }

    $goTools = @(
        @{ Pkg = "github.com/lc/gau/v2/cmd/gau@latest";   Name = "gau" },
        @{ Pkg = "github.com/hahwul/dalfox/v2@latest";    Name = "dalfox" },
        @{ Pkg = "github.com/haccer/subjack@latest";       Name = "subjack" }
    )

    foreach ($t in $goTools) {
        if (Test-Command $t.Name) {
            Write-Ok "$($t.Name) already installed"
        } else {
            Write-Info "Installing $($t.Name)..."
            go install $t.Pkg 2>$null
            if (Test-Command $t.Name) {
                Write-Ok "$($t.Name) installed"
            } else {
                Write-Err "$($t.Name) install failed (check go output above)"
            }
        }
    }
}

# ── sisakulint (CI/CD scanner) ─────────────────────────────────────────────────
Write-Host ""
Write-Info "Installing sisakulint..."

if (Test-Command "sisakulint") {
    Write-Ok "sisakulint already installed"
} elseif ($hasGo) {
    Write-Info "No Windows binary — building from source via go install..."
    go install github.com/sisaku-security/sisakulint@latest 2>$null
    if (Test-Command "sisakulint") {
        Write-Ok "sisakulint installed"
    } else {
        Write-Err "sisakulint build failed. Try manually: go install github.com/sisaku-security/sisakulint@latest"
    }
} else {
    Write-Warn "sisakulint requires Go. Install Go first, then run: go install github.com/sisaku-security/sisakulint@latest"
}

# ── cicd_scanner wrapper (optional) ───────────────────────────────────────────
if ($WithCicdScanner) {
    $cicdSrc = Join-Path $PSScriptRoot "tools\cicd_scanner.sh"
    if (Test-Path $cicdSrc) {
        $destBin = "$env:USERPROFILE\tools\bin\cicd_scanner.sh"
        Copy-Item $cicdSrc $destBin -Force
        Write-Ok "cicd_scanner.sh copied to $destBin (run via Git Bash or WSL)"
    }
} else {
    Write-Warn "cicd_scanner skipped (use -WithCicdScanner to include)"
}

# ── Update nuclei templates ────────────────────────────────────────────────────
if (Test-Command "nuclei") {
    Write-Host ""
    Write-Info "Updating nuclei templates..."
    nuclei -update-templates 2>$null
    Write-Ok "Nuclei templates updated"
}

# ── Verification ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Info "Installation Verification"
Write-Host "=============================================" -ForegroundColor Cyan

$allTools = @("subfinder", "httpx", "nuclei", "ffuf", "nmap", "amass", "gau", "dalfox", "subjack", "sisakulint")
$installed = 0
$missing   = 0

foreach ($tool in $allTools) {
    if (Test-Command $tool) {
        $path = (Get-Command $tool).Source
        Write-Ok "$tool`: $path"
        $installed++
    } else {
        Write-Err "$tool`: NOT FOUND"
        $missing++
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Installed: $installed / $($allTools.Count)"
if ($missing -gt 0) {
    Write-Host "  Missing:   $missing (see errors above)" -ForegroundColor Yellow
    Write-Host ""
    Write-Warn "Tip: Run Git Bash or WSL and use the original install_tools.sh"
    Write-Warn "     for any tools that failed here."
}
Write-Host "=============================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Restart your terminal to apply PATH changes"
Write-Host "  2. Run: .\install.ps1   (installs skills + commands into Claude Code)"
Write-Host "  3. Run: claude"
Write-Host "  4. Run: /recon target.com"
