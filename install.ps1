# Claude Bug Bounty — Windows installer (PowerShell)
# Installs skills and commands into %USERPROFILE%\.claude\

$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:USERPROFILE ".claude\skills"
$CommandsDir = Join-Path $env:USERPROFILE ".claude\commands"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $CommandsDir | Out-Null

Write-Host "Installing Claude Bug Bounty skills..." -ForegroundColor Cyan
Write-Host ""

# Copy skills
Get-ChildItem -Path "skills" -Directory | ForEach-Object {
    $skillName = $_.Name
    $destDir = Join-Path $InstallDir $skillName
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item (Join-Path $_.FullName "SKILL.md") (Join-Path $destDir "SKILL.md") -Force
    Write-Host "  [+] Installed skill: $skillName" -ForegroundColor Green
}

Write-Host ""

# Copy commands
Get-ChildItem -Path "commands" -Filter "*.md" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $CommandsDir $_.Name) -Force
    Write-Host "  [+] Installed command: $($_.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done! Skills installed to: $InstallDir" -ForegroundColor Green
Write-Host "Commands installed to:     $CommandsDir" -ForegroundColor Green
Write-Host ""

# Offer Burp MCP setup
Write-Host "─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Optional: Burp Suite MCP Integration"
Write-Host "─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Connect to PortSwigger's Burp MCP server for live HTTP traffic visibility."
Write-Host "See mcp\burp-mcp-client\README.md for setup instructions."
Write-Host ""
$setupBurp = Read-Host "Set up Burp MCP now? (y/N)"
if ($setupBurp -match "^[Yy]$") {
    Write-Host ""
    Write-Host "To connect Burp MCP, add this to your Claude Code settings:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  claude config edit" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Then add to the mcpServers section:" -ForegroundColor Cyan
    $burpConfig = Get-Content "mcp\burp-mcp-client\config.json" | ConvertFrom-Json
    Write-Host ($burpConfig | ConvertTo-Json -Depth 10) -ForegroundColor Gray
    Write-Host ""
    Write-Host "And set your Burp API key:" -ForegroundColor Cyan
    Write-Host '  $env:BURP_API_KEY = "your-api-key-here"' -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Start hunting:" -ForegroundColor Green
Write-Host "  claude"
Write-Host "  /recon target.com"
Write-Host "  /hunt target.com"
