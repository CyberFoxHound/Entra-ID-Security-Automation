<#
  EXPORT ADMIN ROLE ASSIGNMENTS **UNPROTECTED BY MFA CAPs**
  ----------------------------------------------------------
  1. Runs Generate_all_roles.ps1 → All_Assigned_Roles.csv
  2. Loads that CSV (all assignments in the tenant).
  3. Prompts user to choose:
        - Enabled CAPs only (state = enabled)
        - All CAPs (enabled, disabled, report-only)
  4. Retrieves Conditional Access policies enforcing MFA and targeting roles
     according to user choice.
  5. Resolves each role‑template GUID → friendly role name.
  6. For each CAP, prints:
        • CAP name + state
        • Friendly role names it already protects
        • How many of the 119 built‑in admin roles it leaves unprotected
  7. Filters the assignment list to exclude roles protected by any MFA CAP
     and exports the result to:
        Unprotected_Assigned_Roles_not_covered_By_MFA.csv

  Required Graph scopes:
    Directory.Read.All
    Policy.Read.All
    RoleManagement.Read.Directory
#>

# -------------------------------------------------------------------------
# 0. Run the role‑gathering script first
# -------------------------------------------------------------------------
& "$PSScriptRoot\Generate_all_roles.ps1"

# -------------------------------------------------------------------------
# 1. Load the full role‑assignment CSV
# -------------------------------------------------------------------------
$allCsv = Join-Path $PSScriptRoot 'All_Assigned_Roles.csv'
if (-not (Test-Path $allCsv)) {
    throw "❌  Role assignment CSV not found: $allCsv"
}
$allAssignments = Import-Csv $allCsv

# -------------------------------------------------------------------------
# 2. Get template catalogue (119 built‑in admin roles)
# -------------------------------------------------------------------------
$Templates  = Get-MgDirectoryRoleTemplate -All
$TplLookup  = @{}
$roleIdToBuiltIn = @{}
$Templates | ForEach-Object {
    $id = $_.Id.ToString().ToLower()
    $TplLookup[$id] = $_.DisplayName
    $roleIdToBuiltIn[$id] = $true
}

# -------------------------------------------------------------------------
# 3. Prompt user: Enabled only or All CAPs
# -------------------------------------------------------------------------
Write-Host ""
Write-Host "Choose which Conditional Access Policies to retrieve:" -ForegroundColor Cyan
Write-Host "  1) Enabled CAPs only (state = enabled)"
Write-Host "  2) All CAPs (enabled, disabled, report-only)"

do {
    $choice = Read-Host "Enter 1 or 2"
} while ($choice -notin @('1', '2'))

# -------------------------------------------------------------------------
# 4. Fetch MFA‑enforcing CAPs that target roles based on choice
# -------------------------------------------------------------------------
Write-Host "`nRetrieving Conditional Access policies enforcing MFA..."

switch ($choice) {
    '1' {
        $Policies = Get-MgIdentityConditionalAccessPolicy -All | Where-Object {
            $_.State -eq 'enabled' -and
            $_.Conditions.Users.IncludeRoles -and
            ($_.GrantControls.BuiltInControls -contains 'mfa')
        }
    }
    '2' {
        $Policies = Get-MgIdentityConditionalAccessPolicy -All | Where-Object {
            $_.Conditions.Users.IncludeRoles -and
            ($_.GrantControls.BuiltInControls -contains 'mfa')
        }
    }
}

if (-not $Policies) {
    Write-Host "No MFA Conditional Access policies found for the selected criteria." -ForegroundColor Yellow
}

# -------------------------------------------------------------------------
# 5. Show CAP info + count of admin roles NOT included (always print CAP state)
# -------------------------------------------------------------------------
$excludedRoleIds = @()

foreach ($cap in $Policies) {
    $includedNames = @()

    foreach ($roleId in $cap.Conditions.Users.IncludeRoles) {
        $idStr = $roleId.ToString().ToLower()
        if ($TplLookup[$idStr]) { $includedNames += $TplLookup[$idStr] }
        else                    { $includedNames += $roleId }   # fallback
        $excludedRoleIds += $idStr
    }

    Write-Host ""
    Write-Host "CAP Name: $($cap.DisplayName)   (State: $($cap.State))" -ForegroundColor Cyan
    Write-Host "Included Roles protected by MFA:" -ForegroundColor Yellow
    $includedNames | Sort-Object | ForEach-Object { Write-Host "  • $_" }

    $nonIncludedCount = 119 - $includedNames.Count
    Write-Host "Number of admin roles NOT included in this CAP: $nonIncludedCount" -ForegroundColor Magenta
}

$excludedRoleIds = $excludedRoleIds | Sort-Object -Unique

# -------------------------------------------------------------------------
# 6. Filter assignments NOT in any MFA‑protected role + add extra info columns
# -------------------------------------------------------------------------
$unprotectedAssignments = foreach ($a in $allAssignments) {
    $roleId = $a.RoleTemplateId.ToLower()

    if ($excludedRoleIds -contains $roleId) {
        continue
    }

    $isBuiltIn = $TplLookup.ContainsKey($roleId)
    $isGDAP = ($a.PrincipalType -eq 'ForeignGroup' -and $a.DirectoryScopeType -eq 'CustomerTenant')

    # Create a new object to control which properties to export and include new columns
    [pscustomobject]@{
        AssignmentId       = $a.AssignmentId
        RoleName           = $a.RoleName
        RoleTemplateId     = $a.RoleTemplateId
        UserPrincipalName  = $a.UserPrincipalName
        DisplayName        = $a.DisplayName
        JobTitle           = $a.JobTitle
        CompanyName        = $a.CompanyName
        Department         = $a.Department
        PrincipalType      = $a.PrincipalType
        UserType           = $a.UserType
        AccountEnabled     = $a.AccountEnabled
        OnPremSyncEnabled  = $a.OnPremSyncEnabled
        Scope              = $a.Scope
        StartDateTime      = $a.StartDateTime
        EndDateTime        = $a.EndDateTime
        AssignmentType     = if ($a.PSObject.Properties.Name -contains 'AssignmentType') { $a.AssignmentType } else { $null }
        DirectoryScopeId   = $a.DirectoryScopeId
        DirectoryScopeType = $a.DirectoryScopeType
        DirectoryScopeName = if ($a.PSObject.Properties.Name -contains 'DirectoryScopeName') { $a.DirectoryScopeName } else { $null }
        IsBuiltIn          = $isBuiltIn
        IsGDAPAssignment   = $isGDAP
    }
}

# -------------------------------------------------------------------------
# 7. Console summary (unique roles only)
# -------------------------------------------------------------------------
$uniqueUnprotectedRoles = $unprotectedAssignments |
                          Group-Object RoleName |
                          Sort-Object Name

Write-Host "`n📋 Tenant Assigned Roles not covered by MFA: $($uniqueUnprotectedRoles.Count)" -ForegroundColor Green

if ($uniqueUnprotectedRoles.Count -gt 0) {
    Write-Host "`nUnprotected Assigned Roles:" -ForegroundColor Yellow
    $uniqueUnprotectedRoles | ForEach-Object {
        Write-Host "• $($_.Name)"
    }
} else {
    Write-Host "No unprotected assigned roles found." -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# 8. Export CSV
# -------------------------------------------------------------------------
$exportPath = Join-Path $PSScriptRoot 'Unprotected_Assigned_Roles_not_covered_By_MFA.csv'
$unprotectedAssignments | Export-Csv $exportPath -NoTypeInformation

Write-Host "`n✅  Unprotected roles by MFA exported to:`n   $exportPath" -ForegroundColor Green
