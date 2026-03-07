# ==============================================================
# Enable WinRM for Ansible on Windows Server
# Run this script as Administrator on each Windows Server
# ==============================================================

Write-Host "=== Enabling WinRM for Ansible ===" -ForegroundColor Green

# Set network profile to Private (required for WinRM)
$networkProfiles = Get-NetConnectionProfile
foreach ($profile in $networkProfiles) {
    if ($profile.NetworkCategory -ne 'DomainAuthenticated') {
        Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
        Write-Host "Set interface '$($profile.Name)' to Private" -ForegroundColor Yellow
    }
}

# Enable WinRM service
Write-Host "Enabling WinRM service..." -ForegroundColor Yellow
winrm quickconfig -force

# Set WinRM to start automatically
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

# Configure WinRM settings
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service/auth '@{Negotiate="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

# Set MaxEnvelopeSizekb for large data transfers
winrm set winrm/config '@{MaxEnvelopeSizekb="8192"}'

# Set MaxTimeoutms
winrm set winrm/config '@{MaxTimeoutms="1800000"}'

# Configure WinRM listener on HTTP
$listeners = winrm enumerate winrm/config/listener 2>$null
if ($listeners -notmatch "Transport = HTTP") {
    winrm create winrm/config/listener?Address=*+Transport=HTTP
    Write-Host "Created HTTP listener" -ForegroundColor Yellow
}

# Configure firewall rules for WinRM
$firewallRule = Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    New-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" `
        -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any
    Write-Host "Created firewall rule for WinRM HTTP" -ForegroundColor Yellow
} else {
    Enable-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)"
}

# Enable PowerShell remoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Verify WinRM is working
Write-Host ""
Write-Host "=== WinRM Configuration ===" -ForegroundColor Green
winrm get winrm/config/service
Write-Host ""
Write-Host "=== WinRM Listeners ===" -ForegroundColor Green
winrm enumerate winrm/config/listener
Write-Host ""
Write-Host "WinRM is now enabled and configured for Ansible!" -ForegroundColor Green
Write-Host "Test from Ansible: ansible <hostname> -m win_ping" -ForegroundColor Cyan
