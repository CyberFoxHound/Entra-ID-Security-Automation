<# ======================================================================
   Export Entra ID role assignments with rich identity metadata
   ----------------------------------------------------------------------
   REQS: Connect-MgGraph -Scopes "Directory.Read.All","RoleManagement.Read.Directory","AdministrativeUnit.Read.All"
   OUTPUT: .\All_Assigned_Roles.csv
#>

function Get-PrincipalMetadata {
    param([Parameter(Mandatory)][string]$Id)

    # ---------- User ----------
    $u = Get-MgUser -UserId $Id `
        -Property UserPrincipalName,DisplayName,UserType,JobTitle,CompanyName,
                  Department,AccountEnabled,OnPremisesSyncEnabled `
        -ErrorAction SilentlyContinue
    if ($u) {
        return [pscustomobject]@{
            PrincipalType       = 'User'
            ObjectType          = '#microsoft.graph.user'
            DisplayName         = $u.DisplayName
            UserPrincipalName   = $u.UserPrincipalName
            UserType            = $u.UserType
            JobTitle            = $u.JobTitle
            CompanyName         = $u.CompanyName
            Department          = $u.Department
            AccountEnabled      = $u.AccountEnabled
            OnPremSyncEnabled   = $u.OnPremisesSyncEnabled
        }
    }

    # ---------- Group ----------
    $g = Get-MgGroup -GroupId $Id -Property DisplayName,MailNickname -ErrorAction SilentlyContinue
    if ($g) {
        return [pscustomobject]@{
            PrincipalType       = 'Group'
            ObjectType          = '#microsoft.graph.group'
            DisplayName         = $g.DisplayName
            UserPrincipalName   = $g.MailNickname
            UserType            = $null
            JobTitle            = $null
            CompanyName         = $null
            Department          = $null
            AccountEnabled      = $null
            OnPremSyncEnabled   = $null
        }
    }

    # ---------- Service principal ----------
    $sp = Get-MgServicePrincipal -ServicePrincipalId $Id -Property DisplayName,AppId -ErrorAction SilentlyContinue
    if ($sp) {
        return [pscustomobject]@{
            PrincipalType       = 'ServicePrincipal'
            ObjectType          = '#microsoft.graph.servicePrincipal'
            DisplayName         = $sp.DisplayName
            UserPrincipalName   = $sp.AppId
            UserType            = $null
            JobTitle            = $null
            CompanyName         = $null
            Department          = $null
            AccountEnabled      = $null
            OnPremSyncEnabled   = $null
        }
    }

    # ---------- Device ----------
    $d = Get-MgDevice -DeviceId $Id -Property DisplayName -ErrorAction SilentlyContinue
    if ($d) {
        return [pscustomobject]@{
            PrincipalType       = 'Device'
            ObjectType          = '#microsoft.graph.device'
            DisplayName         = $d.DisplayName
            UserPrincipalName   = $null
            UserType            = $null
            JobTitle            = $null
            CompanyName         = $null
            Department          = $null
            AccountEnabled      = $null
            OnPremSyncEnabled   = $null
        }
    }

    # ---------- Fallback ----------
    [pscustomobject]@{
        PrincipalType       = 'Unknown'
        ObjectType          = $null
        DisplayName         = $null
        UserPrincipalName   = $null
        UserType            = $null
        JobTitle            = $null
        CompanyName         = $null
        Department          = $null
        AccountEnabled      = $null
        OnPremSyncEnabled   = $null
    }
}

function Resolve-DirectoryScopeName {
    param(
        [string]$ScopeId,
        [string]$ScopeType
    )

    if (-not $ScopeId) { return $null }

    try {
        switch ($ScopeType) {
            "AdministrativeUnit" {
                $au = Get-MgAdministrativeUnit -AdminUnitId $ScopeId -ErrorAction SilentlyContinue
                return $au.DisplayName
            }
            "DirectoryRole" {
                $dr = Get-MgDirectoryRole -RoleId $ScopeId -ErrorAction SilentlyContinue
                return $dr.DisplayName
            }
            default {
                return $ScopeId
            }
        }
    }
    catch {
        return $ScopeId
    }
}

Write-Host "⏳ Gathering role definitions..."
$roles = Get-MgRoleManagementDirectoryRoleDefinition -All

$result = foreach ($r in $roles) {
    $assigns = Get-MgRoleManagementDirectoryRoleAssignment `
                 -Filter "roleDefinitionId eq '$($r.Id)'" -ExpandProperty Principal

    foreach ($a in $assigns) {
        $m = Get-PrincipalMetadata -Id $a.PrincipalId
        $directoryScopeName = Resolve-DirectoryScopeName -ScopeId $a.DirectoryScopeId -ScopeType $a.DirectoryScopeType

        # Determine if eligible or permanent (PIM)
        $assignmentType = if ($a.AssignmentType) { $a.AssignmentType } else { 'Permanent' }

        # If eligible, use assignment schedule end datetime as EndDateTime
        $endDate = if ($assignmentType -eq 'Eligible' -and $a.AssignmentScheduleEndDateTime) {
            $a.AssignmentScheduleEndDateTime
        } else {
            $a.AssignmentScheduleEndDateTime ?? $a.AssignmentEndDateTime ?? $null
        }

		[pscustomobject]@{
			# Role / assignment
			RoleName           = $r.DisplayName
			RoleTemplateId     = $r.TemplateId
			IsBuiltIn          = $r.IsBuiltIn
			AssignmentId       = $a.Id
			UserPrincipalName  = $m.UserPrincipalName
			DisplayName        = $m.DisplayName
			JobTitle           = $m.JobTitle
			CompanyName        = $m.CompanyName
			Department         = $m.Department
			PrincipalType      = $m.PrincipalType
			UserType           = $m.UserType
			AccountEnabled     = $m.AccountEnabled
			OnPremSyncEnabled  = $m.OnPremSyncEnabled

			Scope              = if ($a.Scope -eq '/') { 'Tenant-wide' } else { $a.Scope }
			StartDateTime      = $a.AssignmentScheduleStartDateTime ?? $a.AssignmentStartDateTime ?? $null
			EndDateTime        = $endDate
			AssignmentType     = $assignmentType
			ObjectType         = $m.ObjectType

			DirectoryScopeId   = $a.DirectoryScopeId
			DirectoryScopeType = $a.DirectoryScopeType
			DirectoryScopeName = $directoryScopeName
		}
    }
}

$export = ".\All_Assigned_Roles.csv"
$result | Sort-Object RoleName,UserPrincipalName | Export-Csv $export -NoTypeInformation
Write-Host "`n✅  Export complete: $export"
