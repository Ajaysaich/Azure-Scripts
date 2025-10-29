[CmdletBinding()]

param(
    [Parameter(Mandatory = $true, Position = 0)][object] $scriptParams
)

##### Function to start stop VM Starts#########
function StartStopVirtualMachine {
  param (
    [Parameter(Mandatory = $true)][string] $VmName,
    [Parameter(Mandatory = $true)][string] $RgName,
    [Parameter(Mandatory = $true)][String] $Action
  )
  try{
    $vmState = Get-AzVM -ResourceGroupName $RgName -vmname $VmName -Status

    $count = 0
    $retrycount = 10
    $finished = $false

    Switch ($Action) {
      'START' {

        # Start VM
        if (($vmState.statuses[1]).displaystatus -notmatch 'running') {
          #Write-Output "Starting the virtual machine '$VmName'..."
          $null = Start-AzVm -ResourceGroupName $RgName -Name $VmName

          #Write-Output "Check VM power state till it is in 'Running' state..."
          Start-Sleep -Seconds 10

          # Check VM running status
          do {
            $count++
            $vmState = Get-AzVM -ResourceGroupName $RgName -VMName $VmName -Status
      #Write-Output("Current VM Status: $(($vmState.statuses[1]).displaystatus)")
            if (($vmState.statuses[1]).displaystatus -match 'running') {
              $finished = $true
            }
            else {
              #Write-Output "VM power state is not in 'Running' state, retrying [$count/$retryCount]..."
              Start-Sleep -Seconds 10
            }

            if ($count -ge $retryCount) {
              $finished = $true
              $errorMessage = "Unable to start the VM $($VmName)"
              throw $errorMessage
            }
          } until ($finished)
        }
      }

      'STOP' {

        # Stop VM
        if (($vmState.statuses[1]).displaystatus -notmatch 'deallocated') {
          #Write-Output "Stopping the virtual machine '$VmName'..."
          $null = Stop-AzVm -ResourceGroupName $RgName -Name $VmName -force

          #Write-Output "Check VM power state till it is in 'Deallocated' state..."
          Start-Sleep -Seconds 10

          # check VM running status
          do {
            $count++
            $vmState = Get-AzVM -ResourceGroupName $RgName -VMName $VmName -Status
     # Write-Output("Current VM Status: $(($vmState.statuses[1]).displaystatus)")
            if ($(($vmState.statuses[1]).displaystatus) -match 'deallocated') {
              $finished = $true
            }
            else {
              #Write-Output "VM power state is not in 'Deallocated' state, retrying [$count/$retryCount]..."
              Start-Sleep -Seconds 10
            }

            if ($count -ge $retryCount) {
              $finished = $true
              $errorMessage = "Unable to stop the VM $($VmName)"
              throw $errorMessage
            }
          } until ($finished)
        }
      }
    }
  } catch {
    #write-Output "Unable to successfully complete start and stop of VM $_"
    throw "Unable to successfully complete start and stop of VM $_"
  }
}
##### Function to start stop VM Ends#########
try{

    $resourceGroup = $scriptParams.resourceGroupName
    #$vmName = $scriptParams.virtualMachineName
    $newSize = $scriptParams.newVmSize
    #$subscription= $scriptParams.Resource_Subscription
    $TaskNumber = $scriptParams.deploymentName
    $deploymentName = "automation-job-"+$TaskNumber
    
				## logic start####
    $vmName= $scriptParams.virtualMachineName
		#$vmName=$VMName.ToLower()
    $ipaddress= $scriptParams.IpAddress
    $kqlQuery1 = "resources | where type =~ 'microsoft.compute/virtualmachines' |where name == '$vmName' | extend nics=array_length(properties.networkProfile.networkInterfaces) | mv-expand nic=properties.networkProfile.networkInterfaces | where nics == 1 or nic.properties.primary =~ 'true' or isempty(nic) | project subid = subscriptionId, vmName = name,ResourceGroup = resourceGroup, vmSize=tostring(properties.hardwareProfile.vmSize), nicId = tostring(nic.id) | join kind=leftouter ( resources | where type =~ 'microsoft.network/networkinterfaces' | extend ipConfigsCount=array_length(properties.ipConfigurations) | mv-expand ipconfig=properties.ipConfigurations | where ipConfigsCount == 1 or ipconfig.properties.primary =~ 'true' | project nicId = id, privateIpId = tostring(ipconfig.properties.privateIPAddress)) on nicId |where privateIpId == '$ipaddress' | project-away nicId1"
    $result = Search-AzGraph -query $kqlQuery1
    $subscription= $result.subid
    $vmName=$result.vmName
    $resourceGroup=$result.ResourceGroup
		 

## logic End####
  
	# Write-Output "Login to Azure using Managed Identity"
	# $null = Disable-AzContextAutosave -Scope Process	# Ensures you do not inherit an AzContext in your runbook
  #   $AzureContext = (Connect-AzAccount -Identity -AccountId "").context	# Connect to Azure with user-assigned managed identity
  #   $null = Set-AzContext -Subscription $subscription -DefaultProfile $AzureContext
	$null = select-azsubscription -subscriptionid $subscription
    $vm = Get-AzVM -ResourceGroupName $resourceGroup -VMName $vmName
    if($null -ne $vm){
        # Stopping VM
        StartStopVirtualMachine -vmName $vmName -rgName $resourceGroup -action "STOP"

        # Updating VM Size
        $vm.HardwareProfile.VmSize = $newSize
        #Write-Output "Updating new Vmsize"
        $null= Update-AzVM -VM $vm -ResourceGroupName $resourceGroup
        Start-Sleep -Seconds 10

        $count = 0
        $retrycount = 5
        $finished = $false
        #Checking if VM Resized or not
        do {
            $count++
            $vmSize = (Get-AzVM -ResourceGroupName $resourceGroup -VMName $vmName).hardwareprofile.VmSize

            if ($vmSize -eq $newSize) {
                $finished = $true
            }
            else {
                #Write-Output "VM has not been resized, waiting 10s [$count/$retryCount]..."
                Start-Sleep -Seconds 10
            }

            if ($count -ge $retryCount) {
                $finished = $true
                $errorMessage = "Unable to Resize VM $($VmName)"
                throw $errorMessage
            }
         } until ($finished)

        # Starting VM
        StartStopVirtualMachine -vmName $vmName -rgName $resourceGroup -action "START"
      Write-Output @{
            "DeploymentName" = $deploymentName
            "Outputs" = "Server - $vmName resized to $newSize"
            "Provisioningstate" = "Succeeded"
        }
    }

}
catch{
 Write-Output @{
        "DeploymentName" = $deploymentName
        "Outputs" = $_.Exception.Message
        "Provisioningstate" = "Failed"
    }
    #Throw $_
}