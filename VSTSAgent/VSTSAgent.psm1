# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

class VSTSAgentVersion : System.IComparable {
    [int] $Major;
    [int] $Minor;
    [int] $Revision;

    VSTSAgentVersion([string] $version) {

        $version -match "(\d+)\.(\d+)\.(\d+)" | Out-Null
        if ( $Matches.Count -ne 4 ) { throw "Invalid VSTS Agent version: $version" } 

        $this.Major = [int]($Matches[1]);
        $this.Minor = [int]($Matches[2]);
        $this.Revision = [int]($Matches[3]);
    }

    [string] ToString() {
        $result = "$($this.Major).$($this.Minor).$($this.Revision)"
        return $result
    }

    [int] CompareTo([object]$obj) {
        if ($null -eq $obj) { return 1 }
        if ($obj -isnot [VSTSAgentVersion]) { throw "Object is not a VSTSAgentVersion"}
        
        return [VSTSAgentVersion]::Compare($this, $obj)
    }

    static [int] Compare([VSTSAgentVersion]$a, [VSTSAgentVersion]$b) {
        if ($a.Major -lt $b.Major) { return -1 }
        if ($a.Major -gt $b.Major) { return 1 }
        
        if ($a.Minor -lt $b.Minor) { return -1 }
        if ($a.Minor -gt $b.Minor) { return 1 }
        
        if ($a.Revision -lt $b.Revision) { return -1 }
        if ($a.Revision -gt $b.Revision) { return 1 }

        return 0
    }

    [boolean] Equals ( [object]$obj ) {   
        return [VSTSAgentVersion]::Compare($this, $obj) -eq 0;
    } 
}

<#
.SYNOPSIS
    Enable TLS12 security protocol required by the GitHub https certs.
#>
function Set-SecurityProtocol {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $secProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    if ( ($secProtocol -band [System.Net.SecurityProtocolType]::Tls12) -ne 0 ) { return }

    if ( $PSCmdlet.ShouldProcess('[System.Net.ServicePointManager]::SecurityProtocol', 'Add [System.Net.SecurityProtocolType]::Tls12') ) {
        $secProtocol += [System.Net.SecurityProtocolType]::Tls12;
        [System.Net.ServicePointManager]::SecurityProtocol = $secProtocol
    }
}

<#
.SYNOPSIS
    Convert current OS platform to required Agent platform
#>
function Get-Platform {
    param ([string]$OS = $PSVersionTable.OS)

    switch -regex ($OS) {
        'linux' { 'linux' }
        'darwin' { 'osx' }
        default { 'win' }
    }
}

<#
.SYNOPSIS
    Finds available VSTS agents
.DESCRIPTION
    Searches the agent's Github release pages for available versions of the Agent.
.PARAMETER MinimumVersion
    The minimum agent version required.
.PARAMETER MaximumVersion
    The maximum agent version allowed.
.PARAMETER RequiredVersion
    The required agent version.
.PARAMETER Latest
    Find the latest available agent version.
.PARAMETER Platform
    The platform required for the agent.
#>
function Find-VSTSAgent {
    [CmdletBinding( DefaultParameterSetName = "NoVersion")]
    param(
        
        [parameter(Mandatory = $true, ParameterSetName = 'MinVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MinimumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'MaxVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MaximumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
        [VSTSAgentVersion]$RequiredVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'Latest')]
        [switch]$Latest,

        [parameter(Mandatory = $false)]
        [string]$Platform
    )

    if ( $Latest ) {

        $findArgs = @{ }
        if ( $Platform ) { $findArgs['Platform'] = $Platform }
        $sortedAgents = Find-VSTSAgent @findArgs | Sort-Object -Descending -Property Version
        $sortedAgents | Where-Object { $_.Version -eq $sortedAgents[0].Version }
        return
    }

    Set-SecurityProtocol

    $rootUri = [uri]"https://github.com"
    $releasesRelativeUri = [uri]"/Microsoft/vsts-agent/releases"
    
    $page = [uri]::new( $rootUri, $releasesRelativeUri )
    $queriedPages = @()

    do {
        
        $result = Invoke-WebRequest $page -UseBasicParsing
        $result.Links.href | Where-Object { $_ -match "vsts-agent-(\w+)-x64-(\d+\.\d+\.\d+)\..+$" } | ForEach-Object {
            
            $instance = [PSCustomObject] @{
                'Platform' = $Matches[1]
                'Version'  = [VSTSAgentVersion]$Matches[2]
                'Uri'      = [uri]::new($_, [System.UriKind]::RelativeOrAbsolute)   
            }

            # Make it absolute
            if ( -not $instance.Uri.IsAbsoluteUri ) { $instance.Uri = [uri]::new($rootUri, $instance.Uri) }

            if ( $RequiredVersion -and $instance.Version -ne $RequiredVersion) { return }
            if ( $MinimumVersion -and $instance.Version -lt $MinimumVersion) { return }
            if ( $MaximumVersion -and $instance.Version -gt $MaximumVersion) { return }
            if ( $Platform -and $instance.Platform -ne $Platform) { return }

            Write-Verbose "Found agent at $($instance.Uri)"
            Write-Output $instance
        }

        $queriedPages += $page
        $page = $result.Links.href | Where-Object { 
            $_ -match "$releasesRelativeUri\?after=v(\d+\.\d+\.\d+)$" -and $queriedPages -notcontains $_
        } | Select-Object -First 1

    } while ($page)
}


<#
.SYNOPSIS
    Install a VSTS Agent.
.DESCRIPTION
    Download and install a VSTS Agent matching the specified requirements.
.PARAMETER MinimumVersion
    The minimum agent version required.
.PARAMETER MaximumVersion
    The maximum agent version allowed.
.PARAMETER RequiredVersion
    The required agent version.
.PARAMETER AgentDirectory
    What directory should agents be installed into?
.PARAMETER Work
    Work directory where job data is stored. Defaults to _work under the
    root of the agent directory. The work directory is owned by a given
    agent and should not share between multiple agents.
.PARAMETER Name
    What name should the agent use?
.PARAMETER Pool
    What pool should the agent be registered into?
.PARAMETER PAT
    What personal access token (PAT) should be used to auth with VSTS?
.PARAMETER ServerUrl
    What server url should the agent be registered to? Eg. 'https://account.visualstudio.com'
.PARAMETER Replace
    Should the new agent replace any existing one on the account?
.PARAMETER LogonCredential
    What user credentials should be used by the agent service?
.PARAMETER Cache
    Where should agent downloads be cached?
#>
function Install-VSTSAgent {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "NoVersion")]
    param(
        
        [parameter(Mandatory = $true, ParameterSetName = 'MinVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MinimumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'MaxVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MaximumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
        [VSTSAgentVersion]$RequiredVersion,

        [parameter(Mandatory = $false)]
        [string]$AgentDirectory = [IO.Path]::Combine($env:USERPROFILE, "VSTSAgents"),

        [parameter(Mandatory = $false)]
        [string]$Work,

        [parameter(Mandatory = $false)]
        [string]$Name = [System.Environment]::MachineName + "-$(Get-Random)",

        [parameter(Mandatory = $false)]
        [string]$Pool = 'Default',

        [parameter(Mandatory = $false)]
        [string]$DeploymentGroup = '',

        [parameter(Mandatory = $false)]
        [string]$DeploymentGroupTags = '',

        [parameter(Mandatory = $false)]
        [string]$Environment = '',

        [parameter(Mandatory = $false)]
        [string]$VirtualMachineResourceTags = '',

        [parameter(Mandatory = $false)]
        [string]$ProjectName = '',

        [parameter(Mandatory = $true)]
        [securestring]$PAT,

        [parameter(Mandatory = $true)]
        [uri]$ServerUrl,

        [parameter(Mandatory = $false)]
        [switch]$Replace,

        [parameter(Mandatory = $false)]
        [pscredential]$LogonCredential,

        [parameter(Mandatory = $false)]
        [string]$Cache = [io.Path]::Combine($env:USERPROFILE, ".vstsagents")
    )

    if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') {
        throw "Not Implemented: Support for $($PSVersionTable.Platform), contributions welcome."
    }

    if ( $Verbose ) { $VerbosePreference = 'Continue' }

    $existing = Get-VSTSAgent -AgentDirectory $AgentDirectory -NameFilter $Name
    if ( $existing ) { 
        if ($Replace) { 
            Uninstall-VSTSAgent -NameFilter $Name -AgentDirectory $AgentDirectory -PAT $PAT -ErrorAction Stop
        }
        else { throw "Agent $Name already exists in $AgentDirectory" }
    }

    $findArgs = @{ 'Platform' = 'win' }
    if ( $MinimumVersion ) { $findArgs['MinimumVersion'] = $MinimumVersion }
    if ( $MaximumVersion ) { $findArgs['MaximumVersion'] = $MaximumVersion }
    if ( $RequiredVersion ) { $findArgs['RequiredVersion'] = $RequiredVersion }

    $agent = Find-VSTSAgent @findArgs | Sort-Object -Descending -Property Version | Select-Object -First 1
    if ( -not $agent ) { throw "Could not find agent matching requirements." }

    Write-Verbose "Installing agent at $($agent.Uri)"

    $fileName = $agent.Uri.Segments[$agent.Uri.Segments.Length - 1]
    $destPath = [IO.Path]::Combine($Cache, "$($agent.Version)\$fileName")

    if ( -not (Test-Path $destPath) ) {

        $destDirectory = [io.path]::GetDirectoryName($destPath)
        if (!(Test-Path $destDirectory -PathType Container)) {
            New-Item "$destDirectory" -ItemType Directory | Out-Null
        }

        Write-Verbose "Downloading agent from $($agent.Uri)"
        try {  Start-BitsTransfer -Source $agent.Uri -Destination $destPath }
        catch { throw "Downloading $($agent.Uri) failed: $_" }
    }
    else { Write-Verbose "Skipping download as $destPath already exists." }

    $agentFolder = [io.path]::Combine($AgentDirectory, $Name)
    Write-Verbose "Unzipping $destPath to $agentFolder"

    if ( $PSVersionTable.PSVersion.Major -le 5 ) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    }

    [System.IO.Compression.ZipFile]::ExtractToDirectory($destPath, $agentFolder)

    $configPath = [io.path]::combine($agentFolder, 'config.cmd')
    $configPath = Get-ChildItem $configPath -ErrorAction SilentlyContinue
    if ( -not $configPath ) { throw "Agent $agentFolder is missing config.cmd" }

    [string[]]$configArgs = @('--unattended', '--url', "$ServerUrl", '--auth', `
            'pat', '--agent', "$Name", '--runAsService')

    if ($Pool) { $configArgs += '--pool', $Pool }

    if ($DeploymentGroup) { $configArgs += '--deploymentgroup', '--deploymentgroupname', $DeploymentGroup }
    if ($DeploymentGroupTags) { $configArgs += '--addDeploymentGroupTags', '--deploymentGroupTags', $DeploymentGroupTags }
    if ($Environment) { $configArgs += '--environment', '--environmentName', $Environment }
    if ($VirtualMachineResourceTags) { $configArgs += '--addvirtualmachineresourcetags', '--virtualmachineresourcetags', $VirtualMachineResourceTags }
    if ($ProjectName) { $configArgs += '--projectname', $ProjectName }

    if ( $Replace ) { $configArgs += '--replace' }
    if ( $LogonCredential ) { $configArgs += '--windowsLogonAccount', $LogonCredential.UserName }
    if ( $Work ) { $configArgs += '--work', $Work }

    if ( -not $PSCmdlet.ShouldProcess("$configPath $configArgs", "Start-Process") ) { return }

    $token = [System.Net.NetworkCredential]::new($null, $PAT).Password
    $configArgs += '--token', $token

    if ( $LogonCredential ) {
        $configArgs += '--windowsLogonPassword', `
            [System.Net.NetworkCredential]::new($null, $LogonCredential.Password).Password
    }

    $outFile = [io.path]::Combine($agentFolder, "out.log")
    $errorFile = [io.path]::Combine($agentFolder, "error.log")

    Write-Verbose "Registering $Name to $Pool at $ServerUrl"
    Start-Process $configPath -ArgumentList $configArgs -NoNewWindow -Wait `
        -RedirectStandardOutput $outFile -RedirectStandardError $errorFile -ErrorAction Stop

    if (Test-Path $errorFile) {
        Get-Content $errorFile  | Write-Error
    }
}

<#
.SYNOPSIS
    Uninstall agents.
.DESCRIPTION
    Uninstall any agents matching the specified criteria.
.PARAMETER MinimumVersion
    Minimum version of agents to uninstall.
.PARAMETER MaximumVersion
    Maximum version of agents to uninstall.
.PARAMETER RequiredVersion
    Required version of agents to uninstall.
.PARAMETER AgentDirectory
    What directory should be searched for existing agents?
.PARAMETER NameFilter
    Only agents whose names match this filter will be uninstalled.
.PARAMETER PAT
    The personal access token used to auth with VSTS.
#>
function Uninstall-VSTSAgent {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "NoVersion")]
    param(
        [parameter(Mandatory = $true, ParameterSetName = 'MinVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MinimumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'MaxVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MaximumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
        [VSTSAgentVersion]$RequiredVersion,

        [parameter(Mandatory = $false)]
        [string]$AgentDirectory,

        [parameter(Mandatory = $false)]
        [string]$NameFilter,

        [parameter(Mandatory = $true)]
        [securestring]$PAT
    )

    $getArgs = @{}
    $PSBoundParameters.Keys | Where-Object { $_ -ne 'PAT' } | ForEach-Object { 
        $getArgs[$_] = $PSBoundParameters[$_] 
    }

    $token = [System.Net.NetworkCredential]::new($null, $PAT).Password

    Get-VSTSAgent @getArgs | ForEach-Object {
        if ( -not $PSCmdlet.ShouldProcess("$($_.Name) - $($_.Path)", "Uninstall")) { return }

        $configPath = [io.path]::Combine($_.Path.LocalPath, 'config.cmd')
        $configArgs = @('remove', '--unattended', '--auth', 'pat', '--token', "$token")

        $outFile = [io.path]::Combine($_.Path.LocalPath, "out.log")
        $errorFile = [io.path]::Combine($_.Path.LocalPath, "error.log")

        Start-Process $configPath -ArgumentList $configArgs -NoNewWindow -Wait `
            -RedirectStandardOutput $outFile -RedirectStandardError $errorFile

        if ((Test-Path $errorFile) -and (Get-ChildItem $errorFile).Length -gt 0) {
            Get-Content $errorFile | Write-Error
            return; # Don't remove the agent folder if something went wrong.
        }

        Remove-Item $_.Path.LocalPath -Recurse -Force -ErrorAction Continue
        if ( $_.Work.IsAbsoluteUri ) {
            Remove-Item $_.Work.LocalPath -Recurse -Force -ErrorAction Continue
        }
    }
}

<#
.SYNOPSIS
    Get all the agents installed.
.PARAMETER MinimumVersion
    The minimum agent version to get.
.PARAMETER MaximumVersion
    The maximum agent version to get.
.PARAMETER RequiredVersion
    The required agent version to get.
.PARAMETER AgentDirectory
    What directory should be searched for installed agents?
.PARAMETER NameFilter
    Only agents whose names pass the filter are included.
#>
function Get-VSTSAgent {
    [CmdletBinding(DefaultParameterSetName = "NoVersion")]
    param(
        [parameter(Mandatory = $true, ParameterSetName = 'MinVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MinimumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'MaxVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MaximumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
        [VSTSAgentVersion]$RequiredVersion,

        [parameter(Mandatory = $false)]
        [string]$AgentDirectory = [io.Path]::Combine($env:USERPROFILE, "VSTSAgents"),

        [parameter(Mandatory = $false)]
        [string]$NameFilter = '*'
    )

    Get-ChildItem "$AgentDirectory\**\.agent" -Attributes '!D+H,!D' -ErrorAction SilentlyContinue  | 
        ForEach-Object {
        Write-Verbose "Found agent at $($_.FullName)"

        $agentFullDirectory = $_.Directory.FullName
        $agentFullPath = $_.FullName

        try {
            $agent = Get-Content $agentFullPath  | ConvertFrom-Json
            Write-Verbose "Agent is named $($agent.agentName)"
            if ( $NameFilter -and ($agent.agentName -notlike $NameFilter) ) { 
                Write-Verbose "Skipping agent because $($agent.agentName) is not like $NameFilter"
                return 
            }

            $configPath = [io.path]::combine($agentFullDirectory, 'config.cmd')
            $configPath = Get-ChildItem $configPath -ErrorAction SilentlyContinue
            if ( -not $configPath ) {
                Write-Warning "Agent $agentFullDirectory is missing config.cmd"
                return
            }

            $version = & $configPath --version

            if ( $RequiredVersion -and $version -ne $RequiredVersion) { 
                Write-Verbose "Skipping agent because $version not match $RequiredVersion"
                return
            }
            if ( $MinimumVersion -and $version -lt $MinimumVersion) { 
                Write-Verbose "Skipping agent because $version is less than $MinimumVersion"
                return 
            }
            if ( $MaximumVersion -and $version -gt $MaximumVersion) {
                Write-Verbose "Skipping agent because $version is greater than $MaximumVersion"
                return
            }
        
            if ( Test-Path "$($_.Directory.FullName)\.service" ) {
                $serviceName = Get-Content "$($_.Directory.FullName)\.service"
                $service = Get-Service $serviceName
            }

            [pscustomobject]@{
                'Id'        = $agent.agentId
                'Name'      = $agent.agentName
                'PoolId'    = $agent.poolId
                'ServerUrl' = [uri]$agent.serverUrl
                'Work'      = [uri]$agent.workFolder
                'Service'   = $service
                'Version'   = $version
                'Path'      = [uri]$agentFullDirectory
            }
        }
        catch { Write-Error "Exception processing agent at $agentFullPath\: $_" }
    }
}


<#
.SYNOPSIS
    Starts any stopped services for matching VSTS Agents
.PARAMETER MinimumVersion
    Mimumum version for agents.
.PARAMETER MaximumVersion
    Maximum version for agents.
.PARAMETER RequiredVersion
    Required version for agents.
.PARAMETER AgentDirectory
    Directory to search installed agents.
.PARAMETER NameFilter
    Only start services for agents whose names pass this filter.
#>
function Start-VSTSAgent {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "NoVersion")]
    param(
        [parameter(Mandatory = $true, ParameterSetName = 'MinVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MinimumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'MaxVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MaximumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
        [VSTSAgentVersion]$RequiredVersion,

        [parameter(Mandatory = $false)]
        [string]$AgentDirectory,

        [parameter(Mandatory = $false)]
        [string]$NameFilter
    )

    $stoppedAgents = Get-VSTSAgent @PSBoundParameters | Where-Object { 
        $_.Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped 
    }

    $stoppedAgents | ForEach-Object {
        if ( $PSCmdlet.ShouldProcess($_.Service.Name, "Start-Service") ) {
            Start-Service $_.Service
        }
    }
}

<#
.SYNOPSIS
    Stop any running services for agents.
.PARAMETER MinimumVersion
    Mimumum version for agents.
.PARAMETER MaximumVersion
    Maximum version for agents.
.PARAMETER RequiredVersion
    Required version for agents.
.PARAMETER AgentDirectory
    Directory to search installed agents.
.PARAMETER NameFilter
    Only start services for agents whose names pass this filter.
#>
function Stop-VSTSAgent {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "NoVersion")]
    param(
        [parameter(Mandatory = $true, ParameterSetName = 'MinVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MinimumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'MaxVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'MinMaxVersion')]
        [VSTSAgentVersion]$MaximumVersion,

        [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
        [VSTSAgentVersion]$RequiredVersion,

        [parameter(Mandatory = $false)]
        [string]$AgentDirectory,

        [parameter(Mandatory = $false)]
        [string]$NameFilter
    )
    
    $runningAgents = Get-VSTSAgent @PSBoundParameters | Where-Object { 
        $_.Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running 
    }

    $runningAgents | ForEach-Object {
        if ( $PSCmdlet.ShouldProcess($_.Service.Name, "Stop-Service") ) {
            Stop-Service $_.Service
        }
    }
}
