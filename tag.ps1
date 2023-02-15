param(
    [Parameter()]
    [string]$backupLocation,
    [Parameter()]
    [string]$backupContainer
)

$tags = @{BackupLocation=$backupLocation;BackupContainer=$backupContainer}
$vaults = Get-AzKeyVault
foreach ($vault in $vaults){
Update-AzTag -ResourceId $vault.resourceid -Tag $tags -Operation Merge
$tags = @{BackupLocation=$backupLocation;BackupContainer=$backupContainer}
}   