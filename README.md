# VSTS Agent Powershell Module

Tools for managing and automating your Visual Studio Team Services Agents.

## Builds

The `master` branch is manually built and deployed to the [PowerShell Gallery]().

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
# Name    Version Account   Status  Uri
# ----    ------- -------   ------  ---
# Agent01 2.133.3 MyAccount Running file:///C:/Users/me/VSTSAgents/Agent01/
# Agent02 2.133.3 MyAccount Running file:///C:/Users/me/VSTSAgents/Agent01/
```

Install the latest VSTS Agent:

```powershell
$pat = Read-Host -AsSecureString
Install-VSTSAgent -Account 'MyAccount' -PAT $pat -Name 'Agent01'
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
            Account           = 'MyAccount'
            AccountCredential = $AccountCredential
            AgentDirectory    = 'C:\VSTSAgents'
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