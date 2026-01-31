# 1. Directly enable the cache (using the universal cmdlet)
Enable-AzContextAutosave -Scope CurrentUser

# 2. Login Logic

$context = Get-AzContext
if ($null -eq $context) {
    Write-Host "Opening browser for login..." -ForegroundColor Yellow
    Connect-AzAccount
}

$rsgname = 'AZ700LABS'
$fwname = 'FW'
$spoke1cidr = '10.1.0.0/16'
$spoke2cidr = '10.2.0.0/16'
$vm_name = 'vm1'
$location = Get-AzResourceGroup -Name $rsgname | Select-Object -ExpandProperty Location

# -------------------------------------------
# retrieve the firewall details
# -------------------------------------------

$fw = Get-AzFirewall -Name $fwname -ResourceGroupName $rsgname -ErrorAction SilentlyContinue

if ($null -eq $fw){
    Write-Host did not get the firewall
    return
}

# -------------------------------------------
# create and retrieve firewall policy
# -------------------------------------------

$firewallpolicy = $fw.FirewallPolicy.Id

$getfwpolicy = Get-AzFirewallPolicy -ResourceId $firewallpolicy

# -------------------------------------------
# get the pvt ip of the vm for DNAT whitelisting
# -------------------------------------------

$vm = Get-AzVM -Name $vm_name -ResourceGroupName $rsgname 

$vm_nic_id = $vm.NetworkProfile.NetworkInterfaces[0].Id
$vm_nic = Get-AzNetworkInterface -ResourceId $vm_nic_id

$vm_pvt_ip = $vm_nic.IpConfigurations[0].PrivateIpAddress

Write-Host "Private ip of vm is", $vm_pvt_ip

# -------------------------------------------
# create DNAT rules for the policy
# -------------------------------------------

$fw_pip_address_rscid = $fw.IpConfigurations[0].PublicIpAddress.Id
$fw_pip_address = Get-AzResource -ResourceId $fw_pip_address_rscid
$fw_pip_name = $fw_pip_address.Name
$fw_pip_rsg = $fw_pip_address.ResourceGroupName

$fw_pip = Get-AzPublicIpAddress -Name $fw_pip_name -ResourceGroupName $fw_pip_rsg

Write-Host "Front end ip of firewall is", $fw_pip.IpAddress

$dnat_allow_rdp_vm1 = New-AzFirewallPolicyNatRule `
                        -Name AllowVmDNAT `
                        -SourceAddress * `
                        -DestinationAddress $fw_pip.IpAddress `
                        -DestinationPort 3389 `
                        -Protocol TCP `
                        -TranslatedAddress $vm_pvt_ip `
                        -TranslatedPort 3389

# -------------------------------------------
# create network rules for east-west traffic
# -------------------------------------------
$nr_allow_eastwest_Vnet1ToHub = New-AzFirewallPolicyNetworkRule `
                                    -Name AllowTrafficFromSpoke1 `
                                    -SourceAddress $spoke1cidr `
                                    -DestinationAddress $spoke2cidr `
                                    -DestinationPort * `
                                    -Protocol Any

$nr_allow_eastwest_Vnet2ToHub = New-AzFirewallPolicyNetworkRule `
                                    -Name AllowTrafficFromSpoke2 `
                                    -SourceAddress $spoke2cidr `
                                    -DestinationAddress $spoke1cidr `
                                    -DestinationPort * `
                                    -Protocol Any

# -------------------------------------------
# create a filter grp for the created network rules
# -------------------------------------------
$rulecollectionconfig_nwk = New-AzFirewallPolicyFilterRuleCollection `  # filter grp for network / application rules
                            -Name NetworkRules `
                            -Priority 500 `
                            -Rule $nr_allow_eastwest_Vnet1ToHub, $nr_allow_eastwest_Vnet2ToHub `
                            -ActionType Allow

# ---------------------------------------------------------------------------------
# create a nat collection grp
# ---------------------------------------------------------------------------------
$rulecollectionconfig_dnat = New-AzFirewallPolicyNatRuleCollection `  # nat grp for dnat / snat rules
                            -Name DnatRules `
                            -Priority 400 `
                            -Rule $dnat_allow_rdp_vm1 `
                            -ActionType Dnat

# ---------------------------------------------------------------------------------
# create and retrieve rule collection
# ---------------------------------------------------------------------------------
$new_nw_rulecollection = New-AzFirewallPolicyRuleCollectionGroup `
                        -Name CustomRuleCollection `
                        -Priority 400 `
                        -FirewallPolicyObject $getfwpolicy

$nw_rulecollection = Get-AzFirewallPolicyRuleCollectionGroup `
                        -Name CustomRuleCollection `
                        -AzureFirewallPolicyName $getfwpolicy.Name `
                        -ResourceGroupName $rsgname


# -------------------------------------------
# manually add the filter and nat grp to the rule collection
# -------------------------------------------
$nw_rulecollection.Properties.RuleCollection.Add($rulecollectionconfig_nwk)
$nw_rulecollection.Properties.RuleCollection.Add($rulecollectionconfig_dnat)

# -------------------------------------------
# Finally update the collection on Azure
# -------------------------------------------
Set-AzFirewallPolicyRuleCollectionGroup -Name CustomRuleCollection -FirewallPolicyObject $getfwpolicy -RuleCollection $nw_rulecollection.Properties.RuleCollection -Priority 200


