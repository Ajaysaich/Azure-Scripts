[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,Position=0)][object]$scriptParams
)
Try {
    # Parameters
    $TaskNumber = $scriptParams.deploymentName
    $deploymentName = "automation-job-"+$TaskNumber
    $use = $scriptParams.Request 
    $HostName1  = $scriptParams.Record_Name
    $modifyip = $scriptParams.Modifyip   
    $VmName = $scriptParams.virtualMachineName
    $IPAddress = $scriptParams.IpAddress
    $SubscriptionName = $scriptParams.subscription
    $resourceGroupName = $scriptParams.resourceGroupName
    $kqlQuery1 = "resources | where type =~ 'microsoft.compute/virtualmachines' |where name == '$VmName' | extend nics=array_length(properties.networkProfile.networkInterfaces) | mv-expand nic=properties.networkProfile.networkInterfaces | where nics == 1 or nic.properties.primary =~ 'true' or isempty(nic) | project subid = subscriptionId, vmName = name,ResourceGroup = resourceGroup, vmSize=tostring(properties.hardwareProfile.vmSize), nicId = tostring(nic.id) | join kind=leftouter ( resources | where type =~ 'microsoft.network/networkinterfaces' | extend ipConfigsCount=array_length(properties.ipConfigurations) | mv-expand ipconfig=properties.ipConfigurations | where ipConfigsCount == 1 or ipconfig.properties.primary =~ 'true' | project nicId = id, privateIpId = tostring(ipconfig.properties.privateIPAddress)) on nicId |where privateIpId == '$IPAddress' | project-away nicId1"
	$result = Search-AzGraph -query $kqlQuery1
	$subscription = $result.subid
	$VMName = $result.vmName
	$resourceGroup = $result.ResourceGroup
	$subscription
	$VMName
	$resourceGroup
    Select-AzSubscription -Subscription $subscription
    Set-AzContext -Subscription $subscription
[System.String]$InvokeDNS = {
    param (
	 [parameter(Mandatory = $true)][string] $VmName,
	 [parameter(Mandatory = $true)][String] $IPAddress
	)
    function Ignore-SelfSignedCerts {
    try {
        Write-Host "Adding TrustAllCertsPolicy type." -ForegroundColor White
        Add-Type -TypeDefinition @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy
        {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem)
            {
                return true;
            }
        }
"@
        Write-Host "TrustAllCertsPolicy type added." -ForegroundColor White
    } catch {
        Write-Host $_ -ForegroundColor Yellow
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
# Ignore cert warnings
Ignore-SelfSignedCerts
# Set variables
$domain = (Get-WmiObject Win32_ComputerSystem).Domain
$HostName = "$VmName.$domain"
$username = ""
$password = ""
# Secure credentials
$pwd = ConvertTo-SecureString $password -AsPlainText -Force
$creds = New-Object Management.Automation.PSCredential ($username, $pwd)
# Step 1: GET record
$url = "https//uskmdns1/wapi/v2.12/search?address=$IPAddress&_return_as_object=1"
try {
    $response = Invoke-RestMethod -Uri $url -Method GET -Credential $creds -UseBasicParsing
} catch {
    Write-Host "Error during GET request: $_" 
    $response = $null
}
if ($response -and $response.result._ref) {
    $ref = $response.result._ref
    $parts = $ref -split "/"
    $recordType = ($parts[0] -split ":")[1]
    $idandname = $parts[1] -split ":"
    $id = $idandname[0]
    $name = $idandname[1]
    if ($name -eq $HostName) {
        Write-Host "Record already exists with matching hostname: $name"
    } else {
        Write-Host "Record exists but hostname doesn't match. Existing: $name, Expected: $HostName"
    }
} else {
    Write-Host "No existing record found. Proceeding to create..."
    # Step 2: POST to create new record
    $urlPost = "https//uskmdns1/wapi/v2.12/record:host?_return_as_object=1"
    $headersPost = @{ "Content-Type" = "application/json" }
    $bodyPost = @{
        name     = $HostName
        ipv4addrs =@(@{ipv4addr=$IPAddress})
    } | ConvertTo-Json -Depth 3
    try {
        $responsePost = Invoke-RestMethod -Uri $urlPost -Method POST -Headers $headersPost -Body $bodyPost -Credential $creds
        if ($responsePost -and $responsePost.result) {
            $parts0 = $responsePost.result -split "/"
            $recordType0 = ($parts0[0] -split ":")[1]
            $idandname0 = $parts0[1] -split ":"
            $id0 = $idandname0[0]
            $name0 = $idandname0[1]
            if ($name0 -eq $HostName) {
                Write-Host "Successfully created record: $name0"
            } else {
                Write-Host "Record creation mismatch. Got: $name0, Expected: $HostName" 
            }
        } else {
            Write-Host "Record creation failed or returned empty result." 
        }
    } catch {
        Write-Host "Error during POST request: $_" 
    }
}
}
$InfloboxDNS = "InfloboxDNS.ps1"
Out-File -FilePath $InfloboxDNS -InputObject $InvokeDNS -NoNewline

[System.String]$InvokeModifyDNS = {
    param (
	 [parameter(Mandatory = $true)][string] $VmName,
	 [parameter(Mandatory = $true)][String] $IPAddress,
	 [parameter(Mandatory = $true)][String] $HostName1
	)
    function Ignore-SelfSignedCerts {
    try {
        Write-Host "Adding TrustAllCertsPolicy type."
        Add-Type -TypeDefinition @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy
        {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem)
            {
                return true;
            }
        }
"@
        Write-Host "TrustAllCertsPolicy type added." 
    } catch {
        Write-Host $_ 
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
# Ignore cert warnings
Ignore-SelfSignedCerts
# Set variables
$domain = (Get-WmiObject Win32_ComputerSystem).Domain
$HostName = "$VmName.$domain"
$username = ""
$password = ""
# Secure credentials
$pwd = ConvertTo-SecureString $password -AsPlainText -Force
$creds = New-Object Management.Automation.PSCredential ($username, $pwd)

$url = "https//uskmdns1/wapi/v2.12/search?address=$IPAddress&_return_as_object=1"
try {
    $response = Invoke-RestMethod -Uri $url -Method GET -Credential $creds -UseBasicParsing
} catch {
    Write-Host "Error in GET request: $_"
    $response = $null
}
if ($response -and $response.result -and $response.result._ref) {
    $ref1 = $response.result._ref
    $parts = $ref1 -split "/"
    $recordType = ($parts[0] -split ":")[1]
    $idandname = $parts[1] -split ":"
    $id = $idandname[0]
    $name = $idandname[1]
    Write-Host "Found record: $name ($recordType)"
    if($name -eq $HostName1){
    write-host "No update needed.Record already has the desired name :$HostName1"
    }
    else{
    # Step 3: Update record name
    $url1 = "https//uskmdns1/wapi/v2.12/${ref1}?_return_as_object=1"
    $host_details = @{ name = $HostName1 }
    $body1 = $host_details | ConvertTo-Json
    try {
        $response1 = Invoke-RestMethod -Uri $url1 -Method PUT -Credential $creds -ContentType 'application/json' -Body $body1
        if ($response1 -and $response1.result) {
            $parts1 = $response1.result -split "/"
            $recordType1 = ($parts1[0] -split ":")[1]
            $idandname1 = $parts1[1] -split ":"
            $id1 = $idandname1[0]
            $name1 = $idandname1[1]
            if ($name1 -eq $HostName1) {
                Write-Host "Record successfully updated to: $name1"
            } else {
                Write-Host "Update completed, but name mismatch: $name1 vs $HostName1"
            }
        } else {
            Write-Host "PUT response empty or invalid."
        }
    } catch {
        Write-Host "Error in PUT request: $_"
    }
    }
} else {
    Write-Host "No DNS record found for IP: $ip"
}
}
$InfloboxModifyDNS = "InfloboxModifyDNS.ps1"
Out-File -FilePath $InfloboxModifyDNS -InputObject $InvokeModifyDNS -NoNewline

[System.String]$InvokeModifyipDNS = {
    param (
	 [parameter(Mandatory = $true)][string] $VmName,
	 [parameter(Mandatory = $true)][String] $IPAddress,
	 [parameter(Mandatory = $true)][String] $modifyip
	)
    function Ignore-SelfSignedCerts {
    try {
        Write-Host "Adding TrustAllCertsPolicy type."
        Add-Type -TypeDefinition @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy
        {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem)
            {
                return true;
            }
        }
"@
        Write-Host "TrustAllCertsPolicy type added." 
    } catch {
        Write-Host $_ 
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
# Ignore cert warnings
Ignore-SelfSignedCerts
# Set variables
$domain = (Get-WmiObject Win32_ComputerSystem).Domain
$HostName = "$VmName.$domain"
$username = ""
$password = ""
# Secure credentials
$pwd = ConvertTo-SecureString $password -AsPlainText -Force
$creds = New-Object Management.Automation.PSCredential ($username, $pwd)

$url = "https//uskmdns1/wapi/v2.12/search?address=$IPAddress&_return_as_object=1"
try {
    $response = Invoke-RestMethod -Uri $url -Method GET -Credential $creds -UseBasicParsing
} catch {
    Write-Host "Error in GET request: $_"
    $response = $null
}
if ($response -and $response.result -and $response.result._ref) {
    $ref1 = $response.result._ref
    $parts = $ref1 -split "/"
    $recordType = ($parts[0] -split ":")[1]
    $idandname = $parts[1] -split ":"
    $id = $idandname[0]
    $name = $idandname[1]
    Write-Host "Found record: $name ($recordType)"
    if($name -eq $HostName -and $IPAddress -eq $modifyip){
    Write-Host "Record already matches desired Record Name and IP. NO update Needed."
    }else{
    # Step 3: Update record name
    $url1 = "https//uskmdns1/wapi/v2.12/${ref1}?_return_as_object=1"
    #$host_details = @{ name = $HostName1 }
    $host_details = @{ 
        name = $HostName
        ipv4addr = $modifyip 
    }
    $body1 = $host_details | ConvertTo-Json
    try {
        $response1 = Invoke-RestMethod -Uri $url1 -Method PUT -Credential $creds -ContentType 'application/json' -Body $body1
            if ($response1) {
                Write-Host "Record successfully updated to: $HostName with IP: $modifyip"
            } else {
                Write-Host "PUT response empty or invalid."
            }
        } catch {
            Write-Host "Error in PUT request: $_"
        }
    } else {
        Write-Host "No DNS record found for IP: $IPAddress"
    }
    }
}
$InfloboxModifyipDNS = "InfloboxModifyipDNS.ps1"
Out-File -FilePath $InfloboxModifyipDNS -InputObject $InvokeModifyipDNS -NoNewline

[System.String]$InvokeDeleteDNS = {
    param (
	 [parameter(Mandatory = $true)][string] $VmName,
	 [parameter(Mandatory = $true)][String] $IPAddress
	)
    function Ignore-SelfSignedCerts {
    try {
        Write-Host "Adding TrustAllCertsPolicy type." -ForegroundColor White
        Add-Type -TypeDefinition @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy
        {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem)
            {
                return true;
            }
        }
"@
        Write-Host "TrustAllCertsPolicy type added." -ForegroundColor White
    } catch {
        Write-Host $_ -ForegroundColor Yellow
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
# Ignore cert warnings
Ignore-SelfSignedCerts
# Set variables
$domain = (Get-WmiObject Win32_ComputerSystem).Domain
$HostName = "$VmName.$domain"
$username = ""
$password = ""
# Secure credentials
$pwd = ConvertTo-SecureString $password -AsPlainText -Force
$creds = New-Object Management.Automation.PSCredential ($username, $pwd)
$url = "https//uskmdns1/wapi/v2.12/search?address=$IPAddress&_return_as_object=1"
try {
    $reponce = Invoke-RestMethod -Uri $url -Method GET -Credential $creds -UseBasicParsing
} catch {
    Write-Host "Error in GET request: $_" -ForegroundColor Red
    $reponce = $null
}
if ($reponce -and $reponce.result -and $reponce.result._ref) {
    $ref1 = $reponce.result._ref
    Write-Host "Record found: $ref1" -ForegroundColor Cyan
    $parts = $ref1 -split "/"
    $recordType = ($parts[0] -split ":")[1]
    $idandname = $parts[1] -split ":"
    $id = $idandname[0]
    $name = $idandname[1]
    Write-Host "Deleting record: $name" -ForegroundColor Yellow
    # Step 2: DELETE record
    $url2 = "https//uskmdns1/wapi/v2.12/${ref1}?_return_as_object=1"
    try {
        $responce2 = Invoke-RestMethod -Uri $url2 -Method DELETE -Credential $creds
        Write-Host "Record deleted successfully." -ForegroundColor Green

        $parts2 = $responce2.result -split "/"
        $recordType2 = ($parts2[0] -split ":")[1]
        $idandname2 = $parts2[1] -split ":"
        $id2 = $idandname2[0]
        $name2 = $idandname2[1]
        Write-Host "Deleted Record: $name2" -ForegroundColor Green
    } catch {
        Write-Host "Error in DELETE request: $_" -ForegroundColor Red
    }
} else {
    Write-Host "No record found for IP: $ip" -ForegroundColor Gray
}
# Step 3: Verify deletion
Write-Host "Verifying deletion..." -ForegroundColor Cyan
try {
    $verifyUrl = "https//uskmdns1/wapi/v2.12/search?address=$IPAddress&_return_as_object=1"
    $verifyResponse = Invoke-RestMethod -Uri $verifyUrl -Method GET -Credential $creds -UseBasicParsing

    if ($verifyResponse -and $verifyResponse.result) {
        Write-Host "Record still exists: $($verifyResponse.result._ref)" -ForegroundColor Red
    } else {
        Write-Host "Record successfully deleted. No record found." -ForegroundColor Green
    }
} catch {
    Write-Host "Error verifying deletion: $_" -ForegroundColor Red
}
}
$InfloboxDeleteDNS = "InfloboxDeleteDNS.ps1"
Out-File -FilePath $InfloboxDeleteDNS -InputObject $InvokeDeleteDNS -NoNewline

if ($use -eq "Create") {
$response1 = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath $InfloboxDNS -Parameter @{"IPAddress"="$IPAddress";"VmName"="$VmName"}
$outputmsg = $response1.Value[0].Message
$outputmsg
}
elseif ($use -eq "Modify") {
$response1 = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath $InfloboxModifyDNS -Parameter @{"IPAddress"="$IPAddress";"VmName"="$VmName";"HostName1"="$HostName1"}
$outputmsg = $response1.Value[0].Message
$outputmsg
}
elseif ($use -eq "Modifyip") {
$response1 = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath $InfloboxModifyipDNS -Parameter @{"IPAddress"="$IPAddress";"VmName"="$VmName";"modifyip"="$modifyip"}
$outputmsg = $response1.Value[0].Message
$outputmsg
}
elseif ($use -eq "Delete") {
$response1 = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath $InfloboxDeleteDNS -Parameter @{"IPAddress"="$IPAddress";"VmName"="$VmName"}
$outputmsg = $response1.Value[0].Message
$outputmsg
}
else {
    Write-Host "Invalid action: $use. Choose from: create, update, delete."
}
#if($outputmsg) {
#$output = "Adding TrustAllCertsPolicy type.TrustAllCertsPolicy type added.Record already exists with matching hostname: $($VMName)"
#}
#else{
#	$outputmsg = "No Output returned"
#}
$output = $outputmsg 
    Write-Output @{
        "DeploymentName"    = $deploymentName
        "Outputs"           = $output
		"ProvisioningState" = "Succeeded"

    }
}
Catch {
    # Error handling block
    Write-Output "DNS Record to Infoblox failed due to the following error:"
    Write-Output $_

    Write-Output @{
        "DeploymentName"    = $deploymentName
        "Outputs"           = $_.Exception.Message
        "ProvisioningState" = "Failed"
    }

    # Rethrow the exception
    Throw $_
}
