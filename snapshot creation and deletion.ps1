[CmdletBinding()]

param(
    [Parameter(Mandatory = $true, Position = 0)][object] $scriptParams
)

Try 
{ 
	"Inside VM Snapshot Creation Script"
    $Downtime=$scriptParams.downtime          <#"11/17/2022 17:10:00"#>
    $Deployment = $scriptParams.deploymentName               
    $DeploymentName = "Automation-Job-"+$Deployment
	$genReRITM= $scriptParams.' RITM'  
	$genReRITM
## logic start####
    $VMName = $scriptParams.virtualMachineName
	#$VMName=$VMName.ToLower()
    $ipaddress= $scriptParams.IpAddress
    $kqlQuery1 = "resources | where type =~ 'microsoft.compute/virtualmachines' |where name == '$VMName' | extend nics=array_length(properties.networkProfile.networkInterfaces) | mv-expand nic=properties.networkProfile.networkInterfaces | where nics == 1 or nic.properties.primary =~ 'true' or isempty(nic) | project subid = subscriptionId, vmName = name,ResourceGroup = resourceGroup, vmSize=tostring(properties.hardwareProfile.vmSize), nicId = tostring(nic.id) | join kind=leftouter ( resources | where type =~ 'microsoft.network/networkinterfaces' | extend ipConfigsCount=array_length(properties.ipConfigurations) | mv-expand ipconfig=properties.ipConfigurations | where ipConfigsCount == 1 or ipconfig.properties.primary =~ 'true' | project nicId = id, privateIpId = tostring(ipconfig.properties.privateIPAddress)) on nicId |where privateIpId == '$ipaddress' | project-away nicId1"
    $result = Search-AzGraph -query $kqlQuery1
    $RGSubscription= $result.subid
    $RGSubscription
    $VMName=$result.vmName
    $VMName
    $ResourceGroupName=$result.ResourceGroup
    $ResourceGroupName

$Subscription=$RGSubscription
    write-output " Subscription is: $Subscription"
   Set-AzContext -Subscription $Subscription
   $date=get-date -Format "ddMMyyyy"
# create snapshot

$vm= Get-AzVm -ResourceGroupName $ResourceGroupName -Name $VMName
$rsgname=$vm.ResourceGroupName
$vmname=$vm.Name
$tagvalue= @{"Genre RITM"=$genReRITM;"Deletion date"=$Downtime}
write-output "VM Name: $vmname"
write-output "Resource group: $rsgname"
#create os disk snapshot name
$OsSnapshotName= $vmname+"-SNAPSHOT-OnDemandBKP"+"OSDisk"
# $disktype=$vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
$disktype= "Standard_LRS"
write-output "OS Disk Type: $disktyp"
$source = $vm.StorageProfile.OsDisk.ManagedDisk.Id
write-output " SourceUri : $source"
$SnapshotName =@()
#create a snapshot config with the managed disk from the VM OS disk
$disktype
Write-output "Snapshot Name $OsSnapshotName"
$osDiskSnapshot= New-AzSnapshotConfig -SourceUri $source -Location $vm.Location -CreateOption copy -SkuName $disktype -Tag $tagvalue

## create the actual snapshot of the os disk
$osDiskSnapshot
$snapshotcreationrg= Get-azResourceGroup | where {$_.ResourceGroupName -like "*-OndemandBKP-RG001"}
$snapshotcreationrgname=$snapshotcreationrg.ResourceGroupName
$Snapshot=New-AzSnapshot -Snapshot $OsDiskSnapshot -ResourceGroupName $snapshotcreationrgname -SnapshotName $OsSnapshotName
$Snapshot
Start-sleep 30
$snaps=Get-AzSnapshot -ResourceGroupName $snapshotcreationrgname -Name $OsSnapshotName
Write-output "Snap check " $snaps
$SnapshotName+= $OsSnapshotName
#for data disk

$diskdetails= $vm.StorageProfile.DataDisks.Name -join ","
foreach($datadisk in $diskdetails.Split(",")){
$DataSnapshotName = $vmname+"-SNAPSHOT-OnDemandBKP"+$datadisk
$datadiskdetailss= Get-azdisk -ResourceGroupName $rsgname -DiskName $datadisk
$dsource=$datadiskdetailss.Id

# $datadisktype=$datadiskdetailss.Sku.Name
$datadisktype = "Standard_LRS"
$DataDiskSnapshot= New-AzSnapshotConfig -SourceUri $dsource -Location $vm.Location -CreateOption copy -SkuName $datadisktype -Tag $tagvalue
$Snapshot=New-AzSnapshot -Snapshot $DataDiskSnapshot -ResourceGroupName $snapshotcreationrgname -SnapshotName $DataSnapshotName
Start-sleep 30
$snaps=Get-AzSnapshot -ResourceGroupName $snapshotcreationrgname -Name $DataSnapshotName
$SnapshotName+=$DataSnapshotName
}



#Creating Schedule to delte the Snapshot
select-azsubscription -Subscription '' 

foreach($SnapshotNames in $SnapshotName){

$currentdate= get-date -Format "dd-MM-yyyy"
# $deletiondate= (get-date).AddDays(3).AddHours(-6) -f 'dd-mm-yyyy'
 $deletiondate= $Downtime   

$AutomationAccountName = ""
$RunbookName = "VMSnap-deletion"
$AutomationRGName = ""

$ScheduleName = "VMSnapshotDelete"+ "$SnapshotNames"
# Set params and schedule deletion  
$RemovalTime = $deletiondate

# Set params and schedule stop action
$params = @{}
$sParams = @{'virtualMachineName' = $vmname;'ResourceGroupName' = $snapshotcreationrgname;'deploymentName' = $Deployment; 'subscription' = $RGSubscription; 'OsSnapshotName' = $SnapshotNames}
$params.Add('runbookParams',$sParams)
$TimeZone = ([System.TimeZoneInfo]::Local).Id
$TimeZone
try
{
		Select-AzSubscription -SubscriptionId ""
		$runset=New-AzAutomationSchedule -AutomationAccountName $AutomationAccountName `
		-Name $ScheduleName `
		-StartTime $RemovalTime `
		-oneTime `
		-ResourceGroupName $AutomationRGName `
		-TimeZone $TimeZone `
		-ErrorVariable stopSchedError -ErrorAction SilentlyContinue
		$runset
         Write-Output "Schedule new "
		$regset=Register-AzAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName `
		-Name $RunbookName `
		-ScheduleName $ScheduleName `
		-ResourceGroupName $AutomationRGName `
		-Parameters $params `
		-ErrorVariable linkStopSchedError -ErrorAction Stop
	$output = "Snapshot Created for both OS and Datadisk . Deletion of Snapshot is being scheduled on $RemovalTime"
	}
	catch
    {
		Write-Error -Message $_.Exception
		throw $_.Exception
	}
}

	# Print the deployment result
	Write-Output  @{
	"DeploymentName"    = "Automation-Job-"+$deploymentName
	"Outputs"           = $output
	"Provisioningstate" = "Succeeded"
	}
}
Catch {
    <#-------------------------------[ ERROR HANDLING ]-----------------------------------------#>
    
      # Write-Output "Error Occurred in scheduling runbook Script:"
         Write-Output  $_ 

      # Print the error result
        Write-Output  @{
        "DeploymentName"    = "Automation-Job-"+$deploymentName
        "Outputs"           = $_.Exception.Message
        "Provisioningstate" = "Failed"
        }
    }
