# 1. Directly enable the cache (using the universal cmdlet)
Enable-AzContextAutosave -Scope CurrentUser

# 2. Login Logic

$context = Get-AzContext
if ($null -eq $context) {
    Write-Host "Opening browser for login..." -ForegroundColor Yellow
    Connect-AzAccount
}

$rsgname = 'AZ700LABS'
$fwpname = 'FWP6'
$location = Get-AzResourceGroup -Name $rsgname | Select-Object -ExpandProperty Location

# -------------------------------------------
# create and retrieve firewall policy
# -------------------------------------------
$firewallpolicy = New-AzFirewallPolicy `
                    -Name $fwpname `
                    -ResourceGroupName $rsgname `
                    -Location $location

$getfwpolicy = Get-AzFirewallPolicy -Name $fwpname -ResourceGroupName $rsgname

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
                            -Name NetworkRules `
                            -Priority 500 `
                            -Rule $nr_allow_eastwest_Vnet1ToHub, $nr_allow_eastwest_Vnet2ToHub `
                            -ActionType Allow


# -------------------------------------------
# create and retrieve collection grp
# -------------------------------------------
$newrulecollection = New-AzFirewallPolicyRuleCollectionGroup `
                        -Name CustomRuleCollection `
                        -Priority 400 `
                        -FirewallPolicyObject $getfwpolicy

$rulecollection = Get-AzFirewallPolicyRuleCollectionGroup -Name CustomRuleCollection -AzureFirewallPolicyName $fwpname -ResourceGroupName $rsgname


# -------------------------------------------
# manually add the filter grp to the collection
# -------------------------------------------
$rulecollection.Properties.RuleCollection.Add($rulecollectionconfig)


# -------------------------------------------
# Finally update the collection grp on Azure
# -------------------------------------------
Set-AzFirewallPolicyRuleCollectionGroup -Name CustomRuleCollection -FirewallPolicyObject $getfwpolicy -RuleCollection $rulecollection.Properties.RuleCollection -Priority 400


