$resourceGroupName = "Temp2"
$storageAccountName = "rgkvbackup0012"
$containerName = "backup"
$automationAccount = "auto01"
$method = "SA"
$blobEndpoint = "https://rgkvbackup0012.blob.core.windows.net"
$backupFolder = "~\KeyVaultBackup"


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

function backup-keyVaultItems($keyvaultName) {
    #######Parameters
    #######Setup backup directory
    If ((test-path $backupFolder)) {
        Remove-Item $backupFolder -Recurse -Force

    }
    ####### Backup items
    New-Item -ItemType Directory -Force -Path "$($backupFolder)\$($keyvaultName)" | Out-Null
    #Write-Output "Starting backup of KeyVault to a local directory."
    Write-Host "Starting backup of KeyVault to a local directory."
    ###Certificates
    $certificates = Get-AzKeyVaultCertificate -VaultName $keyvaultName 
    foreach ($cert in $certificates) {
        Backup-AzKeyVaultCertificate -Name $cert.name -VaultName $keyvaultName -OutputFile "$backupFolder\$keyvaultName\certificate-$($cert.name)" | Out-Null
    }
    ###Secrets
    $secrets = Get-AzKeyVaultSecret -VaultName $keyvaultName
    foreach ($secret in $secrets) {
        #Exclude any secrets automatically generated when creating a cert, as these cannot be backed up   
        if (! ($certificates.Name -contains $secret.name)) {
            Backup-AzKeyVaultSecret -Name $secret.name -VaultName $keyvaultName -OutputFile "$backupFolder\$keyvaultName\secret-$($secret.name)" | Out-Null
        }
    }
    
    #keys
    $keys = Get-AzKeyVaultKey -VaultName $keyvaultName
    foreach ($kvkey in $keys) {
        #Exclude any keys automatically generated when creating a cert, as these cannot be backed up   
        if (! ($certificates.Name -contains $kvkey.name)) {
            Backup-AzKeyVaultKey -Name $kvkey.name -VaultName $keyvaultName -OutputFile "$backupFolder\$keyvaultName\key-$($kvkey.name)" | Out-Null
        }
    }
}

$keyvaults = Get-AzKeyVault 
    if ($keyvaults) {
        if ($null -eq (get-AzResourceGroup $resourceGroupName -ErrorAction SilentlyContinue)) {
            New-AzResourceGroup $resourceGroupName
        }
        Set-AzCurrentStorageAccount -ResourceGroupName $resourceGroupName -AccountName $storageAccountName
        #New-AzStorageContext -ConnectionString $connectionString
        $storageKey1 = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName | Where-Object {$_.KeyName -eq "key1"}
        Write-Host $storageKey1.Value
        $connectionString = 'DefaultEndpointsProtocol=https;AccountName=' + $storageAccountName + ';AccountKey=' + $storageKey1.Value
        Write-Host $connectionString
        #$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
        $storageContext = New-AzStorageContext -ConnectionString $connectionString
        foreach ($keyvault in $keyvaults) {
            backup-keyVaultItems -keyvaultName $keyvault.VaultName
            foreach ($file in (get-childitem "$($backupFolder)\$($keyvault.VaultName)")) {
                #Set-AzStorageBlobContent -File $file.FullName -Container $containerName -Blob $file.name -Context $storageAccountName.context -Force
                Set-AzStorageBlobContent -BlobEndpoint $blobEndpoint -File $file.FullName -Container $containerName -Blob $file.name -Context $storageContext -Force
                #Set-AzStorageBlobContent -File $file.FullName -Container $containerName -Blob $file.name -Context $storageContext -UseConnectedAccount -Force
            }
         }
    }
