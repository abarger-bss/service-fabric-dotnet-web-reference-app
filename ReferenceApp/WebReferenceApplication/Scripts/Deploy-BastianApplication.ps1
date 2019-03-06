<#

.SYNOPSIS
This is a Powershell script to deploy the Bastian.LogHub application to a Service Fabric cluster.

.DESCRIPTION
This script handles the initial deployment of the application, and allows for initial setup values to be provided for the
various services that this application hosts. This script is intended to make deployment easier, but at the end of the day
its just invoking various Cmdlets in the Service Fabric Powershell Module.

.PARAMETER PackagePath
Path to the package to deploy.

.PARAMETER AppName
Fabric application name to deploy application as, for example, 'fabric:/MyApp'.

.PARAMETER ClusterAddress
Address of the cluster to connect to. Make sure to include the port. Usually the default is 19000.

.PARAMETER Thumbprint
Thumbprint of the certificate to use to connect to the ClusterAddress. Specifying this parameter requires CommonName to also be specified.

.PARAMETER CommonName
CommonName of the certificate to use to connect to the ClusterAddress. Specifying this parameter requires Thumbprint to also be specified.

.PARAMETER ImageStoreConnectionString
Connection string for the image store when uploading the package to the cluster. Leaving this blank will allow the script to choose an appropriate default.
More information can be found here: https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-image-store-connection-string

.PARAMETER ImageStorePackagePath
More information can be found here: https://docs.microsoft.com/en-us/powershell/module/servicefabric/copy-servicefabricapplicationpackage?view=azureservicefabricps

.PARAMETER DevCluster
Indicates whether or not the application is being deployed to a development Service Fabric cluster. If used, changes the ImageStoreConnectionString
to point to the SFDev image store. Be sure to use this switch when deploying locally, otherwise the application package will fail to copy to the 
image store with vague errors like "Service does not exist"

.PARAMETER WebServiceArguments
The arguments that will be used with the New-ServiceFabricService Cmdlet to create the Bastian.ServiceFabric.IntegrationTest.WebService.

.PARAMETER DataServiceArguments
The arguments that will be used with the New-ServiceFabricService Cmdlet to create the Bastian.ServiceFabric.IntegrationTest.DataService.

.PARAMETER ActorServiceArguments
The arguments that will be used with the New-ServiceFabricService Cmdlet to create the Bastian.ServiceFabric.IntegrationTest.ActorService.

.LINK
https://docs.microsoft.com/en-us/powershell/module/servicefabric/?view=azureservicefabricps

#>

[CmdletBinding()]
Param(
	[string]$PackagePath = "./pkg",
	[string]$AppName = "fabric:/WebReferenceApp",
	[string]$AppTypeName = "WebReferenceApplicationType",
	[string]$AppVersion = "1.0.0",
	[string]$ClusterAddress = "127.0.0.1:19000",
	[string]$ImageStoreConnectionString = "fabric:ImageStore",
	[string]$ImageStorePackagePath = "WebReferenceApp",
	[switch]$DevCluster,
	[HashTable]$CustomerOrderActorServiceArgs = @{
													ServiceTypeName = "CustomerOrderActorServiceType"
													Stateful = $true													
													ApplicationName = $AppName
													ServiceName = "$AppName/CustomerOrderActorService"
													PartitionSchemeUniformInt64 = $true
													LowKey = "-9223372036854775808"
													HighKey = "9223372036854775807"
													PartitionCount = 2
													MinReplicaSetSize = 1
													TargetReplicaSetSize = 1
												 },
	[HashTable]$InventoryServiceArgs = @{
											ServiceTypeName = "InventoryServiceType"
											Stateful = $true
											HasPersistedState = $true
											ApplicationName = $AppName
											ServiceName = "$AppName/InventoryService"
											PartitionSchemeUniformInt64 = $true
											LowKey = "-9223372036854775808"
											HighKey = "9223372036854775807"
											PartitionCount = 2
											MinReplicaSetSize = 1
											TargetReplicaSetSize = 1
										},
	[HashTable]$RestockRequestActorServiceArgs = @{
												      ServiceTypeName = "RestockRequestActorServiceType"
													  Stateful = $true													  
													  ApplicationName = $AppName
													  ServiceName = "$AppName/RestockRequestActorService"
													  PartitionSchemeUniformInt64 = $true
													  LowKey = "-9223372036854775808"
													  HighKey = "9223372036854775807"
													  PartitionCount = 2
													  MinReplicaSetSize = 1
													  TargetReplicaSetSize = 1
												  },
	[HashTable]$RestockRequestManagerServiceArgs = @{
														ServiceTypeName = "RestockRequestManagerServiceType"
														Stateful = $true
														HasPersistedState = $true
														ApplicationName = $AppName
														ServiceName = "$AppName/RestockRequestManager"
														PartitionSchemeSingleton = $true														
														MinReplicaSetSize = 1
														TargetReplicaSetSize = 1
													},
	[HashTable]$WebServiceArgs = @{
								      ServiceTypeName = "WebServiceType"
									  Stateless = $true
									  ApplicationName = $AppName
									  ServiceName = "$AppName/WebService"
									  PartitionSchemeSingleton = $true
									  InstanceCount = 1
								  }
)

if($DevCluster) {
	$ImageStoreConnectionString = "file:C:\SfDevCluster\Data\ImageStoreShare"
}

Write-Host "Targeting image store at $ImageStoreConnectionString"

if($ClusterAddress.Contains("127.0.0.1") -and (-not $DevCluster)) {
	Write-Warning "Detected local deployment without use of the -DevCluster switch. If deploying to a Service Fabric development cluster, use the -DevCluster switch to choose the correct image store connection string"
}

Write-Verbose "Connecting to Service Fabric cluster at [$ClusterAddress]"

#Create a connection to the cluster. Can't perform any admin operations without this
Connect-ServiceFabricCluster -ConnectionEndpoint $ClusterAddress

Write-Verbose "Testing application package"
#Validates app package against packaging requirements and existing packages in the image store
Test-ServiceFabricApplicationPackage -ApplicationPackagePath $PackagePath -ImageStoreConnectionString $ImageStoreConnectionString

Write-Verbose "Copying application package to image store [$ImageStoreConnectionString] under Image Store package path [$ImageStorePackagePath]"

$CopyServiceFabricApplicationPackageArgs = @{
	ApplicationPackagePath = $PackagePath
	ImageStoreConnectionString = $ImageStoreConnectionString
	ApplicationPackagePathInImageStore = $ImageStorePackagePath
	CompressPackage = $true
	ShowProgress = $true
}

#Copy the package to the image store service so it can be deployed to all nodes in the cluster.
Copy-ServiceFabricApplicationPackage @CopyServiceFabricApplicationPackageArgs

Write-Verbose "Registering application type under image store package path [$ImageStorePackagePath]"
#Provisions an application type based on what was copied to the image store
Register-ServiceFabricApplicationType -ApplicationPathInImageStore $ImageStorePackagePath -Async

#Wait until provisioning is complete to proceed
while($true)
{
	$app = Get-ServiceFabricApplicationType -ApplicationTypeName $AppTypeName
	$status = $app.Status;

	Write-Verbose "Current status for application type [$AppTypeName] is [$Status]"

	if($status -eq "Available")
	{
		break
	}
	elseif ($status -eq "Failed")
	{
		$statusDetails = $app.StatusDetails;
		throw "Registering application type [$AppTypeName] failed with details [$statusDetails]"
	}
	else
	{		
		Start-Sleep -Seconds 2
	}
}

#Cleans up artifacts in the image store
Write-Verbose "Removing Application Package under Image Store Package Path [$ImageStorePackagePath]"
Remove-ServiceFabricApplicationPackage -ImageStoreConnectionString $ImageStoreConnectionString -ApplicationPackagePathInImageStore $ImageStorePackagePath

Write-Verbose "Creating new application instance of version [$AppVersion] of type [$AppTypeName] with instance name [$AppName]"
New-ServiceFabricApplication -ApplicationName $AppName -ApplicationTypeName $AppTypeName -ApplicationTypeVersion $AppVersion

$services = ($CustomerOrderActorServiceArgs, $InventoryServiceArgs, $RestockRequestActorServiceArgs, $RestockRequestManagerServiceArgs, $WebServiceArgs)

#Add service instances to our application instance.
foreach($serviceArgs in $services)
{
	New-ServiceFabricService @serviceArgs
}