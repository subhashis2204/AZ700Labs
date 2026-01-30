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
$fwpname = 'FWP4'
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
$firewallpolicy = New-AzFirewallPolicy `
                    -Name $fwpname `
                    -ResourceGroupName $rsgname `
                    -Location $location

$getfwpolicy = Get-AzFirewallPolicy -Name $fwpname -ResourceGroupName $rsgname

# -------------------------------------------
# get the pvt ip of the vm for DNAT whitelisting
# -------------------------------------------

$vm_name = 'vm1'
$vm = Get-AzVM -Name $vm_name -ResourceGroupName $rsgname 

$vm_nic_id = $vm.NetworkProfile.NetworkInterfaces[0].Id
$vm_nic = Get-AzNetworkInterface -ResourceId $vm_nic_id

$vm_pvt_ip = $vm_nic.IpConfigurations[0].PrivateIpAddress

# -------------------------------------------
# create DNAT rules for the policy
# -------------------------------------------

$dnat_allow_rdp_vm1 = New-AzFirewallNatRule `
-Name AllowVmDNAT `
-SourceAddress * `
-DestinationAddress 

# -------------------------------------------
# create network rules for the policy
# -------------------------------------------
$nr_allow_eastwest_Vnet1ToHub = New-AzFirewallPolicyNetworkRule `
                                    -Name AllowTrafficFromSpoke1 `
                                    -SourceAddress 10.1.0.0/16 `
                                    -DestinationAddress * `
                                    -DestinationPort * `
                                    -Protocol Any

$nr_allow_eastwest_Vnet2ToHub = New-AzFirewallPolicyNetworkRule `
                                    -Name AllowTrafficFromSpoke2 `
                                    -SourceAddress 10.2.0.0/16 `
                                    -DestinationAddress * `
                                    -DestinationPort * `
                                    -Protocol Any

# -------------------------------------------
# create a filter grp for the created rules
# -------------------------------------------
$rulecollectionconfig = New-AzFirewallPolicyFilterRuleCollection `
                            -Name testing2 `
                            -Priority 500 `
                            -Rule $nr_allow_eastwest_Vnet1ToHub, $nr_allow_eastwest_Vnet2ToHub `
                            -ActionType Allow
$rulecollectionconfig

# -------------------------------------------
# create and retrieve collection grp
# -------------------------------------------
$newrulecollection = New-AzFirewallPolicyRuleCollectionGroup `
                        -Name testing `
                        -Priority 400 `
                        -FirewallPolicyObject $getfwpolicy

$rulecollection = Get-AzFirewallPolicyRuleCollectionGroup -Name testing -AzureFirewallPolicyName $fwpname -ResourceGroupName $rsgname


# -------------------------------------------
# manually add the filter grp to the collection
# -------------------------------------------
$rulecollection.Properties.RuleCollection.Add($rulecollectionconfig)


# -------------------------------------------
# Finally update the collection grp on Azure
# -------------------------------------------
Set-AzFirewallPolicyRuleCollectionGroup -Name testing -FirewallPolicyObject $getfwpolicy -RuleCollection $rulecollection.Properties.RuleCollection -Priority 500


