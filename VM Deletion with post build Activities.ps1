<#
    Description: Delete VM
    Version: 1.0
    Product: Cloud Exponence
    Modules Required: Az.Compute,Az.Network,Az.Storage,Az.Resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][object]$scriptParams
)

function Remove-AzrVirtualMachine {
    param
    (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [string]$VMName,
		
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [switch]$Wait

    )
    process {
        $scriptBlock = {
            param ($VMName,
                $ResourceGroupName)
            $commonParams = @{
                'Name'              = $VMName;
                'ResourceGroupName' = $ResourceGroupName
            }            
            $vm = Get-AzVm @commonParams


            Write-Output 'Removing the Azure VM...'
            $null = $vm | Remove-AzVM -Force
            Write-Output 'Removing the Azure network interface...'
            foreach ($nicUri in $vm.NetworkProfile.NetworkInterfaces.Id) {
                $nic = Get-AzNetworkInterface -ResourceGroupName $vm.ResourceGroupName -Name $nicUri.Split('/')[-1]
                if($nic -ne $null)
                {
                Remove-AzNetworkInterface -Name $nic.Name -ResourceGroupName $vm.ResourceGroupName -Force
                Write-Output "$($nic.Name) is deleted"
                foreach ($ipConfig in $nic.IpConfigurations) {
                    if ($ipConfig.PublicIpAddress -ne $null) {
                        Write-Output 'Removing the Public IP Address...'
                        Remove-AzPublicIpAddress -ResourceGroupName $vm.ResourceGroupName -Name $ipConfig.PublicIpAddress.Id.Split('/')[-1] -Force
                        Write-Output "Public IP Address is removed"
                    } 
                }
                }
                else
                {
                    Write-Output '$($nic.Name) not found'
                }
			}


            ## Remove the OS disk
            Write-Output 'Removing OS disk...'
            if ('Uri' -in $vm.StorageProfile.OSDisk.Vhd) {
                ## Not managed
                $osDiskId = $vm.StorageProfile.OSDisk.Vhd.Uri
                $osDiskContainerName = $osDiskId.Split('/')[-2]

                ## TODO: Does not account for resouce group 
                $osDiskStorageAcct = Get-AzStorageAccount | where { $_.StorageAccountName -eq $osDiskId.Split('/')[2].Split('.')[0] }
                $osDiskStorageAcct | Remove-AzStorageBlob -Container $osDiskContainerName -Blob $osDiskId.Split('/')[-1]

                #region Remove the status blob
                Write-Output 'Removing the OS disk status blob...'
                $osDiskStorageAcct | Get-AzStorageBlob -Container $osDiskContainerName -Blob "$($vm.Name)*.status" | Remove-AzStorageBlob
                #endregion
            }
            else {
                ## managed
                $diskID = $VM.StorageProfile.OsDisk.ManagedDisk.Id
                Remove-AzResource -ResourceId $diskID -Force
                write-output "$($VM.StorageProfile.OsDisk.Name) is deleted"
            }

            ## Remove any other attached disks
            if (($vm.StorageProfile.DataDisks).Count -gt 0) {
                Write-Output 'Removing data disks...'
                foreach ($datadisk in $vm.StorageProfile.DataDisks.Name) {
                    $dataDiskStorageAcct = Get-AzDisk -Name $datadisk
                    $dataDiskStorageAcct | Remove-AzDisk -Force
                    Write-Output "$($dataDiskstorageAcct.Name) is deleted"
                }
            }
        }

        if ($Wait.IsPresent) {
            & $scriptBlock -VMName $VMName -ResourceGroupName $ResourceGroupName
        }
        else {
            $jobParams = @{
                'ScriptBlock'  = $scriptBlock
                'ArgumentList' = @($VMName, $ResourceGroupName)
                'Name'         = "Azure VM $VMName Removal"
            }
            Start-Job @jobParams
        }
    }
}
function Fetchkeyvault {
    param (
        [Parameter(Mandatory = $True)][string]$TaskNumber,
        [Parameter(Mandatory = $True)][string]$SecretName,
        [Parameter(Mandatory = $True)][string]$KeyvaultId,
        [Parameter(Mandatory = $True)][string]$RGname
    )

    $ErrorActionPreference = "Stop"


    $jsonTemplateFile = '{
        "$schema": "https//urldefense.com/v3/__http//schemamanagementazurecom/schemas/2015-01-01/deploymentTemplate.json*__;Iw!!OsrnOkA!0X-ljdOxYtHwb$  ",
        "contentVersion": "\",
        "parameters": {
            "SecretCode": {
                "type": "securestring"
            }
        },
        "variables": {},
        "resources": [],
        "outputs": {
            "SecretCode-Val": {
                "type": "string",
                "value": "[parameters(''SecretCode'')]"
            }
        }
    }'


    $jsonParameterFile = @"
    {
        "$schema": "https//urldefense.com/v3/__https//schema.managementcom/schemas/2015-01-01/deploymentParameters.json*__;Iw!!OsrnOkA$  ",
        "contentVersion": "\",
        "parameters": {
            "SecretCode": {
                "reference": {
                    "keyVault": {
                        "id": "$KeyvaultId"
                    },
                    "secretName": "$SecretName"
                }
            }

        }
    }
"@

    #write-output $jsonParameterFile
    $armTemplate= "InvokeJob.json"
    Set-Content -Path $armTemplate -Value $jsonTemplateFile
    #Get-Content -Path $armTemplate

    $parameterFile = "InvokeJob-Parameter.json"
    Set-Content -Path $parameterFile -Value $jsonParameterFile

    $deploymentName = "automation-job-"+$TaskNumber
    Write-Output $deploymentName

    $keyvaultJobOutput = New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $RGname -TemplateFile $armTemplate -TemplateParameterFile $parameterFile -Verbose
    #Write-Output $keyvaultJobOutput
    $null= Remove-AzResourceGroupDeployment -ResourceGroupName $RGname -name $deploymentName
    return $keyvaultJobOutput
}

[System.String]$ADRecord = {
	param (
	 [Parameter(Mandatory = $true)]
	 [string] $VM
	 )
    #$Result= Get-ADComputer -Identity $VM | Remove-ADComputer -Recursive -Force -Verbose
	$Result= Get-ADComputer -Identity $VM | Remove-ADObject -Recursive -Confirm:$False
	$Result
	Write-Output "ADRecord Result is $($Result)"
}

$RemoveADRecord = "RemoveADRecord.ps1"
Out-File -FilePath $RemoveADRecord -InputObject $ADRecord -NoNewline

[System.String]$Disjoin = {
	Param(   
   [parameter(Mandatory=$true)][String]$username1,
   [parameter(Mandatory=$true)][String]$password1
)

	$user=$username1
    	#Write-Output "Username is $user" 
    	$pass=$password1
    	#Write-Output "Password is $pass"
	
	#$user1 = "grn\"+"$user"
    	#$pass = "%-)SrG-V4F"
	$secure = ConvertTo-SecureString -AsPlainText $pass -Force
    	#$pass = $secure
	$credential1= New-Object -typename System.Management.Automation.PsCredential($user, $Secure)
	$server = Get-WMIObject Win32_ComputerSystem| Select-Object Domain,Name
    	$domain1 = $server.Domain


######################## Delete DNS record from Infoblox ##################
    add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

	$userName = $user
    $password =  $pass
    # Create secure string for the password
    $Secure = ConvertTo-SecureString -AsPlainText $password -Force
    $Credentials1 = New-Object -typename System.Management.Automation.PsCredential($userName, $Secure)

    $host1 = $server.name
	$host1 
    $ip=(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'").IPAddress[0]
    $HostName = $host1 + "." + $domain1
    $HostName=$HostName.ToLower()
    $webrequest1 = Invoke-WebRequest -Uri "//uskmdns1/wapi/v1.2.1/record:host?name~=$HostName" -Method Get -Credential $Credentials1 -UseBasicParsing
    $b1=$webrequest1.Content | ConvertFrom-Json
    $refnew1 = $b1._ref
    $refnew1
    if ($refnew1 -ne $null)
    {
	$Delete1 = Invoke-WebRequest -Uri "//uskmdns1/wapi/v1.2.1/$refnew1" -Method Delete -Credential $Credentials1 -ContentType "application/json" -UseBasicParsing
	if ($Delete1.statusCode -eq "200")
		{
		Write-host "Host record associated with server $HostName deleted successfully."
		$Result="Host record associated with server $HostName deleted successfully."
		}
	else
		{
		Write-host "Failed to delete Host record associated with server $HostName."
		$Result="Failed to delete Host record associated with server $HostName."
		}
    }
    else
   	 	{
		Write-output "Host record is already deleted."
		$Result= "Host record is already deleted."
    		}


	if($domain1 -ne "WORKGROUP")
	{
		Remove-Computer -UnjoinDomaincredential $Credential1 -PassThru -Verbose -Force
		$server1 = Get-WMIObject Win32_ComputerSystem| Select-Object Domain,Name
		$domain2 = $server1.Domain

        if($domain2 -eq "WORKGROUP")
		{
            $Result+="Disjoined VM from domain successfully."
		}
		else
		{ 
			$Result+="Failed to disjoin VM from domain."
		}
		
	}
	else
	{
		$Result+="VM already disjoined from domain successfully."
	}
    	
	Write-Output "$($Result)"
}

$DomainDisjoinPath = "DomainDisjoin.ps1"
Out-File -FilePath $DomainDisjoinPath -InputObject $Disjoin -NoNewline



try
{
    $TaskName = $scriptParams.deploymentName
    $deploymentName= "Automation-job-"+$TaskName
    $subscription = $scriptParams.subscription
    #$VMName = $scriptParams.virtualMachineName
    #$ResourceGroupName = $scriptParams.resourceGroupName
    #$RGSubscription = $scriptParams.Resource_Subscription
	$automationRG= ""
## logic start####
    $VMName = $scriptParams.virtualMachineName
	#$VMName=$VMName.ToLower()
    $ipaddress= $scriptParams.IpAddress
    $kqlQuery1 = "resources | where type =~ 'microsoft.compute/virtualmachines' |where name == '$VMName' | extend nics=array_length(properties.networkProfile.networkInterfaces) | mv-expand nic=properties.networkProfile.networkInterfaces | where nics == 1 or nic.properties.primary =~ 'true' or isempty(nic) | project subid = subscriptionId, vmName = name,ResourceGroup = resourceGroup, vmSize=tostring(properties.hardwareProfile.vmSize), nicId = tostring(nic.id) | join kind=leftouter ( resources | where type =~ 'microsoft.network/networkinterfaces' | extend ipConfigsCount=array_length(properties.ipConfigurations) | mv-expand ipconfig=properties.ipConfigurations | where ipConfigsCount == 1 or ipconfig.properties.primary =~ 'true' | project nicId = id, privateIpId = tostring(ipconfig.properties.privateIPAddress)) on nicId |where privateIpId == '$ipaddress' | project-away nicId1"
    $result = Search-AzGraph -query $kqlQuery1

    if(-not $result -or $result.Count -eq 0){
    $VMNameUpper = $VMName.ToUpper()
    $kqlQuery2 = "resources | where type =~ 'microsoft.compute/virtualmachines' |where name == '$VMNameUpper' | extend nics=array_length(properties.networkProfile.networkInterfaces) | mv-expand nic=properties.networkProfile.networkInterfaces | where nics == 1 or nic.properties.primary =~ 'true' or isempty(nic) | project subid = subscriptionId, vmName = name,ResourceGroup = resourceGroup, vmSize=tostring(properties.hardwareProfile.vmSize), nicId = tostring(nic.id) | join kind=leftouter ( resources | where type =~ 'microsoft.network/networkinterfaces' | extend ipConfigsCount=array_length(properties.ipConfigurations) | mv-expand ipconfig=properties.ipConfigurations | where ipConfigsCount == 1 or ipconfig.properties.primary =~ 'true' | project nicId = id, privateIpId = tostring(ipconfig.properties.privateIPAddress)) on nicId |where privateIpId == '$ipaddress' | project-away nicId1"
    $result = Search-AzGraph -query $kqlQuery2
    }

    $RGSubscription= $result.subid
    $RGSubscription
    $VMName=$result.vmName
    $VMName
    $ResourceGroupName=$result.ResourceGroup
    $ResourceGroupName
	
## logic End####
    ################## Getting Secrets from KeyVault ####################

	#$keyvaultDeploymentName = "keyVault-" +(Get-Date -UFormat "%s") + "-" + $deploymentName
	$keyvaultDeploymentName = "keyVault" + "-" + $deploymentName
    $keyVaultName = ""
	$keyvaultId = "/subscriptions/$subscription/resourceGroups/$automationRG/providers/Microsoft.KeyVault/vaults/$keyVaultName"
	$UserName = Fetchkeyvault -TaskNumber "$keyvaultDeploymentName" -SecretName "svcuser" -KeyvaultId $keyVaultId -RGName "$automationRG"
	$UserName = $UserName.Outputs.('secretCode-Val').Value
	$Password = Fetchkeyvault -TaskNumber "$keyvaultDeploymentName" -SecretName "svcpwd" -KeyvaultId $keyVaultId -RGName "$automationRG"
	$Password = $Password.Outputs.('secretCode-Val').Value

    #Credentials to Secre String
    $securePwd = ConvertTo-SecureString $Password -AsPlainText -Force
    $Creds = New-Object System.Management.Automation.PSCredential ($UserName, $securePwd)

 ######################## Setting Subscription Context ####################

    Set-AzContext -SubscriptionId $RGSubscription
    Select-AzSubscription -SubscriptionId $RGSubscription


  ##### Checking the VM Power State #######

    $VMRunningStatus = ((Get-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName -Status).Statuses | Where-Object Code -Like "*PowerState*").displaystatus
        
	if ($VMRunningStatus -eq "VM running")
        {
		Write-Output "$($VMName) is found to be in running state hence it will not get deleted."
		throw("$($VMName) is found to be in running state hence it will not get deleted.")
        }
	else	
	{
		Write-Output " $($VMName) is in stopped state, so powering it ON for decom tasks.."
	   	Start-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName
		Write-Output "VM Started...wait for 5 mins"
		start-sleep -s 180
	}

 ####################### Disabling backup of a VM Starts ###################

    Write-output "Started backup Disabling, Fetching Backup Vault details"
    if($vault = Get-AzRecoveryServicesBackupStatus -Name $VMName -ResourceGroupName $ResourceGroupName -Type AzureVM)
    {
    $vault
	if($vault.BackedUp)
	{
	$array=($vault.VaultId).Split('/')
    #Write-output "Vault array after splitting is $array"   
    $indexRG = 0..($array.Length -1) | where {$array[$_] -eq 'resourcegroups'}
    #Write-output "Indetx of valut RG is $indexRG"
    $indexV = 0..($array.Length -1) | where {$array[$_] -eq 'vaults'}
    #Write-output "Index of Vault Nameis $indexV"
    $vrg=$array[$indexRG+1]
    Write-output "Vault RG Name: $vrg"
    $vname=$array[$indexV+1]
    Write-output "Vault Name: $vname"
    $Vault_details=Get-AzRecoveryServicesVault -Name "$vname"
    Set-AzRecoveryServicesVaultContext -Vault $Vault_details
	Write-output  "Vault details: $Vault_details"
	$vaultid = $Vault_details.id
	Write-output "Vault Id: $vaultid"
	Write-Output "VMName: $VMName"
    $container= Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -FriendlyName "$VMName" -VaultId "$vaultid"
	Write-Output "Container: $container"
	$Bkp_Item=Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType "AzureVM" -VaultId "$vaultid"

    Disable-AzRecoveryServicesBackupProtection -Item $Bkp_Item -Force
    Write-output("$($VMName) has been Removed from Backup successfully.")
    $output += "$($VMName) has been Removed from Backup successfully."
	}
	else
	{
		Write-output("$($VMName) does not have any backup policy enabled.")
	}
    }
    ########Removing the node from solarwinds#########
	#$ipaddress
	#$VMName
	#Define VM details
	#$virtualmachinename = ""
	#$vmresourceGroup = ""
	#$vmlocation = "northeurope"
	#Select-AzSubscription -Subscription ""
	#$existingExtension = Get-AzVMExtension -ResourceGroupName $vmresourceGroup -VMName $virtualmachinename -Name "CustomScriptExtension" -ErrorAction SilentlyContinue

	#if ($existingExtension) {
	#Write-Host "Removing previous Custom Script Extension..."
	#Remove-AzVMExtension -ResourceGroupName $vmresourceGroup -VMName $virtualmachinename -Name "CustomScriptExtension" -Force
	#Start-Sleep -Seconds 60  # Wait to ensure removal
	#}
	#$ipaddress
	#$VMName
	#$settings = @{
	#	"commandToExecute" = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\Users\tchirru\Documents\Node_Deletion.ps1 -privateip $ipaddress -VMName $VMName"
	#}
	#$settingsJson = $settings | ConvertTo-Json -Compress
	#Set-AzVMExtension -ResourceGroupName $vmresourceGroup -VMName $virtualmachinename -Location $vmlocation `
	#	-Name "CustomScriptExtension" -Publisher "Microsoft.Compute" `
	#	-ExtensionType "CustomScriptExtension" -TypeHandlerVersion "1.10" `
	#	-SettingString $settingsJson
	#Write-Host "Using the Custom Script Extension Added VM to Solarwinds Monitoring."	 	
	#Start-Sleep -Seconds 120  # Wait to ensure removal

    ################ Disjoin VM from domain ################

	Write-output "Disjoining VM from domain & deleting DNS entry..."
    $DomainDisjoinDetail = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath $DomainDisjoinPath -Parameter @{"username1" = "$UserName" ; "password1" = "$Password" } -Verbose
    #$DomainDisjoinDetail = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -Name $VMName -CommandId 'RunPowerShellScript' -ScriptBlock $Disjoin -Parameter @{"Credential" = "$Creds" }
    $DomainDisjoinDetail.value.message
    Write-output "DomainDisjoinDetail is $DomainDisjoinDetail"
    $output += "$($VMName) is disjoined from domain successfully."

    #################### Remove AD Object ####################
	
	Write-output "Removing AD Object"
    Select-AzSubscription -SubscriptionId ""
    $ADRecordDetail = Invoke-AzVMRunCommand -ResourceGroupName "" -Name "" -CommandId 'RunPowerShellScript' -ScriptPath $RemoveADRecord -Parameter @{"VM" = "$VMName" }
    Write-output "ADRecordDetail is $ADRecordDetail"
    $output += "AD Record for $($VMName) has been removed successfully."

    ######################## Setting Subscription Context ####################

    Set-AzContext -SubscriptionId $RGSubscription
    Select-AzSubscription -SubscriptionId $RGSubscription

    ######### Deletion of VM and its associated Resources...... ########################

  	$vm = Get-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName -status
   
        Remove-AzrVirtualMachine -VMName $VMName -ResourceGroupName $ResourceGroupName -Verbose -Wait -ErrorAction Stop
        start-sleep 100
        $vm1 = Get-AzResource -Name $VMName -ResourceGroupName $ResourceGroupName
        if($vm1 -eq $null)
        {
            $output += "$($VMName) and associated resources are deleted successfully."
        	Write-Output "$($VMName) and associated resources are deleted successfully."
	}
	

     Write-Output @{
            "DeploymentName" = $deploymentName
            "Outputs" = $output
            "Provisioningstate" = "Succeeded"
        }
}
catch {
    <#------------------------ 0. Error Handling: Get the exception message.-------------------------------------------#>
    Write-Output "Error caught in VM Decomm Script:"
    Write-Output $_
    Write-Output @{
        "DeploymentName" = $deploymentName
        "Outputs" = $_.Exception.Message
        "Provisioningstate" = "Failed"
    }
    Throw $_
}