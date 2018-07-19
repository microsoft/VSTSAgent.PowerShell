# VSTS Agent Powershell Module

Tools for managing and automating your Visual Studio Team Services Agents.

## Builds

### Master
[![Build status](https://ci.appveyor.com/api/projects/status/pnw34lbpygqyttb9/branch/master?svg=true)](https://ci.appveyor.com/project/jwittner/vstsagent-powershell/branch/master)

The `master` branch is automatically built and deployed to the [PowerShell Gallery](https://www.powershellgallery.com/packages/VSTSAgent).

### Develop
[![Build status](https://ci.appveyor.com/api/projects/status/pnw34lbpygqyttb9/branch/develop?svg=true)](https://ci.appveyor.com/project/jwittner/vstsagent-powershell/branch/develop)

The `develop` branch is automatically built and deployed as a prerelease module to the [PowerShell Gallery](https://www.powershellgallery.com/packages/VSTSAgent).

## Installation

```powershell
Install-Module VSTSAgent -Scope CurrentUser
```

## Using

### Cmdlets
Get all of your installed VSTS Agents:

```powershell
Get-VSTSAgent | Format-Table -AutoSize

# Sample Output
# Id Name    PoolId ServerUrl                          Work                             Service                    Version Path
# -- ----    ------ ---------                          ----                             -------                    ------- ----
# 54 Agent01      1 https://account.visualstudio.com/  file:///D:/VSTSAgentWork/Agent01 vstsagent.account.Agent01  2.138.0 file:///C:/VSTSAgents/Agent01
```

Install the latest VSTS Agent:

```powershell
$pat = Read-Host -AsSecureString
Install-VSTSAgent -ServerUrl 'https://account.visualstudio.com' -PAT $pat -Name 'Agent01'
```

Uninstall any VSTS Agents:

```powershell
Uninstall-VSTSAgent
```

Find available VSTS Agents for installation:

```powershell
Find-VSTSAgent
```

Start and Stop installed Agents:
```powershell
Stop-VSTSAgent
Start-VSTSAgent
```

### DSC
VSTSAgent includes the xVSTSAgent DSC Resource. An example configuration might look like:

```powershell   
Configuration Sample_xVSTSAgent_Install {
    param 
    (   
        [parameter(Mandatory = $true)] 
        [PSCredential]$AccountCredential
    )
    Import-DscResource -ModuleName VSTSAgent

    Node 'localhost' {

        xVSTSAgent VSTSAgent {
            Name              = 'Agent01'
            ServerUrl         = 'https://account.visualstudio.com'
            AccountCredential = $AccountCredential
            AgentDirectory    = 'C:\VSTSAgents'
            Work              = 'D:\VSTSAgentsWork\Agent01'
            Ensure            = 'Present'
        }
    }
}

```

# Feedback
To file issues or suggestions, please use the [Issues](https://github.com/Microsoft/unitysetup.powershell/issues) page for this project on GitHub.


# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Reporting Security Issues

Security issues and bugs should be reported privately, via email, to the Microsoft Security Response Center (MSRC) at [secure@microsoft.com](mailto:secure@microsoft.com). You should receive a response within 24 hours. If for some reason you do not, please follow up via email to ensure we received your original message. Further information, including the [MSRC PGP](https://technet.microsoft.com/en-us/security/dn606155) key, can be found in the [Security TechCenter](https://technet.microsoft.com/en-us/security/default).