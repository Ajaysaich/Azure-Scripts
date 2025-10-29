[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][object]$scriptParams
)

function Fetchkeyvault {
    param (
        [Parameter(Mandatory = $True)][string]$TaskNumber,
        [Parameter(Mandatory = $True)][string]$SecretName,
        [Parameter(Mandatory = $True)][string]$KeyvaultId,
        [Parameter(Mandatory = $True)][string]$RGname
    )

    $ErrorActionPreference = "Stop"


    $jsonTemplateFile = '{
        "$schema": "http//urldefensecom/v3/__http//schemamanagementazurecom/schemas/2015-01-01/deploymentTemplate.json*__;Iw!!OsrnOkA!0X-ljdOxYtHwb8A6F$  ",
        "contentVersion": "",
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
        "$schema": "http//urldefensecom/v3/__http//schemamanagementazurecom/schemas/2015-01-01/deploymentParameters.json*__;Iw!!OsrnOkA!0X-lE$  ",
        "contentVersion": "",
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
	 [parameter(Mandatory = $true)][string] $VM,
	 [parameter(Mandatory = $true)][String] $targetOU
	)
	write-output "target ou is :$targetOU"
	#[parameter(Mandatory=$true)][String]$VM,
   	#[parameter(Mandatory=$true)][String]$targetOU

	######### Moving Computer Object from Staging to targt OU path starts######
	write-output "inside AD, VM is :$VM"
	$getou = Get-ADComputer -Identity "$VM"
	$getou
	$ou = $getou.DistinguishedName
	#write-output "inside AD, OU is :$ou"

	if($ou -match "Staging")
	{
		Write-output "Computer object is in staging OU hence moving it to correct OU"
		#$targetOU= "OU=Windows Server 2019,OU=MemberServers,OU=Computers,OU=Root,DC=,DC=,DC=com"
		Get-ADComputer -Identity "$VM"| Move-ADObject -Targetpath $targetOU
		$tarOU= Get-ADComputer -Identity "$VM"
		#Write-Output "After moving AD record: $tarOU"
		$tarou1=$tarOU.DistinguishedName
		Write-output "After moving the computer Object form staging OU path is $tarou1"
		if($tarOU -match "Windows Server 2019") 
		{
				Write-output "Successfully moved AD record to target OU."
		}	
		else
		{
			Write-output "Unable to move AD record to Target OU."
		}
	}
	elseif($ou -match "Windows Server 2019")
	{
		Write-output "Computer is already in correct OU $ou."
	}
	else
	{
		Write-output "Computer object is in different OU hence moving it to correct OU."
		#$targetOU= "OU=Windows Server 2019,OU=MemberServers,OU=Computers,OU=Root,DC=,DC=,DC=com"
		Get-ADComputer -Identity "$VM"| Move-ADObject -Targetpath $targetOU
		$tarOU= Get-ADComputer -Identity "$VM"
		$tarou1=$tarOU.DistinguishedName
		Write-output "After moving the computer Object form staging OU path is $tarou1."
		if($tarOU -match "Windows Server 2019") 
		{
				Write-output "Successfully moved AD record to target OU."
		}	
		else
		{
			Write-output "Unable to move AD record to Target OU."
		}

	}

	######### Moving Computer Object from Staging to targt OU path starts######
    # $Result= Get-ADComputer -Identity $VM | Remove-ADComputer -Recursive -confirm:$False
	# Write-Output "$($Result)"
}

$moveADRecord = "MoveADRecord.ps1"
Out-File -FilePath $moveADRecord -InputObject $ADRecord -NoNewline

try 
{

	################## Getting Secrets from KeyVault ####################

	#$keyvaultDeploymentName = "keyVault-" +(Get-Date -UFormat "%s") + "-" + $deploymentName
	$keyvaultDeploymentName = "keyVault" + "-" + $deploymentName
    $keyVaultName = ""
	$keyvaultId = "/subscriptions/$subscription/resourceGroups/$automationRG/providers/Microsoft.KeyVault/vaults/$keyVaultName"
	$UserName = Fetchkeyvault -TaskNumber "$keyvaultDeploymentName" -SecretName "svcuser" -KeyvaultId $keyVaultId -RGName "$automationRG"
	$UserName = $UserName.Outputs.('secretCode-Val').Value
	$UserName
	$UserName1="grn\"+$UserName
	$UserName1
	$Password = Fetchkeyvault -TaskNumber "$keyvaultDeploymentName" -SecretName "svcpwd" -KeyvaultId $keyVaultId -RGName "$automationRG"
	$Password = $Password.Outputs.('secretCode-Val').Value
	#$Password
	$localadmin = Fetchkeyvault -TaskNumber "$keyvaultDeploymentName" -SecretName "localUser" -KeyvaultId $keyVaultId -RGName "$automationRG"
	$localadmin = $localadmin.Outputs.('secretCode-Val').Value

	$localadminpwd = Fetchkeyvault -TaskNumber "$keyvaultDeploymentName" -SecretName "localPwd" -KeyvaultId $keyVaultId -RGName "$automationRG"
	$localadminpwd = $localadminpwd.Outputs.('secretCode-Val').Value


    #Credentials to Secre String
    $securePwd = ConvertTo-SecureString $Password -AsPlainText -Force
    $Creds = New-Object System.Management.Automation.PSCredential ($UserName1,$securePwd)

    
    <#-------------------------------[ DECLARATION ]-----------------------------------------#>
    write-Output "Name: $($scriptParams.VMName)"
    $Subnet = $scriptParams.subnetName
    $Vnet = $scriptParams.virtualNetworkId
    $VRG = $scriptParams.VnetResourceGroup
    $OSVersion= $scriptParams.os_version
	Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription
	$vnetRG = (Get-AzVirtualNetwork -Name $Vnet).ResourceGroupName
	$Getvnet = Get-AzVirtualNetwork -Name $Vnet -ResourceGroupName $vnetRG
	<#if(!(($Getvnet.count) -eq 1)){
		
	}#>
	#$vnetRG = $Getvnet.ResourceGroupName
	
	write-output "Hello $vnetRG"
    $subnetName1 = (Get-AzVirtualNetworkSubnetConfig -Name $Subnet -VirtualNetwork $Getvnet).Id
    #$subnetName1
	$scriptParams.subnetName = $subnetName1
    $scriptParams.subnetName
	$Domain=$scriptParams.Domain
    #$Domain
	Write-output "Availability set name is $scriptParams.availabilitySet"
	
	$vmTemplateParams = @{}
    $allowedVMTemplateParams = @("resourceGroup" , "virtualNetworkId" , "subnetName" , "networkInterfaceName" ,"location","virtualMachineName",
                "osType",
                "vmSize",               
                "authenticationType",
                "adminUsername",
                "adminPassword",
                "imageType",
                "imagePublisher",
                "imageOffer",
                "imageSku",
                "imageVersion",
                "osDiskstorageAccountType", "tags","vnetRG","imageID","dataDisksArray")

	# $scriptParams.Keys | ForEach-Object { 
	#         if ($allowedVMTemplateParams.Contains($_)) {
	#             $vmTemplateParams[$_] = $($scriptParams[$_])
	#         }
	#     }

	$vmTemplateParams = @{ }
      foreach ($property in $scriptParams.GetEnumerator() ) {   
        
                if ($allowedVMTemplateParams.Contains($property.Name)) {
            $vmTemplateParams[$property.Name] = $property.Value
            }
        }

		
	Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription
	#$vnetRG=Get-Azresource -Name $scriptParams.virtualNetworkId

	$vmTemplateParams['adminUsername']=$localadmin
	$vmTemplateParams['adminPassword']=$localadminpwd
	$vmTemplateParams['vnetRG']=$vnetRG
	# $vmTemplateParams['virtualMachineName']=$scriptParams.VMName
	# $vmTemplateParams['resourceGroup']=$scriptParams.ResourceGroup

	# Initiate the deployment of Virtual Machine
	$deploymentName = 'VM_' + $scriptParams.virtualMachineName + "-" + $scriptParams.deploymentName #Deployment Name for Virtual Machine
	Write-Output "Deployment name is $deploymentName"
	$vmName =$scriptParams.virtualMachineName
	$rg = $scriptParams.resourceGroup
	write-Output "Template name is: $($scriptParams.templateFile)"
	Write-Output "Files downloaded to C temp are"
	get-childItem -path "$env:temp"
	
	if($scriptParams.osType -eq "Windows")
	{
		Write-Output "VM Template Params for Windows" $vmTemplateParams
		$deploymentName
		$scriptParams.resourceGroup
		#$vmTemplateParams
		$scriptParams.templateFileWindows
		if($OSVersion -eq "Windows 2019"){
		#$imageID="/subscriptions//resourceGroups//providers/Microsoft.Compute/galleries/GoldenImage_Windows/images/GoldenImage/versions/2019"
		$imageID="/subscriptions//resourceGroups//providers/Microsoft.Compute/galleries/GoldenImage_Latest/images/Windows_VM/versions/2019"
		}
		else{
		$imageID="/subscriptions//resourceGroups//providers/Microsoft.Compute/galleries/GoldenImage_Windows/images/LatestGoldenImageJun_2022/versions/22"
		}
		$vmTemplateParams['imageID']=$imageID
		#$vmTemplateParams
		$job = New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $scriptParams.resourceGroup -TemplateParameterObject $vmTemplateParams -TemplateFile "$env:temp\$($scriptParams.templateFileWindows)" 
		#$job
		$output=" VM created with ID: $($job.outputs.vmResourceID.value) Successfully"
		start-sleep -s 200
		write-output " Windows VM post provisioning"
		#$windows_post_prov = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath "C:\Temp\Windows_Post_Prov.ps1" -Parameter @{"Credential"="$Creds";"Domain"="$Domain"}
		#$windows_post_prov.Value.Message
		$Password
		$windows_post_prov = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath "$env:temp\VM_Post_Prov.ps1" -Parameter @{"Username"= "$UserName1" ; "Domain"= "$Domain" ; "Password"= "$Password"}
		Write-output "Domain join Status is: "
		$windows_post_prov.Value.Message
		restart-AzVM -ResourceGroupName $rg -Name $VMName 
		start-sleep -s 200
		Write-output "Moving AD Object"
		if($Domain -eq "")
		{
			Select-AzSubscription -SubscriptionId ""
			$OUPath="OU=Windows Server 2019,OU=MemberServers,OU=Computers,OU=GBLO,DC=,DC=,DC=com"
			#$ADRecordDetail = Invoke-AzVMRunCommand -ResourceGroupName "" -Name "" -CommandId 'RunPowerShellScript' -ScriptPath $RemoveADRecord -Parameter @{"VM" = "$VMName"}
			$ADRecordDetail = Invoke-AzVMRunCommand -ResourceGroupName "" -Name "" -CommandId 'RunPowerShellScript' -ScriptPath $moveADRecord -Parameter @{"VM" = "$VMName" ; "targetOU" = "$OUPath"}
			$ADRecordDetail.Value.Message
		}
		else
		{
			Select-AzSubscription -SubscriptionId ""
			$OUPath="OU=Windows Server 2019,OU=MemberServers,OU=Computers,OU=Root,DC=,DC=,DC=com"
			#$ADRecordDetail = Invoke-AzVMRunCommand -ResourceGroupName "-POC01" -Name "" -CommandId 'RunPowerShellScript' -ScriptPath $RemoveADRecord -Parameter @{"VM" = "$VMName" }
			$ADRecordDetail = Invoke-AzVMRunCommand -ResourceGroupName "-POC01" -Name "" -CommandId 'RunPowerShellScript' -ScriptPath $moveADRecord -Parameter @{"VM" = "$VMName" ; "targetOU" = "$OUPath"}
			$ADRecordDetail.Value.Message
		}
		######################## Setting Subscription Context ###################
		Set-AzContext -SubscriptionId $scriptParams.Resource_Subscription
		Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription
		write-Output "Restarting VM, wait for 5 mins"
		restart-AzVM -ResourceGroupName $rg -Name $VMName 
		start-sleep -s 200
		#$Password		
		Write-output "Creating Host recrod in Infoblox:"
		$windows_post_prov = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath "$env:temp\Windows_Post_Prov.ps1" -Parameter @{"Username"="$UserName";"Domain"="$Domain";"Password"="$Password"}
		$windows_post_prov.Value.Message
		#Write-output "adding windows vmnode to solarwinds"
        #Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription
        #$vmid = Get-AzVM -Name $vmName -ResourceGroupName $rg
        #$nic = Get-AzNetworkInterface -ResourceId $vmid.NetworkProfile.NetworkInterfaces[0].Id
        #$privateip = $nic.IpConfigurations[0].PrivateIpAddress
        #$privateip
        #$Domain
        #$Environment = $scriptParams.tags.Environment
        #$Environment
        #$VMName

		# Define VM details
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
		#$privateip
		#$Domain
		#$Environment = $scriptParams.tags.Environment
		#$Environment
		#$VMName
		#$settings = @{
			#"commandToExecute" = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\\Users\\tchirru\\Documents\\solarwinds_script.ps1 -privateip $privateip -Domain $Domain -Environment $Environment -VMName $VMName"
		#}
		#$settingsJson = $settings | ConvertTo-Json -Compress
		#Set-AzVMExtension -ResourceGroupName $vmresourceGroup -VMName $virtualmachinename -Location $vmlocation `
			#-Name "CustomScriptExtension" -Publisher "Microsoft.Compute" `
			#-ExtensionType "CustomScriptExtension" -TypeHandlerVersion "1.10" `
			#-SettingString $settingsJson
		#Write-Host "Using the Custom Script Extension Added VM to Solarwinds Monitoring."	 	
	}
	else
	{
		$linuxver="$scriptParams.linuxver"
		if($scriptParams.linuxver -eq "SUSE12SP5")
		{
			#$imageID="/subscriptions//resourceGroups//providers/Microsoft.Compute/galleries/Suse12Sp5/images/SUSE12SP5image"
			$imageID="/subscriptions//resourceGroups//providers/Microsoft.Compute/galleries//images/suse15sp6goldenimage"
		}
		elseif($scriptParams.linuxver -eq "SUSE 15.5")
		{
			#$imageID="/subscriptions//resourceGroups//providers/Microsoft.Compute/galleries/Suse12Sp5/images/SUSE12SP5image"
			$imageID="/subscriptions//resourceGroups//providers/Microsoft.Compute/galleries/AZEASIG01/images/goldenimageSuse15sp5new"
		}
		elseif($scriptParams.linuxver -eq "SUSE 15.6")
		{
			#$imageID="/subscriptions/c8f6dd83-d11b-4411-b05f-99056941b33e/resourceGroups/AZ-EUNO-EDT-AKS-D-RG001/providers/Microsoft.Compute/galleries/Suse12Sp5/images/SUSE12SP5image"
			$imageID="/subscriptions/68c7099e-8605-404c-b107-038c6037dc2c/resourceGroups/AZEASTGENTRIENC-POC01/providers/Microsoft.Compute/galleries/AZEASIG01/images/suse15sp7goldenimage/versions/0.0.1"
		}
		else{
			
			#$imageID="/subscriptions//resourceGroups/providers/Microsoft.Compute/galleries/AZEASIG01/images/ubuntu-18-image-20210209"
			$imageID="/subscriptions//resourceGroups/-POC01/providers/Microsoft.Compute/galleries/AZEASIG01/images/ubuntu2404goldenimage02/versions/0.0.2"
		}
		$vmTemplateParams['imageID']=$imageID
		Write-Output "VM Template Params for Linux" $vmTemplateParams
 
		$job = New-AzResourceGroupDeployment -Name  $deploymentName -ResourceGroupName $scriptParams.resourceGroup -TemplateParameterObject $vmTemplateParams -TemplateFile "$env:temp\$($scriptParams.templateFileLinux)" 
		write-Output "Resource created with Name: $($job.outputs.vmResourceID.value) Successfully"
		$job.outputs.vmResourceID.value
		start-sleep -s 240
		Write-output "After completion of sleep time"

        Set-AzContext -SubscriptionId $scriptParams.Resource_Subscription
		Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription

		restart-AzVM -ResourceGroupName $rg -Name $VMName
		start-sleep -s 200

        $vmName = $scriptParams.virtualMachineName
        $rg = $scriptParams.resourceGroup
        $Domain=$scriptParams.Domain

        $HostName = $vmName + "." + $Domain
        $HostName

$Script = @"
hostname -i
"@
        $results = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId 'RunShellScript' -ScriptString $Script
        $results.Value.Message

        $ip = $results.Value.Message
        if($ip -match '(\d{1,3}\.){3}\d{1,3}'){
        $IPAddress = $Matches[0]
        }
        $IPAddress
        $virtualmachinename = ""
        $vmresourceGroup = ""
        Select-AzSubscription -Subscription ""
        $response1 = Invoke-AzVMRunCommand -ResourceGroupName $vmresourceGroup -Name $virtualmachinename -CommandId 'RunPowerShellScript' -ScriptPath "$env:temp\Linux_VM_DnsRecord_Creation.ps1" -Parameter @{"IPAddress"="$IPAddress";"HostName"="$HostName"}
        Write-output "Creating Host recrod in Infoblox for linux VM:" 
        $outputmsg = $response1.Value[0].Message
        $outputmsg
		start-sleep -s 200
		$linux_post_prov = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $VMName -CommandId 'RunShellScript' -ScriptPath "$env:temp\Linux_Post_Prov.sh" -Parameter @{"linuxver"="$linuxver";"vmname"="$VMName";"ver"="$linuxver"}
		Write-output "Linux post provisioning Status is:" 
		$linux_post_prov.Value.Message

		#Write-output "adding linux vmnode to solarwinds"
		#Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription
        #$vmid = Get-AzVM -Name $vmName -ResourceGroupName $rg
        #$nic = Get-AzNetworkInterface -ResourceId $vmid.NetworkProfile.NetworkInterfaces[0].Id
        #$privateip = $nic.IpConfigurations[0].PrivateIpAddress
        #$privateip
        #$Domain
        #$Environment = $scriptParams.tags.Environment
        #$Environment
        #$VMName
		# Define VM details
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
		#$privateip
		#$Environment = $scriptParams.tags.Environment
		#$Environment
		#$VMName
		#$settings = @{
			#"commandToExecute" = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\Users\tchirru\Documents\Solarwinds_LinuxScript.ps1 -privateip $privateip -Environment $Environment -VMName $VMName"
		#}
		#$settingsJson = $settings | ConvertTo-Json -Compress
		#Set-AzVMExtension -ResourceGroupName $vmresourceGroup -VMName $virtualmachinename -Location $vmlocation `
			#-Name "CustomScriptExtension" -Publisher "Microsoft.Compute" `
			#-ExtensionType "CustomScriptExtension" -TypeHandlerVersion "1.10" `
			#-SettingString $settingsJson
		#Write-Host "Using the Custom Script Extension Added VM to Solarwinds Monitoring."

		#$linux_post_prov = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $VMName -CommandId 'RunShellScript' -ScriptPath "$env:temp\Linux_Post_Prov.sh" -Parameter @{"linuxver"="$linuxver";"vmname"="$VMName";"ver"="$linuxver"}
		#Write-output "Linux post provisioning Status is:" 
		#$linux_post_prov.Value.Message

	}
	
	write-output "Backup Enable: "
	$backupreq=$scriptParams.enable_backup

	write-output "Backup required or not: $backupreq"
	if($backupreq -eq "true")
	{
		Write-output "Enabling Backup"
		$RecoveryServicesVault= $scriptParams.recovery_vault
		$BackupProtectionPolicy=$scriptParams.backup_policy
		$RSV=Get-AzRecoveryServicesVault -Name $RecoveryServicesVault
		write-output "Recovery service vault :$RSV"
		if($RSV)
		{
			Write-output("Recovery service Vault found : $($RSV.name)")
			$RSV | Set-AzRecoveryServicesVaultContext
		}
		else
		{
			Throw("Recovery service Vault $RecoveryServicesVault Not found")
		}
		if($BackupProtectionPolicy)
		{
			$policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $BackupProtectionPolicy
		}
		if($policy)
		{
			$output= Enable-AzRecoveryServicesBackupProtection -ResourceGroupName $rg -Name $vmName -Policy $policy
		}

		
	}
	else
	{
		Write-output "Backup not required. Hence not enabling it."
	}
$ASREnable = $scriptParams.asr_enable 

if ($ASREnable -eq "Yes"){
	Write-output "Enabling the ASR"
    
$sub = Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription
$subscription = $sub.Subscription
$subname = $subscription.Name
$subname

# Define target subscription and location for matching
$targetSubscription = $subname
#olbfile
$Location = $scriptParams.location
$targetLocation = $scriptParams.target_location
$proxy = $scriptParams.dr_proxy  
$BypassList = if($scriptParams.bypasslist -match "^(?i)null$"){@()} else {$scriptParams.bypasslist}
$TargetResourceGroupName = $scriptParams.target_resource_group
$TargetVirtualNetwork = $scriptParams.vnet
$StorageAccount = $scriptParams.storage_account  
$policyName = $scriptParams.replication_policy
$vaultName = $scriptParams.recovery_service_vault
$vaultResourceGroup = $scriptParams.recovery_service_vault_rsg
$StorageAccountRG = $scriptParams.storage_account_rsg 

    # Output the matched details
    Write-Output " Matched Row Details:"
    Write-Output " Location:$Location"
    Write-Output " Target Location:$targetLocation"
    Write-Output " Proxy:$proxy"
    Write-Output " BypassList:$BypassList"
    Write-Output " VaultSubscription:$VaultSubscription"
    Write-Output " Target Resource Group Name:$TargetResourceGroupName"
    Write-Output " Target Virtual Network:$TargetVirtualNetwork"
    Write-Output " Storage Account:$StorageAccount"
    Write-Output " Policy Name:$policyName"
    Write-Output " Vault Name:$vaultName"
    Write-Output " Vault Resource Group:$vaultResourceGroup"
    Write-Output " Storage Account RG:$StorageAccountRG"

Select-AzSubscription -SubscriptionId $scriptParams.Resource_Subscription 

$PrimaryStagingStorageAccount = (Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $StorageAccount).Id 
$TargetResourceGroupId = (Get-AzResourceGroup -Name $TargetResourceGroupName -Location $targetLocation).ResourceId
$TargetVirtualNetworkId = (Get-AzVirtualNetwork -Name $TargetVirtualNetwork -ResourceGroupName $TargetResourceGroupName).Id    
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $vaultResourceGroup -Name $vaultName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault

$azureFabrics = Get-AzRecoveryServicesAsrFabric
$priFab = $azureFabrics | Where-Object { $_.FabricSpecificDetails.Location -like $Location }
$recFab = $azureFabrics | Where-Object { $_.FabricSpecificDetails.Location -eq $targetLocation }
# Get protection containers for the primary and recovery fabrics
$priContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $priFab
$pr = $priContainer[0]
$recContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $recFab
$re = $recContainer[0]
# Get the protection container mapping based on the specified policy
$primaryProtectionContainerMappings = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $pr | Where-Object { $_.TargetProtectionContainerId -like $re.Id }
$primaryMapping = $primaryProtectionContainerMappings | Where-Object { $_.PolicyFriendlyName -eq $policyName }
$primaryname = $primaryMapping.Name
$primaryProtectionContainerMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -Name $primaryname -ProtectionContainer $pr
# Reverse protection container mapping (for failback scenarios)
$reverseContainerMappings = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $re | Where-Object { $_.TargetProtectionContainerId -like $pr.Id }
$reverseMapping = $reverseContainerMappings | Where-Object { $_.PolicyFriendlyName -eq $policyName }
$reverseName = $reverseMapping.Name
$reverseContainerMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -Name $reverseName -ProtectionContainer $re
# Get the virtual machine
$VMName 
$rg 
$vm = Get-AzVM -ResourceGroupName $rg -Name $VMName
$vm
# Initialize disk replication configurations
$diskList = New-Object System.Collections.ArrayList
 
# Get the OS disk storage type and configure OS disk replication
$osDiskType = (Get-AzDisk -ResourceGroupName $vm.ResourceGroupName -DiskName $vm.StorageProfile.OsDisk.Name).Sku.Name
$osDisk = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -DiskId $vm.StorageProfile.OsDisk.ManagedDisk.Id `
    -LogStorageAccountId $PrimaryStagingStorageAccount -ManagedDisk  -RecoveryReplicaDiskAccountType $osDiskType `
    -RecoveryResourceGroupId $TargetResourceGroupId -RecoveryTargetDiskAccountType $osDiskType
$diskList.Add($osDisk)
 
# Loop through each data disk to configure their replication
foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
    $dataDiskType = (Get-AzDisk -ResourceGroupName $vm.ResourceGroupName -DiskName $dataDisk.Name).Sku.Name
    $disk = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -DiskId $dataDisk.ManagedDisk.Id `
        -LogStorageAccountId $PrimaryStagingStorageAccount -ManagedDisk  -RecoveryReplicaDiskAccountType $dataDiskType `
        -RecoveryResourceGroupId $TargetResourceGroupId -RecoveryTargetDiskAccountType $dataDiskType
    $diskList.Add($disk)
}

Write-Output "Enable protection being triggered."

# Enable replication for the VM
$asrjob = New-AzRecoveryServicesAsrReplicationProtectedItem -Name $VMName -ProtectionContainerMapping $primaryProtectionContainerMapping `
    -AzureVmId $vm.ID -AzureToAzureDiskReplicationConfiguration $diskList -RecoveryResourceGroupId $TargetResourceGroupId `
    -RecoveryAzureNetworkId $TargetVirtualNetworkId
 
Start-Sleep 30
$asrjob

# Track the job status
$job1 = Get-AzRecoveryServicesAsrJob -Job $asrjob
$job1

# Get replication protected item
$targetObjectName = $job1.TargetObjectName
$targetObjectName
#$rpi = Get-AzRecoveryServicesAsrReplicationProtectedItem -Name $targetObjectName -ProtectionContainer $pr

Start-Sleep 300
#____________________________________________________Proxy Part ___________________________

if ($vm.StorageProfile.OsDisk.OsType -eq "Windows"){

$resourceGroupName = $scriptParams.resourceGroup
$resourceGroupName
$vmName = $scriptParams.virtualMachineName
$vmName
$proxy
$BypassList

<#
$proxy = ""
$BypassList =""
#>

if($BypassList -ne "$null")
{
$ScriptBlock = {
    param(
        [string] $Proxy,
        [string] $BypassList
        )
$proxyfile= "C:\ProgramData\Microsoft Azure Site Recovery\Config\ProxyInfo.conf"
$configurationContent = @"
[proxy]
Address=$Proxy
Port=80
BypassList=$BypassList
"@
Set-Content -path $proxyfile -Value $configurationContent
}

$Script = [scriptblock]::create($ScriptBlock)
$Script
$data = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $Script -Parameter @{"Proxy" = "$proxy"; "BypassList" = "$BypassList"} -ErrorAction Ignore
$data

#Restart-AzRecoveryServicesAsrJob -Job $job

}
else {

$ScriptBlock = {
    param(
        [string] $Proxy
        )
$proxyfile= "C:\ProgramData\Microsoft Azure Site Recovery\Config\ProxyInfo.conf"
$configurationContent = @"
[proxy]
Address=$Proxy
Port=80
"@
Set-Content -path $proxyfile -Value $configurationContent
}

$Script = [scriptblock]::create($ScriptBlock)
$Script
$data = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $Script -Parameter @{"Proxy" = "$proxy"} -ErrorAction Ignore
$data

#Restart-AzRecoveryServicesAsrJob -Job $job

}
}
 
if ($vm.StorageProfile.OsDisk.OsType -eq "Linux"){

$resourceGroupName = $scriptParams.resourceGroup
$resourceGroupName
$vmName = $scriptParams.virtualMachineName
$vmName

$proxy
$BypassList


<#
$proxy = ""
$BypassList =""
#>

if($BypassList -ne $null)
{
$ScriptBlock = {
    param(
        [string] $Proxy,
        [string] $BypassList
        )
echo "[proxy]
Address=$Proxy
Port=80
BypassList=$BypassList
" >> /usr/local/InMage/config/ProxyInfo.conf
}

$Script = [scriptblock]::create($ScriptBlock)
$Script
$data = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId 'Bash' -ScriptString $Script -Parameter @{'Proxy' = $proxy; 'BypassList' = $BypassList} -ErrorAction Ignore
$data

#Restart-AzRecoveryServicesAsrJob -Job $job

}
else {

$ScriptBlock = {
    param(
        [string] $Proxy,
        [string] $BypassList
        )
echo "[proxy]
Address=$Proxy
#Address=
Port=80
" >> /usr/local/InMage/config/ProxyInfo.conf
}

$Script = [scriptblock]::create($ScriptBlock)
$Script
$data = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId 'Bash' -ScriptString $Script -Parameter @{'Proxy' = $proxy; 'BypassList' = $BypassList} -ErrorAction Ignore
$data

#Restart-AzRecoveryServicesAsrJob -Job $job

}

 

}

Start-Sleep 300

$sub = $asrjob.ID.Split("/")[2]
$vaultResourceGroup = $asrjob.ID.Split("/")[4]
$vaultName = $asrjob.ID.Split("/")[8]
Select-AzSubscription -Subscription $sub
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $vaultResourceGroup -Name $vaultName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault
#$restarjob= (Get-AzRecoveryServicesAsrJob -TargetObjectId $job.TargetObjectId)[0]
$restarjob1= (Get-AzRecoveryServicesAsrJob | where {$_.TargetObjectName -eq $asrjob.TargetObjectName})[0]
#$restarjob
$restarjob1

if($restarjob1.State -eq "Failed"){

Restart-AzRecoveryServicesAsrJob -job $restarjob1 -ErrorAction Ignore

}


$restarjob1

if($restarjob1.State -eq "CompletedWithInformation"){

write-host "Successfully completed the ASR Enable"

}





}



	Write-Output "Deployment output is $output "   
	Write-Output @{
			"DeploymentName"    = $deploymentName
			"Outputs"           = $output
			"Provisioningstate" = $job.ProvisioningState
	}
}
catch{
	Write-output "Getting Error"
}