#
# Remove_BastianServiceFabricApplication.ps1
#
[CmdletBinding()]
param(
	[string]$AppName,
	[string]$AppTypeName,
	[string]$AppTypeVersion,
	[string]$ClusterAddress = "127.0.0.1:19000",
	[switch]$UnregisterApplicationType,
	[switch]$ForceRemove,
	[int]$TimeoutSec = 30
)

Write-Verbose "Connecting to Service Fabric cluster at [$ClusterAddress]"

#Create a connection to the cluster. Can't perform any admin operations without this
Connect-ServiceFabricCluster -ConnectionEndpoint $ClusterAddress

Write-Verbose "Removing Service Fabric application [$AppName]"

$RemoveServiceFabricApplicationArgs = @{
	ApplicationName = $AppName
	TimeoutSec = $TimeoutSec
	ForceRemove = $ForceRemove
	Force = $true
}

Remove-ServiceFabricApplication @RemoveServiceFabricApplicationArgs



if($UnregisterApplicationType)
{
	Write-Verbose "Unregistering application type [$AppTypeName] with version [$AppTypeVersion]"

	$UnregisterServiceFabricApplicationTypeArgs = @{
		ApplicationTypeName = $AppTypeName
		ApplicationTypeVersion = $AppTypeVersion
		Force = $true
		Async = $true		
	}

	Unregister-ServiceFabricApplicationType @UnregisterServiceFabricApplicationTypeArgs

	while($true)
	{
		$appType = Get-ServiceFabricApplicationType -ApplicationTypeName $AppTypeName -ApplicationTypeVersion $AppTypeVersion
		$status = $app.Status

		Write-Verbose "Status of application type [$AppTypeName] with version [$AppTypeVersion] is [$Status]"

		if($status -eq $null)
		{
			break;
		}
		else
		{
			Start-Sleep -Seconds 1
		}

	}
}