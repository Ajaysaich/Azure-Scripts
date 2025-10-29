# Import data from the CSV file
$inputfile = "C:\Users\tchirru\Downloads\AzureVirtualMachines (11).csv"
$inputdata = Import-Csv -Path $inputfile

# Initialize an empty array to store details from all VMs
$allSpaceDetails = @()

# Get all subscriptions
$subscriptions = Get-AzSubscription

foreach ($subscription in $subscriptions) {
    # Set the Azure context to the current subscription
    Set-AzContext -Subscription $subscription.Id

    # Get all VMs in the current subscription
    $vms = Get-AzVM

    foreach ($vmDetails in $inputdata) {
        $vmName = $vmDetails.NAME

        # Filter the VMs based on the VM name
        $vm = $vms | Where-Object { $_.Name -eq $vmName }

        if ($vm) {
            # Specify the script path
            $scriptPath = "C:\Users\tchirru\Documents\show proxy.ps1"

            # Invoke the RunPowerShellScript command
            $spacedetails = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Verbose

            # Extract relevant details from the output
            $s = $spacedetails.Value[0].Message

            # Extract proxy and bypass information using regex or string manipulation
            $proxy = ($s -split "`n" | Where-Object { $_ -like "*Proxy Server*" }) -replace ".*Proxy Server\(s\)\s*:\s*", ""
            $bypassList = ($s -split "`n" | Where-Object { $_ -like "*Bypass List*" }) -replace ".*Bypass List\s*:\s*", ""

            # Get VM location, OS type, and private IP address
            $location = $vm.Location
            $osType = $vm.StorageProfile.OsDisk.OsType
            $privateIP = (Get-AzNetworkInterface -ResourceGroupName $vm.ResourceGroupName -Name $vm.NetworkProfile.NetworkInterfaces[0].Id.Split('/')[-1]).IpConfigurations.PrivateIpAddress

            # Create a custom object with required details
            $details = [PSCustomObject]@{
                VMName         = $vm.Name
                ResourceGroup  = $vm.ResourceGroupName
                Location       = $location
                OSType         = $osType
                PrivateIP      = $privateIP
                Proxy          = $proxy.Trim()
                BypassList     = $bypassList.Trim()
            }

            # Append the details to the array
            $allSpaceDetails += $details
        }
    }
}

# Export all VM details to a CSV file
$allSpaceDetails | Export-Csv -Path "C:\Users\tchirru\Documents\AzureVirtualMachines2024(11).csv" -NoTypeInformation

Write-Host "VM details exported to C:\Users\tchirru\Documents\AzureVirtualMachines2024(11).csv"
