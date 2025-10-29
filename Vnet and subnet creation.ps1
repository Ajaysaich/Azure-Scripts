
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,Position=0)][object]$scriptParams
) 

try{
# Define VNet details
$deploymentName= $scriptparams.deploymentname
$requestforcreation= $scriptparams.requestforcreation
$subscriptionId = $scriptparams.Res_subscription
$subofPeeringvnet= $scriptparams.subofPeeringvnet
$PeeringvnetName = $scriptparams.PeeringvnetName
$PeeringvnetResourceGroupname = $scriptparams.PeeringvnetResourceGroupname
$newSubnetName = $scriptparams.newSubnetName
$newSubnetAddressPrefix = $scriptparams.newSubnetAddressPrefix
$routetableandNSG= $scriptparams.routetableandNSG
$RouteTableName= $scriptparams.RouteTableName
$NSGName= $scriptparams.NSGName
$resourceGroupName = $scriptparams.resourceGroupName
$vnetName = $scriptparams.vnetName
$vnetAddressPrefix = $scriptparams.vnetAddressPrefix
$location= $scriptparams.location
$dnsenable= $scriptparams.dnsenable
$dnsserer1= $scriptparams.dnsserer1
$dnsserer2= $scriptparams.dnsserer2


if($requestforcreation -eq "Vnet Creation")
{

# Set your subscription
Select-AzSubscription -SubscriptionId $subscriptionId
 
# Create VNet
$vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name $vnetName -AddressPrefix $vnetAddressPrefix
$vnet # display selected Vnet

#DNS Addition
if($dnsenable -eq 'Yes')
{
$dnsserver=@("$dnsserer1","$dnsserer2")
$vnet.DhcpOptions.DnsServers=$dnsserver
Set-AzVirtualNetwork -VirtualNetwork $vnet
}
if($routetableandNSG -eq "Yes"){
#Route table and NSG Details
$RouteTable= Get-AzRouteTable -Name $RouteTableName
$NetworkSecurityGroup= Get-AzNetworkSecurityGroup -Name $NSGName
if($RouteTable -ne $null -and $NetworkSecurityGroup -ne $null)
{
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix -NetworkSecurityGroup $NetworkSecurityGroup -RouteTable $RouteTable
}
if($RouteTable -eq $null -or $RouteTableName -eq "-- None --")
{
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix -NetworkSecurityGroup $NetworkSecurityGroup
}
if($NetworkSecurityGroup -eq $null -or $NSGName -eq "-- None --")
{
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix -RouteTable $RouteTable
}

}
else
{
# Add a new subnet
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix
}

# Update the VNet with the new subnet
Set-AzVirtualNetwork -VirtualNetwork $vnet
 
# Display updated subnets
$vnet.Subnets

$vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName

# Set your subscription
Select-AzSubscription -SubscriptionId $subofPeeringvnet
$Peeringvnet = Get-AzVirtualNetwork -Name $PeeringvnetName -ResourceGroupName $PeeringvnetResourceGroupname

# Create peering from Peeringvnet to New VNet
$namepeering1=$PeeringvnetName+"-"+$vnetName
Add-AzVirtualNetworkPeering -Name $namepeering1 -VirtualNetwork $Peeringvnet -RemoteVirtualNetworkId $vnet.Id

Select-AzSubscription -SubscriptionId $subscriptionId
# Create peering from New VNet to Peeringvnet
$namepeering2=$vnetName+"-"+$PeeringvnetName
Add-AzVirtualNetworkPeering -Name $namepeering2 -VirtualNetwork $vnet -RemoteVirtualNetworkId $Peeringvnet.Id

$outputmessage= "Vnet with Name $vnetName along with all requested configuration is successfully created. "

}
else
{
	
Select-AzSubscription -SubscriptionId $subofPeeringvnet
# Get existing VNet details
$vnet = Get-AzVirtualNetwork -ResourceGroupName $PeeringvnetResourceGroupname -Name $PeeringvnetName
Write-Output "Exisitng Vnet Details"
$vnet # display selected Vnet
 
# Display existing subnets
Write-Output "Exisitng Subnet Details"
$vnet.Subnets

if($routetableandNSG -eq "Yes"){
#Route table and NSG Details
$RouteTable= Get-AzRouteTable -Name $RouteTableName
Write-Output "Route Table Details"
$RouteTable
$NetworkSecurityGroup= (Get-AzNetworkSecurityGroup -Name $NSGName)[0]
Write-Output "NSG Details"
$NetworkSecurityGroup
if($RouteTable -ne $null -and $NetworkSecurityGroup -ne $null)
{
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix -NetworkSecurityGroup $NetworkSecurityGroup -RouteTable $RouteTable
}
if($RouteTable -eq $null -or $RouteTableName -eq "-- None --")
{
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix -NetworkSecurityGroup $NetworkSecurityGroup
}
if($NetworkSecurityGroup -eq $null -or $NSGName -eq "-- None --")
{
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix -RouteTable $RouteTable
}
}
else
{
# Add a new subnet
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddressPrefix
}
# Update the VNet with the new subnet
Set-AzVirtualNetwork -VirtualNetwork $vnet
 
# Display updated subnets
$vnet.Subnets

$outputmessage= "Subnet with name $newSubnetName is Successfully created in $PeeringvnetName "

}

# Print the deployment result
	Write-Output  @{
	"DeploymentName"    = $deploymentName
	"Outputs"           = $outputmessage
	"Provisioningstate" = "Succeeded"
	}
}
Catch {
    
      # Write-Output "Error Occurred in scheduling runbook Script:"
         Write-Output  $_ 

      # Print the error result
        Write-Output  @{
        "DeploymentName"    = $deploymentName
        "Outputs"           = $_.Exception.Message
        "Provisioningstate" = "Failed"
        }
}
