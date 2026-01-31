$fw_name = "FW"
$rsg_name = "AZ700LABS"
$vnet_name = "vnet0"
$pip_name = "FWIP"

# -------------------------------------------
# reallocate the firewall
# -------------------------------------------

# 1. Get the resources
$azfw = Get-AzFirewall -Name $fw_name -ResourceGroupName $rsg_name
$vnet = Get-AzVirtualNetwork -Name $vnet_name -ResourceGroupName $rsg_name
$pip = Get-AzPublicIpAddress -Name $pip_name -ResourceGroupName $rsg_name

# 2. Re-allocate (Assigning it back to the subnet/IP)
$azfw.Allocate($vnet, $pip)

# 3. Start the firewall
Set-AzFirewall -AzureFirewall $azfw