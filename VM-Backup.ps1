[CmdletBinding()]

param(
    [Parameter(Mandatory = $true, Position = 0)][object] $scriptParams
)

try{

  $RequestNumber = $scriptParams.deploymentName
  $deploymentName = "automation-job-"+$RequestNumber
  $Subscription = $scriptParams.Resource_Subscription
  $ComputerName = $scriptParams.VirtualMachineName
	Write-Output "Hi i am VM Name" $ComputerName
  $RecoveryServicesVault= $scriptParams.RecoveryServicesVault
  $BackupProtectionPolicy=$scriptParams.BackupProtectionPolicy
	$ResourceGroup =  $scriptParams.ResourceGroup
 if ($ResourceGroup -eq $null) {
## logic start####
    $VMName = $scriptParams.virtualMachineName
	#$VMName=$VMName.ToLower()
    $ipaddress= $scriptParams.IpAddress
    $kqlQuery1 = "resources | where type =~ 'microsoft.compute/virtualmachines' |where name == '$VMName' | extend nics=array_length(properties.networkProfile.networkInterfaces) | mv-expand nic=properties.networkProfile.networkInterfaces | where nics == 1 or nic.properties.primary =~ 'true' or isempty(nic) | project subid = subscriptionId, vmName = name,ResourceGroup = resourceGroup, vmSize=tostring(properties.hardwareProfile.vmSize), nicId = tostring(nic.id) | join kind=leftouter ( resources | where type =~ 'microsoft.network/networkinterfaces' | extend ipConfigsCount=array_length(properties.ipConfigurations) | mv-expand ipconfig=properties.ipConfigurations | where ipConfigsCount == 1 or ipconfig.properties.primary =~ 'true' | project nicId = id, privateIpId = tostring(ipconfig.properties.privateIPAddress)) on nicId |where privateIpId == '$ipaddress' | project-away nicId1"
    $result = Search-AzGraph -query $kqlQuery1
    $Subscription= $result.subid
    $Subscription
    $ComputerName=$result.vmName
    $ComputerName
    $ResourceGroup=$result.ResourceGroup
    $ResourceGroup
 }

		$query ="recoveryservicesresources | where type == 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' | where properties['workloadType'] == 'VM'|extend protectionState = properties.protectionState |extend  dataSourceId= properties.dataSourceId |extend  policyId= properties.policyId |extend friendlyname = properties.friendlyName |extend lastRecoveryPoint = properties.lastRecoveryPoint |extend protectedPrimaryRegion= properties.protectedPrimaryRegion | where friendlyname =~ '$ComputerName' |project id, protectionState"
		$query
		$result = Search-AzGraph -query $query
		$result
		 $resourceid=$result.id
		 $protection= $result.protectionState
 		$protection
  Select-azSubscription -subscriptionId $Subscription
  $RSV=Get-AzRecoveryServicesVault -Name $RecoveryServicesVault
  if($RSV)
    {
	    Write-output("Recovery service Vault found : $($RSV.name)")
			$RSV | Set-AzRecoveryServicesVaultContext
    }
    else
    {
        Throw("Recovery service Vault $RecoveryServicesVault Not found")
        ###Code to create a new Recovery service vault###
        # New-AzRecoveryServicesVault -ResourceGroupName $ResourceGroup -Name $RecoveryServicesVault -Location $Location
        # $RSV=Get-AzRecoveryServicesVault -Name $RecoveryServicesVault
        # $RSV | Set-AzRecoveryServicesVaultContext
        # $RSV | Set-AzRecoveryServicesBackupProperty -BackupStorageRedundancy $BackupStorageRedundancy

    }
    # #### Code to check backup is enabled or not ####
    # $vault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroup -Name $RSV
    # $vid = $RSV.id
		# Write-Output " Hi I am vid $vid"
    # # $Container = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -FriendlyName $ComputerName -VaultId $vid
    # # Write-Output "Hi I am container $Container"
		# # $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType "AzureVM " -VaultId $vid
    # # Write-Output " Hi I am Backup Item " $BackupItem 
		 

    if($BackupProtectionPolicy)
    {
        $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $BackupProtectionPolicy
				Write-output "Hi I am Policy " $policy
    }
    else
    {
        $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name "DefaultPolicy"
				Write-output "Hi I am Policy " $policy
    }

  if($resourceid -ne $null -or $protection -eq "ProtectionStopped")
    {
			# Select-AzSubscription -Subscription $Subscription
			$RSV=Get-AzRecoveryServicesVault -Name $RecoveryServicesVault
			$RSV
			$RSV | Set-AzRecoveryServicesVaultContext
			$backupcontainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -FriendlyName $ComputerName
			$item = Get-AzRecoveryServicesBackupItem -Container $backupcontainer -WorkloadType "AzureVM"
			$policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $BackupProtectionPolicy
			$vaultid=$RSV.Id
			$vaultid
			Enable-AzRecoveryServicesBackupProtection -Item $item -Policy $policy -VaultId $vaultid
			$output= "Backup Enabled Successfully"
		}
  elseif($resourceid -eq $null)
    {
        $output= Enable-AzRecoveryServicesBackupProtection -ResourceGroupName $ResourceGroup -Name $ComputerName -Policy $policy
				Write-output "Hi I am Output " $output
				$output= "Backup Enabled Successfully"
##### Code to enable first backup ######
    # $backupcontainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -FriendlyName $ComputerName
		# Write-Output " Hi i am backupcontainer $backupcontainer"
    # $item = Get-AzRecoveryServicesBackupItem -Container $backupcontainer -WorkloadType "AzureVM"
		# Write-Output "Hi I am item $item "
    # $firstbackup =Backup-AzRecoveryServicesBackupItem -Item $item
		# Write-output "Hi I am first backup " $firstbackup
    # $backupstatus = Get-AzRecoveryservicesBackupJob
		# Write-output "Hi I am backup status " $backupstatus
		}
  else
    {
      Write-Output "Backup is already enabled for $ComputerName "
			$output= "Backup is already enabled for $ComputerName "
    }



    Write-Output @{
    "DeploymentName" = $deploymentName
    "Outputs" = $output
    "Provisioningstate" = "Succeeded"
    }
}
catch{
    Write-Output "Error Occurred in Windows VM Backup Script:"
    Write-Output $_
    Write-Output @{
        "DeploymentName" = $deploymentName
        "Outputs" = $_.Exception.Message
        "Provisioningstate" = "Failed"
    }
    Throw $_
}