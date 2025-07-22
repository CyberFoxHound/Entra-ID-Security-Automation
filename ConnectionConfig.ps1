# =============================================================================
# PowerShell Connection Configuration (Client Secret version)
# Save this as: ConnectionConfig.ps1
# =============================================================================

# Azure AD / Entra ID App Registration Settings
$Global:ConnectionConfig = @{
    TenantId       = ""  # Your Tenant ID
    ClientId       = ""  # App Registration (Client ID)
    ClientSecret   = ""  # App client secret (replace this!)
    Organization   = ""             # Exchange Online domain
}
# -----------------------------------------------------------------------------
# Connect to Microsoft Graph (Entra ID)
# -----------------------------------------------------------------------------
function Connect-ToGraph {
    $secureSecret = ConvertTo-SecureString $Global:ConnectionConfig.ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential (
        $Global:ConnectionConfig.ClientId,
        $secureSecret
    )

    Connect-MgGraph -TenantId $Global:ConnectionConfig.TenantId -Credential $credential

    $ctx = Get-MgContext
    Write-Host "✅ Connected to Microsoft Graph as app: $($ctx.ClientId)" -ForegroundColor Green
    Write-Host "Scopes: $($ctx.Scopes -join ', ')" -ForegroundColor Yellow
}




# -----------------------------------------------------------------------------
# Connect to Exchange Online (App-Only)
# -----------------------------------------------------------------------------
function Connect-ToExchange {
    Connect-ExchangeOnline `
        -AppId        $Global:ConnectionConfig.ClientId `
        -ClientSecret $Global:ConnectionConfig.ClientSecret `
        -TenantId     $Global:ConnectionConfig.TenantId `
        -Organization $Global:ConnectionConfig.Organization

    Write-Host "✅ Connected to Exchange Online as App Registration" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Connect to Azure (Az.Accounts)
# -----------------------------------------------------------------------------
function Connect-ToAzure {
    $secureSecret = ConvertTo-SecureString $Global:ConnectionConfig.ClientSecret -AsPlainText -Force
    $credential   = New-Object System.Management.Automation.PSCredential (
        $Global:ConnectionConfig.ClientId,
        $secureSecret
    )

    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId   $Global:ConnectionConfig.TenantId `
        -Credential $credential

    Write-Host "✅ Connected to Azure (Az module) using client secret" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Show current config
# -----------------------------------------------------------------------------
function Show-ConnectionInfo {
    Write-Host "=== Connection Configuration ===" -ForegroundColor Cyan
    Write-Host "Tenant ID:        $($Global:ConnectionConfig.TenantId)" -ForegroundColor Yellow
    Write-Host "Client ID:        $($Global:ConnectionConfig.ClientId)" -ForegroundColor Yellow
    Write-Host "Client Secret:    ***hidden***" -ForegroundColor Yellow
    Write-Host "Organization:     $($Global:ConnectionConfig.Organization)" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Info banner
# -----------------------------------------------------------------------------
Write-Host "Connection configuration loaded!" -ForegroundColor Green
Write-Host "Available commands:" -ForegroundColor Cyan
Write-Host "  Connect-ToGraph" -ForegroundColor White
Write-Host "  Connect-ToExchange" -ForegroundColor White
Write-Host "  Connect-ToAzure" -ForegroundColor White
Write-Host "  Show-ConnectionInfo" -ForegroundColor White
