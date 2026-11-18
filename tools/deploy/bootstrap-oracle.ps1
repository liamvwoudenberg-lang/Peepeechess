<#
  Windows helper for the Oracle deployment: creates the SSH key pair, prints the PUBLIC key and the list of GitHub secrets to add,
  and (optionally) sets them with the GitHub CLI. It never prints a private key or a secret value and creates NO cloud resources.

  Usage (PowerShell 5.1 or 7):
    .\tools\deploy\bootstrap-oracle.ps1                      # key pair + checklist
    .\tools\deploy\bootstrap-oracle.ps1 -SetSecrets          # also upload secrets with `gh secret set` (asks for each value)
#>
[CmdletBinding()]
param(
  [string]$Repo = "liamvwoudenberg-lang/Peepeechess",
  [string]$KeyPath = (Join-Path $HOME ".ssh\peepeechess_oracle"),
  [switch]$SetSecrets
)
$ErrorActionPreference = "Stop"

function Require-Tool([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "$name was not found on PATH." }
}

Require-Tool "ssh-keygen"
$sshDir = Split-Path $KeyPath
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
if (-not (Test-Path $KeyPath)) {
  & ssh-keygen -t ed25519 -N '""' -C "peepeechess-deploy" -f $KeyPath | Out-Null
  Write-Host "Created a new SSH key pair at $KeyPath (the private key stays on this PC)."
} else {
  Write-Host "Using the existing key pair at $KeyPath."
}
Write-Host ""
Write-Host "PUBLIC key (safe to share; add it to the VM's authorized_keys and to the secret ORACLE_SSH_PUBLIC_KEY):"
Get-Content "$KeyPath.pub"
Write-Host ""
Write-Host "GitHub Actions secrets to add (Settings > Secrets and variables > Actions):"
$names = @(
  "OCI_USER_OCID", "OCI_TENANCY_OCID", "OCI_FINGERPRINT", "OCI_REGION", "OCI_API_KEY_PEM",
  "OCI_COMPARTMENT_OCID", "OCI_SUBNET_OCID", "OCI_AVAILABILITY_DOMAIN", "OCI_IMAGE_OCID",
  "ORACLE_SSH_PUBLIC_KEY", "ORACLE_SSH_PRIVATE_KEY", "ORACLE_KNOWN_HOSTS", "ORACLE_HOST", "ORACLE_SSH_USER"
)
$names | ForEach-Object { Write-Host "  $_" }
Write-Host "Repository variable (not secret), set to true only when you want hourly provisioning: ORACLE_PROVISION_ENABLED"
Write-Host "See docs/deployment/ORACLE.md for where each value comes from."

if ($SetSecrets) {
  Require-Tool "gh"
  & gh auth status | Out-Null
  foreach ($name in $names) {
    if ($name -eq "ORACLE_SSH_PRIVATE_KEY") {
      Get-Content -Raw $KeyPath | & gh secret set $name --repo $Repo
    } elseif ($name -eq "ORACLE_SSH_PUBLIC_KEY") {
      Get-Content -Raw "$KeyPath.pub" | & gh secret set $name --repo $Repo
    } else {
      $secure = Read-Host -AsSecureString "Value for $name (leave empty to skip)"
      $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
      if ($plain) { $plain | & gh secret set $name --repo $Repo }
    }
    Write-Host "  processed $name"
  }
}
