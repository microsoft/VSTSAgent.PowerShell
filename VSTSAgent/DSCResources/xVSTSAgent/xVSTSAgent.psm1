# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

function Get-PrefixComputerName {
    param(
        [parameter(Mandatory = $true)]
        [string]$Name
    )

    "$($env:COMPUTERNAME)-$Name"
}

<#
.SYNOPSIS
    Returns the status of vsts agent installs.
.PARAMETER Name
    The name of the agent to get.
.PARAMETER AgentDirectory
    The directory to search for installed agents.
.PARAMETER Account
    Unused - the account is discovered, not dictated.
.PARAMETER AccountCredential
    Unused - not necessary for discovery.
.PARAMETER LogonCredential
    Unused - not necessary for discovery.
.PARAMETER Ensure
    Unused - not necessary for discovery.
#>
function Get-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [parameter(Mandatory = $true)]
        [System.String]
        $AgentDirectory,

        [parameter(Mandatory = $false)]
        [System.String]
        $Work,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerUrl,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AccountCredential,

        [System.Management.Automation.PSCredential]
        $LogonCredential,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = 'Present',

        [System.Boolean]
        $PrefixComputerName = $false
    )

    if ( $PrefixComputerName ) { $Name = Get-PrefixComputerName $Name }

    $returnValue = @{ 'Name' = $Name; 'AgentDirectory' = $AgentDirectory }
    $agent = Get-VSTSAgent -NameFilter $Name -AgentDirectory $AgentDirectory
    if ( $agent ) {
        $returnValue['ServerUrl'] = $agent.ServerUrl
        $returnValue['Work'] = "$($agent.Work)"
        $returnValue['PoolId'] = "$($agent.PoolId)"
        $returnValue['Ensure'] = 'Present'
    }
    else {
        $returnValue['Ensure'] = 'Absent'
    }

    $returnValue
}

<#
.SYNOPSIS
    Installs or uninstalls the specified agent.
.PARAMETER Name
    What's the name of the agent we're concerned with?
.PARAMETER Pool
    What's the pool of the agent we're concerned with? Note, only used on install.
.PARAMETER AgentDirectory
    What directory is used for agents?
.PARAMETER Account
    What VSTS account should we be concerned with?
.PARAMETER AccountCredential
    The credential used to auth with VSTS.
.PARAMETER LogonCredential
    What credential should the agent service use?
.PARAMETER Ensure
    Should we ensure the agent exists or that it doesn't?
#>
function Set-TargetResource {
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [System.String]
        $Pool = 'Default',

        [System.String]
        $DeploymentGroup = '',

        [System.String]
        $DeploymentGroupTags = '',

        [System.String]
        [string]$ProjectName = '',

        [parameter(Mandatory = $true)]
        [System.String]
        $AgentDirectory,

        [parameter(Mandatory = $false)]
        [System.String]
        $Work,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerUrl,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AccountCredential,

        [System.Management.Automation.PSCredential]
        $LogonCredential,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = 'Present',

        [System.Boolean]
        $PrefixComputerName = $false
    )

    if ( Test-TargetResource @PSBoundParameters ) { return }

    if ( $PrefixComputerName ) { $Name = Get-PrefixComputerName $Name }

    if ( $Ensure -eq 'Present') {
        $installArgs = @{
            'Name'                  = $Name 
            'Pool'                  = $Pool
            'ServerUrl'             = $ServerUrl
            'PAT'                   = $AccountCredential.Password
            'AgentDirectory'        = $AgentDirectory
            'Replace'               = $true
            'DeploymentGroup'       = $DeploymentGroup
            'DeploymentGroupTags'   = $DeploymentGroupTags
            'ProjectName'           = $ProjectName
        }

        if ( $Work ) { $installArgs['Work'] = $Work }
        if ( $LogonCredential ) { $installArgs['LogonCredential'] = $LogonCredential }
        
        Install-VSTSAgent @installArgs
    }
    else {
        Uninstall-VSTSAgent -Name $Name -AgentDirectory $AgentDirectory -PAT $AccountCredential.Password 
    }
}

<#
.SYNOPSIS
    Test the status of the specified agent.
.PARAMETER Name
    What's the name of the agent we're concerned with?
.PARAMETER Pool
    Unused - Agent pool is not currently detectable.
.PARAMETER AgentDirectory
    What directory should we search for agents?
.PARAMETER Account
    What account should the agent use?
.PARAMETER AccountCredential
    Unused - testing does not require credentials.
.PARAMETER LogonCredential
    Unused - agent service logon user is not currently detectable.
.PARAMETER Ensure
    Should the agent be present or absent?
#>
function Test-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [System.String]
        $Pool = 'Default',

        [System.String]
        $DeploymentGroup = '',

        [System.String]
        $DeploymentGroupTags = '',

        [System.String]
        [string]$ProjectName = '',

        [parameter(Mandatory = $true)]
        [System.String]
        $AgentDirectory,

        [parameter(Mandatory = $false)]
        [System.String]
        $Work,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerUrl,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AccountCredential,

        [System.Management.Automation.PSCredential]
        $LogonCredential,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = 'Present',

        [System.Boolean]
        $PrefixComputerName = $false
    )

    if ( $PrefixComputerName ) { $Name = Get-PrefixComputerName $Name }

    $agent = Get-VSTSAgent -NameFilter $Name -AgentDirectory $AgentDirectory -Verbose

    switch ($Ensure) {
        'Present' {
            if ( -not $agent ) { return $false }

            Write-Verbose "Found agent pointed to $($agent.ServerUrl) and working from $($agent.Work)"
            if ( $agent.ServerUrl -ne $ServerUrl ) {
                Write-Verbose "ServerUrl mismatch: $($agent.ServerUrl) -ne $ServerUrl"
                return $false 
            }
            if ( $Work -and $agent.Work -ne $Work ) { 
                Write-Verbose "Work folder mismatch: $($agent.Work) -ne $Work"
                return $false 
            }
            # TODO: Get back to pool name from $agent.PoolId.

            Write-Verbose "VSTS Agent is Present"
            return $true
        }
        'Absent' { 
            if ( $agent ) { 
                Write-Verbose "Found agent pointed to $($agent.ServerUrl) and working from $($agent.Work)"
                return $false
            } 

            Write-Verbose "VSTS Agent is Absent"
            return $true
        }
    }
}


Export-ModuleMember -Function *-TargetResource

