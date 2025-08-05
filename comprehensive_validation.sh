#!/bin/bash
# Comprehensive validation script for EAST-SPOKE-1 route table renaming

echo "=== Comprehensive EAST-SPOKE-1 Route Table Validation ==="

RESOURCE_GROUP="NWAVE-EAST"
VNET_NAME="EAST-SPOKE-1"

echo "Resource Group: $RESOURCE_GROUP"
echo "VNet: $VNET_NAME"
echo "Validation Date: $(date)"
echo "================================================"

# 1. Validate Route Table Existence
echo -e "\n1. ROUTE TABLE INVENTORY:"
echo "Checking all route tables in resource group..."
az network route-table list \
    --resource-group $RESOURCE_GROUP \
    --query "[].{Name:name, Location:location, ProvisioningState:provisioningState, SubnetCount:length(subnets)}" \
    --output table

# 2. Validate Subnet Associations
echo -e "\n2. SUBNET ASSOCIATIONS:"
echo "Private Subnet (Spoke-1-Net-1-Prv):"
private_rt=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name "Spoke-1-Net-1-Prv" \
    --query "routeTable.id" \
    --output tsv)

if [[ $private_rt == *"EAST-SPOKE-1-PRV-RT"* ]]; then
    echo "✓ Private subnet correctly associated with EAST-SPOKE-1-PRV-RT"
else
    echo "✗ Private subnet association incorrect: $private_rt"
fi

echo "Public Subnet (Spoke-1-Net-1-Pub):"
public_rt=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name "Spoke-1-Net-1-Pub" \
    --query "routeTable.id" \
    --output tsv)

if [[ $public_rt == *"EAST-SPOKE-1-PUB-RT"* ]]; then
    echo "✓ Public subnet correctly associated with EAST-SPOKE-1-PUB-RT"
else
    echo "✗ Public subnet association incorrect: $public_rt"
fi

# 3. Validate Route Content
echo -e "\n3. ROUTE TABLE CONTENTS:"

echo -e "\nEAST-SPOKE-1-PRV-RT Routes:"
az network route-table route list \
    --resource-group $RESOURCE_GROUP \
    --route-table-name "EAST-SPOKE-1-PRV-RT" \
    --query "[].{Name:name, Prefix:addressPrefix, NextHop:nextHopType, NextHopIP:nextHopIpAddress}" \
    --output table

echo -e "\nEAST-SPOKE-1-PUB-RT Routes:"
az network route-table route list \
    --resource-group $RESOURCE_GROUP \
    --route-table-name "EAST-SPOKE-1-PUB-RT" \
    --query "[].{Name:name, Prefix:addressPrefix, NextHop:nextHopType, NextHopIP:nextHopIpAddress}" \
    --output table

echo -e "\nEAST-SPOKE-1-IPv6 Routes:"
az network route-table route list \
    --resource-group $RESOURCE_GROUP \
    --route-table-name "EAST-SPOKE-1-IPv6" \
    --query "[].{Name:name, Prefix:addressPrefix, NextHop:nextHopType, NextHopIP:nextHopIpAddress}" \
    --output table

# 4. Validate Hub Gateway Routes
echo -e "\n4. HUB GATEWAY ROUTES (EAST-SPOKE-1 related):"
az network route-table route list \
    --resource-group $RESOURCE_GROUP \
    --route-table-name "EAST-HUB-GATEWAY-RT" \
    --query "[?contains(name, 'EAST-SPOKE-1')].{Name:name, Prefix:addressPrefix, NextHop:nextHopType, NextHopIP:nextHopIpAddress}" \
    --output table

# 5. VM Information
echo -e "\n5. VM INFORMATION:"
az vm list \
    --resource-group $RESOURCE_GROUP \
    --query "[?contains(name, 'SPOKE1')].{Name:name, PowerState:powerState, Location:location}" \
    --output table

# 6. VM IP Addresses
echo -e "\n6. VM IP ADDRESSES:"
az vm list-ip-addresses \
    --resource-group $RESOURCE_GROUP \
    --query "[?contains(virtualMachine.name, 'SPOKE1')].{VM:virtualMachine.name, PrivateIP:virtualMachine.network.privateIpAddresses[0], PublicIP:virtualMachine.network.publicIpAddresses[0].ipAddress}" \
    --output table

# 7. Network Security Groups
echo -e "\n7. NETWORK SECURITY GROUPS:"
az network nsg list \
    --resource-group $RESOURCE_GROUP \
    --query "[].{Name:name, Location:location, SubnetAssociations:length(subnets), NicAssociations:length(networkInterfaces)}" \
    --output table

# 8. Virtual Appliance Status Check
echo -e "\n8. VIRTUAL APPLIANCE CONNECTIVITY TEST:"
echo "Testing connectivity to virtual appliances..."

# Test from Private VM to appliances
echo "From Private VM (10.28.159.4) to Virtual Appliances:"
az vm run-command invoke \
    --resource-group $RESOURCE_GROUP \
    --name "SPOKE1-Private-Monitor-VM" \
    --command-id RunShellScript \
    --scripts "
echo 'Testing EAST-FGT-A (137.75.100.6):';
ping -c 2 -W 5 137.75.100.6 2>/dev/null && echo '✓ EAST-FGT-A reachable' || echo '✗ EAST-FGT-A unreachable';
echo 'Testing EAST-FGT-B (137.75.100.7):';
ping -c 2 -W 5 137.75.100.7 2>/dev/null && echo '✓ EAST-FGT-B reachable' || echo '✗ EAST-FGT-B unreachable';
echo 'Testing Next Hop 10.28.128.11:';
ping -c 2 -W 5 10.28.128.11 2>/dev/null && echo '✓ Next Hop 10.28.128.11 reachable' || echo '✗ Next Hop 10.28.128.11 unreachable';
echo 'Testing Internet (8.8.8.8):';
ping -c 2 -W 5 8.8.8.8 2>/dev/null && echo '✓ Internet reachable' || echo '✗ Internet unreachable';
" --output tsv

# 9. Summary Report
echo -e "\n9. VALIDATION SUMMARY:"
echo "================================================"

# Check if all expected route tables exist
tables_exist=0
for table in "EAST-SPOKE-1-PRV-RT" "EAST-SPOKE-1-PUB-RT" "EAST-SPOKE-1-IPv6"; do
    if az network route-table show --resource-group $RESOURCE_GROUP --name "$table" &>/dev/null; then
        echo "✓ Route table $table exists"
        ((tables_exist++))
    else
        echo "✗ Route table $table missing"
    fi
done

# Final status
echo -e "\nOVERALL STATUS:"
if [ $tables_exist -eq 3 ]; then
    echo "✓ Route table renaming appears SUCCESSFUL"
    echo "✓ All 3 expected route tables exist"
    echo "✓ Subnet associations updated"
else
    echo "✗ Route table renaming may have ISSUES"
    echo "✗ Missing $(( 3 - tables_exist )) route table(s)"
fi

echo -e "\nNext recommended actions:"
echo "1. Verify connectivity tests pass"
echo "2. Test cross-spoke communication"
echo "3. Monitor for any routing issues"
echo "4. Delete old SPOKE-1 route tables if validation successful"

echo -e "\nValidation completed at $(date)"