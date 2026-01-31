$fw_name = "FW"
$rsg_name = "AZ700LABS"

# -------------------------------------------
# Deallocate the firewall
# -------------------------------------------

# 1. Capture the firewall details
$azfw = Get-AzFirewall -Name $fw_name sourceGroupName $rsg_name

# 2. Deallocate the resources
$azfw.Deallocate()

# 3. Apply the change
Set-AzFirewall -AzureFirewall $azfw

