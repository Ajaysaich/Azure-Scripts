[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,Position=0)][object]$scriptParams
)

Try
{
    write-output("Inside VM Start/Stop Schedule script")
    $RGSubscription = $scriptParams.Resource_Subscription
    $VMList= $scriptParams.vmlist
    $DeploymentName = "Automation-job-"+ $scriptParams.deploymentName
    $Subscription = $scriptParams.subscription
    $Task=$scriptParams.task
    $Action = $scriptParams.action
    $frequency=$scriptParams.frequency
    $time=$scriptParams.time +" "+ "EST"
    $AutomationAccountName=''
    $AutomationRGName=''

    $context= Set-AzContext -SubscriptionId $RGSubscription
    $RGSubscriptionName = ($context.Subscription.name).replace("/","")
    select-azsubscription -subscriptionid $RGSubscription
    if($frequency -eq "Weekday")
    {
        $tagname="ScheduledWeekday"
        $tagvalue= $time
    }
    elseif($frequency -eq "Weekday(Mon-Thur)")
    {
        $tagname="ScheduledWeekday"
        $tagvalue= $time+"Mon-Thur"
		#$tagvalue= $frequency+'-'+$time
    }
    else
    {
        $tagname="ScheduledWeekend"
        $tagvalue= $frequency+'-'+$time
    }
    $VMs= $VMList.split(",")
    foreach($VM in $VMs)
    {
        $VMName = $VM.split(":")[0]
	$ResourceGroupName = $VM.split(":")[1]
        $id=(Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName).id
        if($frequency -eq "Weekday(Mon-Thur)")
        {
            $scheduleName= "Weekday"+'-'+$time.replace(":","") + '-' + "Action" + '-' + "Mon-Thur" + "-" + "$RGSubscriptionName"
        }
        else
        {
            $scheduleName= $frequency+'-'+$time.replace(":","") + '-' + "Action" + "-" + "$RGSubscriptionName"
        }
		write-output "Schedule name is: $scheduleName"
        if(($Task -eq "ADD") -or ($Task -eq "Modify"))
        {
            if($Action -eq "Start")
            {
                $tagna=$tagname+"StartTime"
                $tags = @{$tagna=$tagvalue}
                Update-AzTag -ResourceId $id -Tag $tags -Operation Merge
                $output+="Tag $tagna has been updated to $tagvalue on $VMName."
            }
            else
            {
                $tagna=$tagname+"StopTime"
                $tags = @{$tagna=$tagvalue}
                Update-AzTag -ResourceId $id -Tag $tags -Operation Merge
                $output+="Tag $tagna has been updated to $tagvalue on $VMName."
            }
        }
        elseif($Task -eq "Remove")
        {
            if($Action -eq "Start")
            {
                $tagna=$tagname+"StartTime"
                $tags = @{$tagna=''}
                Update-AzTag -ResourceId $id -Tag $tags -Operation Merge
                $output+="Tag $tagna has been Removed from $VMName."
            }
            else
            {
                $tagna=$tagname+"StopTime"
                $tags = @{$tagna=''}
                Update-AzTag -ResourceId $id -Tag $tags -Operation Merge
                $output+="Tag $tagna has been Removed from $VMName."
            }

        }
        else
        {
            throw "Task $Task is incorrect"
        }
    }
    #setting context to work on Automation Account
    Set-AzContext -SubscriptionId $Subscription
    select-azsubscription -subscriptionid $Subscription
    if(($Task -eq "ADD") -or ($Task -eq "Modify"))
    {
        $parameter1=$frequency+'-'+$time
        $parameter2 = $RGSubscription
        if($Action -eq "Start"){
            $RunbookName="PS-Action-Start-AzureVMs"
            $parameters= @{"ScheduledStartTime"="$parameter1";"subscription"="$parameter2"}
        }
        else
        {
            $RunbookName="PS-Action-Stop-AzureVMs"
            $parameters= @{"ScheduledStopTime"="$parameter1";"subscription"="$parameter2"}
        }
        $schedCheck=Get-AzAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleName -ResourceGroupName $AutomationRGName -ErrorAction silentlyContinue
        if($schedCheck)
        {
            $output+= "Schedule $scheduleName already present."
        }
        else
        {
            $time1=$scriptParams.time
            $SchedTime = (get-date $time1).AddHours(5)
		
	    $CurrentTime = get-date
	    if($CurrentTime -gt $SchedTime)
		{
			$SchedTime = $SchedTime.AddDays(1)
		}
		#newly added to check time
		$SchedTime1 = get-date -format dd/MM/yyyy
		#$SchedTime=$time
		#newly added to check time
            $TimeZone='Eastern Standard Time'
            if($frequency -eq "Weekday")
            {
                [System.DayOfWeek[]]$WeekDays = @([System.DayOfWeek]::Monday..[System.DayOfWeek]::Friday)
                $CreateScheduleJob=New-AzAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $ScheduleName -StartTime $SchedTime -WeekInterval 1 -DaysOfWeek $WeekDays -TimeZone $TimeZone -ResourceGroupName $AutomationRGName
            }
            elseif($frequency -eq "Weekday(Mon-Thur)")
            {
                [System.DayOfWeek[]]$WeekDays = @([System.DayOfWeek]::Monday..[System.DayOfWeek]::Thursday)
                $CreateScheduleJob=New-AzAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $ScheduleName -StartTime $SchedTime -WeekInterval 1 -DaysOfWeek $WeekDays -TimeZone $TimeZone -ResourceGroupName $AutomationRGName
            }
            else
            {
                [System.DayOfWeek[]]$WeekDays = @([System.DayOfWeek]::$frequency)
                $CreateScheduleJob=New-AzAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $ScheduleName -StartTime $SchedTime -WeekInterval 1 -DaysOfWeek $WeekDays -TimeZone $TimeZone -ResourceGroupName $AutomationRGName
            }
            if ($CreateScheduleJob.Provisioningstate -eq 'Failed')
            {
				throw $CreateScheduleJob.Outputs
			}
			else
			{
                Register-AzAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -Name $RunbookName -ScheduleName $scheduleName -Parameters $parameters -ResourceGroupName $AutomationRGName
				$output+= "Schedule $scheduleName Created and linked to $RunbookName."

			}

        }

        ######### Checking Whether Runbook is Linked to Schedule or not #########
        $checkLink= Get-AzAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $AutomationRGName -ScheduleName $scheduleName -ErrorAction SilentlyContinue
        if($checkLink)
        {
            if($checkLink.RunbookName -eq $RunbookName)
            {
            $output+= "Schedule $scheduleName is linked to $RunbookName."
            }
        }
        else
        {
            Register-AzAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -Name $RunbookName -ScheduleName $scheduleName -Parameters $parameters -ResourceGroupName $AutomationRGName
            $checkLink1= Get-AzAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $AutomationRGName -ScheduleName $scheduleName -ErrorAction SilentlyContinue
            if($checkLink1)
            {
                if($checkLink1.RunbookName -eq $RunbookName)
                {
                $output+= "Schedule $scheduleName is Successfully linked to $RunbookName."
                }
            }
            else
            {
                throw "Failed to Link Schedule $scheduleName to $RunbookName. "
            }

        }
    }

    elseif($Task -eq "Remove")
    {
        Write-output("Tags already Removed from VMs")
    }
    else
    {
        throw "Task $Task is incorrect"
    }

	# Print the deployment result
	Write-Output  @{
	"DeploymentName"    = $deploymentName
	"Outputs"           = $output
	"Provisioningstate" = "Succeeded"
	}
}
Catch
{
    <#-------------------------------[ ERROR HANDLING ]-----------------------------------------#>

    Write-Output "Error caught in VM Start/Stop Schedule Script:"
    Write-Output $_
    Write-Output @{
        "DeploymentName" = $deploymentName
        "Outputs" = $_.Exception.Message
        "Provisioningstate" = "Failed"
    }
    Throw $_
}
