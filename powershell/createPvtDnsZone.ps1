Enable-AzContextAutosave -Scope CurrentUser

# ------------------------------------------
# Login Logic
# ------------------------------------------
$context = Get-AzContext

if ($null -eq $context) {
    Write-Host "Opening browser for login..." -ForegroundColor Yellow
    Connect-AzAccount
}


# ------------------------------------------
# Variables
# ------------------------------------------
$rsg_name = 'AZ700LABS'
$dns_name = 'subhashis.internal'


# ------------------------------------------
# Create Private DNS Zone (Delete if exists)
# ------------------------------------------
$pvt_dns = Get-AzPrivateDnsZone `
    -Name $dns_name `
    -ResourceGroupName $rsg_name `
    -ErrorAction SilentlyContinue

if ($null -ne $pvt_dns) {

    Get-AzPrivateDnsVirtualNetworkLink `
        -ZoneName $dns_name `
        -ResourceGroupName $rsg_name |
        Remove-AzPrivateDnsVirtualNetworkLink -Confirm:$false

    Remove-AzPrivateDnsZone -PrivateZone $pvt_dns

    $new_pvt_dns = New-AzPrivateDnsZone `
        -Name $dns_name `
        -ResourceGroupName $rsg_name

    $pvt_dns = Get-AzPrivateDnsZone `
        -Name $dns_name `
        -ResourceGroupName $rsg_name `
        -ErrorAction SilentlyContinue
}


# ------------------------------------------
# Get all VNets in the resource group
# ------------------------------------------
$vnets = Get-AzVirtualNetwork -ResourceGroupName $rsg_name


# ------------------------------------------
# Link VNets to Private DNS Zone
# ------------------------------------------
foreach ($vnet in $vnets) {

    $link_name = "linkzone$($vnet.Name)"

    $vnet_id = Get-AzVirtualNetwork `
        -Name $vnet.Name `
        -ResourceGroupName $rsg_name

    New-AzPrivateDnsVirtualNetworkLink `
        -ResourceGroupName $rsg_name `
        -ZoneName $dns_name `
        -Name $link_name `
        -VirtualNetworkId $vnet_id.Id `
        -EnableRegistration 
}


# ------------------------------------------
# Manually add A record set
# ------------------------------------------
# A record set can contain multiple IPs.
# DNS may return any one of them to the client.

$records = @()

$records += New-AzPrivateDnsRecordConfig -Ipv4Address 10.100.1.1
$records += New-AzPrivateDnsRecordConfig -Ipv4Address 10.100.1.2

New-AzPrivateDnsRecordSet `
    -Name "www" `
    -ZoneName $dns_name `
    -ResourceGroupName $rsg_name `
    -Ttl 3600 `
    -RecordType A `
    -PrivateDnsRecord $records
