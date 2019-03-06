#
# Package_BastianServiceFabricApplication.ps1
#

[cmdletbinding()]
param(
	$ApplicationRootPath = "..\..\"
)

$ResolvedPath = Resolve-Path $ApplicationRootPath

Write-Verbose "Application path is [$ResolvedPath]"

$toolsPath = Join-Path $ResolvedPath "tools"
$nugetPath = Join-Path $toolsPath "nuget.exe"
$sln = Join-Path $ResolvedPath "WebReferenceApp.sln"

Write-Verbose "Cleaning solution $sln"

msbuild $sln /target:clean /toolsversion:15.0 /p:Platform=x64 /p:Configuration=Debug

if(-not (test-path $toolsPath))
{
	New-Item -ItemType Directory $toolsPath
}

if(-not (test-path $nugetPath))
{
	Write-Verbose "Downloading nuget to [$nugetPath]"
	$url = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"	
	$wc = [System.Net.WebClient]::new()
	$wc.DownloadFile($url, $nugetPath)
}

Write-Verbose "Restoring nuget packages"

$nugetParams = 'restore', "$ApplicationRootPath\WebReferenceApplication\packages.config", '-PackagesDirectory', "$ApplicationRootPath\packages\"

& $nugetPath $nugetParams

Write-Verbose "Building solution $sln and generating service fabric Application package"

msbuild $sln /target:build /toolsversion:15.0 /p:Platform=x64 /p:Configuration=Debug /p:ForcePackageTarget=true