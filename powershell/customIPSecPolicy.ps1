# ==========================================================
# Azure PowerShell Script — Create S2S VPN Connection
# Lab: AZ-700 — VPN Gateway + Local Network Gateway + IPSec
# ==========================================================

# Persist Azure context across PowerShell sessions
Enable-AzContextAutosave -Scope CurrentUser


# ----------------------------------------------------------
# LOGIN — Ensure Azure session exists
# ----------------------------------------------------------
$context = Get-AzContext

if ($null -eq $context) {
    Write-Host "No Azure session found. Opening browser for login..." -ForegroundColor Yellow
    Connect-AzAccount
}
else {
    Write-Host "Azure session already active." -ForegroundColor Green
}


# ----------------------------------------------------------
# CONFIGURATION VARIABLES
# ----------------------------------------------------------
$rgName              = "AZ700LABS"
$localGwName         = "LNG"
$localAddressPrefix  = "10.0.0.0/16"   # On-premises network CIDR
$onPremPublicIpName  = "OnPrem-Router-IP"
$connectionName      = "S2S_CONN"
$sharedKey           = "AzureUser@123"   # ⚠ For labs only — use Key Vault in production


# ----------------------------------------------------------
# FETCH REQUIRED AZURE RESOURCES
# ----------------------------------------------------------

# Get resource group (used for location reference)
$rg = Get-AzResourceGroup -Name $rgName

# Get public IP of on-prem router (simulated device in lab)
$onPremPublicIp = Get-AzPublicIpAddress `
    -Name $onPremPublicIpName `
    -ResourceGroupName $rgName

if ($null -eq $onPremPublicIp) {
    throw "Public IP resource '$onPremPublicIpName' not found."
}

# Get existing Azure VPN Gateway
$vnetGateway = Get-AzVirtualNetworkGateway -ResourceGroupName $rgName

if ($null -eq $vnetGateway) {
    throw "Virtual Network Gateway not found in resource group."
}


# ----------------------------------------------------------
# CREATE LOCAL NETWORK GATEWAY (Represents On-Prem Site)
# ----------------------------------------------------------
# This defines:
# - On-prem address space
# - On-prem public VPN device IP

$localGateway = New-AzLocalNetworkGateway `
    -Name $localGwName `
    -ResourceGroupName $rgName `
    -Location $rg.Location `
    -AddressPrefix $localAddressPrefix `
    -GatewayIpAddress $onPremPublicIp.IpAddress


# ----------------------------------------------------------
# DEFINE CUSTOM IPSec POLICY
# ----------------------------------------------------------
# Explicit IPSec parameters instead of Azure defaults
# Useful for interoperability testing in AZ-700 labs

$ipsecPolicy = New-AzIpsecPolicy `
    -SALifeTimeSeconds 1000 `
    -SADataSizeKilobytes 2000 `
    -IpsecEncryption "GCMAES256" `
    -IpsecIntegrity "GCMAES256" `
    -IkeEncryption "AES256" `
    -IkeIntegrity "SHA256" `
    -DhGroup "DHGroup14" `
    -PfsGroup "PFS2048"


# ----------------------------------------------------------
# CREATE SITE-TO-SITE VPN CONNECTION
# ----------------------------------------------------------
# Connects:
# Azure VPN Gateway  <-->  Local Network Gateway (on-prem)

$connection = New-AzVirtualNetworkGatewayConnection `
    -Name $connectionName `
    -ResourceGroupName $rgName `
    -Location $rg.Location `
    -SharedKey $sharedKey `
    -VirtualNetworkGateway1 $vnetGateway `
    -LocalNetworkGateway2 $localGateway `
    -ConnectionType IPsec `
    -IpsecPolicies $ipsecPolicy `
    -UsePolicyBasedTrafficSelectors $true


# ----------------------------------------------------------
# OUTPUT SUMMARY
# ----------------------------------------------------------
Write-Host "S2S VPN connection created successfully: $connectionName" -ForegroundColor Cyan
