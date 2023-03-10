# param(
#     [Parameter()]
#     [string]$backupLocation,
#     [Parameter()]
#     [string]$backupContainer
# )
$backupLocation = "Storage"
$backupContainer = "Container"
$automationAccount = "auto01"
$method = "SA"
$resourceGroup = "Temp"

# Set the remote execution policy with the Set-ExecutionPolicy cmdlet.
Set-ExecutionPolicy RemoteSigned -Force;

# Install the latest NuGet package provider using the Install-PackageProvider cmdlet.
Install-PackageProvider -Name NuGet -Force;

# Allow the PowerShell gallery repository to be trusted with the Set-PSRepository cmdlet.
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted;

# Install the latest PowerShellGet module using the Install-Module cmdlet.
Install-Module -Name PowerShellGet -Force;

# Install the Azure PowerShell (Az) module using the Install-Module cmdlet.
Install-Module -Name Az -Force -AllowClobber;




# Ensures you do not inherit an AzContext in your runbook
Write-Host "Clearing Context"
Disable-AzContextAutosave -Scope Process | Out-Null

# Connect using a Managed Service Identity
Write-Host "Creating Context"
try {
        $AzureContext = (Connect-AzAccount -Identity).context
    }
catch{
        Write-Output "There is no system-assigned user identity. Aborting."; 
        exit
    }

# set and store context
Write-Host "Storing Context"
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription `
    -DefaultProfile $AzureContext

if ($method -eq "SA")
    {
        Write-Output "Using system-assigned managed identity"
    }
elseif ($method -eq "UA")
    {
        Write-Output "Using user-assigned managed identity"

        # Connects using the Managed Service Identity of the named user-assigned managed identity
        $identity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroup `
            -Name $UAMI -DefaultProfile $AzureContext

        # validates assignment only, not perms
        if ((Get-AzAutomationAccount -ResourceGroupName $resourceGroup `
                -Name $automationAccount `
                -DefaultProfile $AzureContext).Identity.UserAssignedIdentities.Values.PrincipalId.Contains($identity.PrincipalId))
            {
                $AzureContext = (Connect-AzAccount -Identity -AccountId $identity.ClientId).context

                # set and store context
                $AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext
            }
        else {
                Write-Output "Invalid or unassigned user-assigned managed identity"
                exit
            }
    }
else {
        Write-Output "Invalid method. Choose UA or SA."
        exit
     }

Write-Host "Tagging"
$tags = @{BackupLocation=$backupLocation;BackupContainer=$backupContainer}
$vaults = Get-AzKeyVault
foreach ($vault in $vaults){
Update-AzTag -ResourceId $vault.resourceid -Tag $tags -Operation Merge
$tags = @{BackupLocation=$backupLocation;BackupContainer=$backupContainer}
}   
