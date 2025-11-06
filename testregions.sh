
#!/bin/bash

echo "=========================================="
echo "Finding Working Azure Regions..."
echo "=========================================="
echo ""

# Create resource group if it doesn't exist
RG_NAME="rg-test-regions"
echo "Creating test resource group in default region..."
az group create --name "$RG_NAME" --location centralus &>/dev/null || \
az group create --name "$RG_NAME" --location westus2 &>/dev/null || \
az group create --name "$RG_NAME" --location eastus2 &>/dev/null

echo ""

# Test these regions
regions=(
    "centralus"
    "westus2"
    "eastus2"
    "westus3"
    "southcentralus"
    "northcentralus"
    "eastus"
    "westus"
    "canadacentral"
    "canadaeast"
    "brazilsouth"
    "westeurope"
    "northeurope"
    "uksouth"
    "ukwest"
    "francecentral"
    "germanywestcentral"
    "switzerlandnorth"
    "norwayeast"
    "swedencentral"
    "australiaeast"
    "australiasoutheast"
    "japaneast"
    "japanwest"
    "koreacentral"
    "southeastasia"
    "eastasia"
    "southindia"
    "centralindia"
    "westindia"
    "uaenorth"
    "southafricanorth"
)

working_regions=()

for region in "${regions[@]}"; do
    printf "Testing %-25s ... " "$region"
    
    # Try to create NSG in this region
    if az network nsg create \
        --resource-group "$RG_NAME" \
        --name "test-$region" \
        --location "$region" \
        --output none 2>/dev/null; then
        
        echo "✅ WORKS!"
        working_regions+=("$region")
        
        # Clean up immediately
        az network nsg delete \
            --resource-group "$RG_NAME" \
            --name "test-$region" \
            --yes &>/dev/null
    else
        echo "❌ BLOCKED"
    fi
    
    sleep 1
done

# Clean up resource group
echo ""
echo "Cleaning up test resource group..."
az group delete --name "$RG_NAME" --yes --no-wait &>/dev/null

echo ""
echo "=========================================="
echo "✅ WORKING REGIONS:"
echo "=========================================="

if [ ${#working_regions[@]} -eq 0 ]; then
    echo "❌ NO REGIONS WORK!"
    echo ""
    echo "This means your subscription has severe restrictions."
    echo "Please contact Azure support or check with your administrator."
else
    for region in "${working_regions[@]}"; do
        echo "  ✓ $region"
    done
    
    echo ""
    echo "=========================================="
    echo "📝 UPDATE YOUR SCRIPT:"
    echo "=========================================="
    echo "Open deploy.sh and change this line:"
    echo ""
    echo 'LOCATION="eastus"'
    echo ""
    echo "To this:"
    echo ""
    echo "LOCATION=\"${working_regions[0]}\""
    echo ""
fi

echo "=========================================="
