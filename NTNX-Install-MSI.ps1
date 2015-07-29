############################################################
##
## Function: NTNX-Install-MSI
## Author: Steven Poitras
## Description: Automate bulk MSI installation
## Language: PowerShell
##
############################################################
function NTNX-Install-MSI {
<#
.NAME
	NTNX-Install-MSI
.SYNOPSIS
	Installs Nutanix package to Windows hosts
.DESCRIPTION
	Installs Nutanix package to Windows hosts
.NOTES
	Authors:  thedude@nutanix.com
	
	Logs: C:\Users\<USERNAME>\AppData\Local\Temp\NutanixCmdlets\logs
.LINK
	www.nutanix.com
.EXAMPLE
    NTNX-Install-MSI -installer "Nutanix-VirtIO-1.0.0.msi" `
		-cert "NutanixSoftware.cer" -localPath "C:\" `
		-computers $compArray -credential $(Get-Credential)
		
	NTNX-Install-MSI -installer "Nutanix-VirtIO-1.0.0.msi" `
		-cert "NutanixSoftware.cer" -localPath "C:\" `
		-computers "99.99.99.99"
#> 
	Param(
		[parameter(mandatory=$true)]$installer,
		
		[parameter(mandatory=$true)]$cert,
		
		[parameter(mandatory=$false)][AllowNull()]$localPath,
		
		[parameter(mandatory=$true)][Array]$computers,
		
		[parameter(mandatory=$false)][AllowNull()]$credential
	)

	begin{
		# Pre-req message
		Write-host "NOTE: the following pre-requisites MUST be performed / valid before script execution:"
		Write-Host "	+ Nutanix installer must be downloaded and installed locally"
		Write-Host "	+ Export Nutanix Certificate in Trusted Publishers / Certificates"
		Write-Host "	+ Both should be located in c:\"
				
		$input = Read-Host "Do you want to continue? [Y/N]:"
				
		if ($input -ne 'y') {
			break
		}
		
		if ($(Get-ExecutionPolicy) -ne 'Unrestricted') {
			Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force -Confirm:$false
		}
		
		# Import modules and add snappins
		Import-Module DnsClient
		Add-PSSnapin NutanixCmdletsPSSnapin -ErrorAction SilentlyContinue

		# Installer and cert filenames
		if ([string]::IsNullOrEmpty($localPath)) {
			# Assume location is c:\
			$localPath = 'c:\'
		}
		
		# Credential for remote PS connection
		if (!$credential) {
			$credential = Get-Credential
		}
		
		# Path for ADMIN share used in transfer
		$adminShare = "C:\Windows\"
		
		# Format paths
		$localInstaller = $(Join-Path $localPath $installer)
		$localCert = $(Join-Path $localPath $cert)
		$remoteInstaller = $(Join-Path $adminShare $installer)
		$remoteCert = $(Join-Path $adminShare $cert)
	
	}
	process {
		# For each computer copy file and install drivers
		$computers | %	{
			# Create a new PS Drive
			New-PSDrive -Name P -PSProvider FileSystem -Root \\$_\ADMIN$ `
				-Credential $credential
			
			# Copy virtio installer
			Copy-Item  $localInstaller P:\$installer
			
			# Copy Nutanix cert
			Copy-Item $localCert P:\$cert
			
			# Create PS Session
			$sessionObj = New-PSSession -ComputerName $_ -Credential $credential
			
			# Install certificate for signing
			Invoke-Command -session $sessionObj -ScriptBlock {
				certutil -addstore "TrustedPublisher" $args[0]
			} -Args $remoteCert
			
			# Install driver silently
			$installResponse = Invoke-Command -session $sessionObj -ScriptBlock {
				$status = Start-Process -FilePath "msiexec.exe"  -ArgumentList `
					$args[0] -Wait -PassThru
				
				return $status
			} -Args "/i $remoteInstaller /qn"
			
			if ($installResponse.ExitCode -eq 0) {
				Write-Host "Installation of Nutanix package succeeded!"
			} else {
				Write-Host "Installation of Nutanix package failed..."
			}
			
			# Cleanup PS drive
			Remove-PSDrive -Name P
		
			# Cleanup session
			Disconnect-PSSession -Session $sessionObj | Remove-PSSession
		}
	
	}
	end {
		
	}
}