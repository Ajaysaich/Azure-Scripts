$privateip = $args[1]
$privateip
$Domain = $args[3]
$Domain
$Environment = $args[5]
$Environment
$VMName = $args[7]
$VMName

#I#nstall-Module -Name SwisPowerShell -RequiredVersion 
$hostname = ""
$username = "swautomation"
$password = "" 
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -argumentlist($username, $securePassword)
$swis = Connect-Swis -host $hostname -Credential $cred

$ip = $privateip
$VMName = $VMName

#Checking the Node 
$existingNode = Get-SwisData $swis "
    SELECT NodeID, SysName, IPAddress FROM Orion.Nodes
    WHERE IPAddress = '$ip'"

if ($existingNode) {
    Write-Host "Node with IP $ip already exists (NodeID: $($existingNode.NodeID))"
} else {
    Write-Host "IP $ip not found. Proceeding to create a new node..."
}
#Getting the Credential ID
$credentialName = "SAM" 
$credentialId = Get-SwisData $swis "SELECT ID FROM Orion.Credential where Name = '$credentialName'"
if (!$credentialId) {
	Throw "Can't find the Credential with the provided Credential name '$credentialName'."
}
$credentialId
Start-Sleep 10
# Polling engines
$engines = Get-SwisData $swis "SELECT EngineID, ServerName, IP From Orion.Engines"
$engines | Format-Table -AutoSize
$engines.EngineID

if ($ip -match "^10\.94|^10\.91|^10\.90") {
    $selectedEngineID = 11
}
elseif ($ip -match "^10\.121|^10\.1|^10\.51") {
    $selectedEngineID = 13
}
elseif ($ip -match "^10\.240|^10\.135|^10\.100|^10\.93|^10\.213|^10\.10|^10\.82|^10\.218|^10\.84|^10\.136|^10\.96|^10\.92|^10\.132|^10\.128") {
    $selectedEngineID = 12
}
else {
    $selectedEngineID = 11
}
Write-Output "Selected EngineID: $selectedEngineID"

$newNodeProps = @{
    IPAddress = $ip
    EngineID = $selectedEngineID
    Caption = $VMName 
    ObjectSubType = "WMI"
    DNS = "$VMName.$Domain"
    SysName = "$VMName"
    EntityType = 'Orion.Nodes'    
}
$newNodeUri = New-SwisObject $swis -EntityType "Orion.Nodes" -Properties $newNodeProps
$nodeProps = Get-SwisObject $swis -Uri $newNodeUri 
$nodeuri = $nodeProps.Uri
$nodeuri
Write-Output "Created the Node successfully Under the nodeUri: $nodeuri"

Start-Sleep 10
#Adding NodeSettings
$nodeSettings = @{
    NodeID = $nodeProps["NodeID"]
    SettingName = "WMICredential"
    SettingValue = ($credentialId.ToString())
}
#Creating node settings
$newNodeSettings = New-SwisObject $swis -EntityType "Orion.NodeSettings" -Properties $nodeSettings
$pollerTypes = @(
    "N.Status.ICMP.Native",
    "N.ResponseTime.ICMP.Native",
    "N.Details.WMI.Vista",
    "N.Uptime.WMI.XP",
    "N.Cpu.WMI.Windows",
    "N.Memory.WMI.Windows",
    "N.AssetInventory.Wmi.Generic"
)
foreach ($pollerType in $pollerTypes) {
    $poller = @{
        NetObject = "N:" + $nodeProps["NodeID"]
        NetObjectType = "N"
        NetObjectID = $nodeProps["NodeID"]
        PollerType = $pollerType
        Enabled = $true 
    }
    # Create the poller in an enabled state
    $pollerUri = New-SwisObject $swis -EntityType "Orion.Pollers" -Properties $poller
    Write-Host "Created and enabled poller: $pollerType"
}
Start-Sleep 30
Invoke-SwisVerb -SwisConnection $swis -EntityName "Orion.Nodes" -Verb "PollNow" -Arguments "("N:" + $nodeProps["NodeID"])"  
#Invoke-SwisVerb $swis Orion.Nodes PollNow @("N:" + $nodeProps["NodeID"])
#Nodeid
$nodeid = $nodeProps.NodeID
$nodeid
Write-Output "Succeessfully Created and enabled pollers under the NodeID : $nodeid"
$customProperties = @{
    "Environment" = "$Environment" #PROD,QA,Dev
}  
#$swisuri = "swis://$($hostname)/Orion/Orion.Nodes/NodeID=$($nodeId)/CustomProperties"
Set-SwisObject $swis -Uri "swis://$($hostname)/Orion/Orion.Nodes/NodeID=$($nodeId)/CustomProperties" -Properties $customProperties
Start-Sleep 10
Write-Output "Successfully Added the Environment to the Node"


