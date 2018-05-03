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

        [parameter(Mandatory = $true)]
        [System.String]
        $Account,

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

    if( $PrefixComputerName ) { $Name = Get-PrefixComputerName $Name }

    $returnValue = @{ Name = $Name }
    $agent = Get-VSTSAgent -NameFilter $Name -AgentDirectory $AgentDirectory
    if ( $agent ) {
        $returnValue['Account'] = $agent.Account
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

        [parameter(Mandatory = $true)]
        [System.String]
        $AgentDirectory,

        [parameter(Mandatory = $true)]
        [System.String]
        $Account,

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

    if( $PrefixComputerName ) { $Name = Get-PrefixComputerName $Name }

    if ( $Ensure -eq 'Present') {
        $installArgs = @{
            Name           = $Name 
            Pool           = $Pool
            Account        = $Account
            PAT            = $AccountCredential.Password
            AgentDirectory = $AgentDirectory
            Replace        = $true
        }

        if ( $LogonCredential ) { $installArgs['LogonCredential'] = $LogonCredential }
        
        Install-VSTSAgent @installArgs
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

        [parameter(Mandatory = $true)]
        [System.String]
        $AgentDirectory,

        [parameter(Mandatory = $true)]
        [System.String]
        $Account,

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

    if( $PrefixComputerName ) { $Name = Get-PrefixComputerName $Name }

    $agent = Get-VSTSAgent -NameFilter $Name -AgentDirectory $AgentDirectory
    switch ($Ensure) {
        'Present' { 
            if ( -not $agent ) { return $false }
            if ( $agent.Account -ne $Account ) { return $false }
            return $true
        }
        'Absent' { return (-not $agent) }
    }
}


Export-ModuleMember -Function *-TargetResource

