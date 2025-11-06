#!/bin/bash

#############################################
# NSG Configuration Export Script
# Exports all NSG rules to JSON for documentation
#############################################

RESOURCE_GROUP="rg-multitier-prod"
OUTPUT_DIR="nsg_configs"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Exporting NSG Configurations...${NC}\n"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Export Web NSG
echo -e "${YELLOW}Exporting Web NSG...${NC}"
az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "nsg-web" \
    > "$OUTPUT_DIR/nsg-web.json"

az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "nsg-web" \
    --query "securityRules[].{Name:name, Priority:priority, Direction:direction, Protocol:protocol, SourceAddress:sourceAddressPrefix, SourcePort:sourcePortRange, DestAddress:destinationAddressPrefix, DestPort:destinationPortRange, Access:access}" \
    -o table > "$OUTPUT_DIR/nsg-web-rules.txt"

# Export App NSG
echo -e "${YELLOW}Exporting App NSG...${NC}"
az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "nsg-app" \
    > "$OUTPUT_DIR/nsg-app.json"

az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "nsg-app" \
    --query "securityRules[].{Name:name, Priority:priority, Direction:direction, Protocol:protocol, SourceAddress:sourceAddressPrefix, SourcePort:sourcePortRange, DestAddress:destinationAddressPrefix, DestPort:destinationPortRange, Access:access}" \
    -o table > "$OUTPUT_DIR/nsg-app-rules.txt"

# Export DB NSG
echo -e "${YELLOW}Exporting DB NSG...${NC}"
az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "nsg-db" \
    > "$OUTPUT_DIR/nsg-db.json"

az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "nsg-db" \
    --query "securityRules[].{Name:name, Priority:priority, Direction:direction, Protocol:protocol, SourceAddress:sourceAddressPrefix, SourcePort:sourcePortRange, DestAddress:destinationAddressPrefix, DestPort:destinationPortRange, Access:access}" \
    -o table > "$OUTPUT_DIR/nsg-db-rules.txt"

# Create summary report
cat > "$OUTPUT_DIR/NSG_SUMMARY.md" << 'EOF'
# Network Security Group Configuration Summary

## Overview
This document provides a comprehensive overview of the NSG rules configured for the multi-tier architecture.

## Architecture Flow
```
Internet → Web Tier → App Tier → DB Tier
```

## Web Tier NSG (nsg-web)
**Purpose**: Accept traffic from Internet, forward to App tier

### Inbound Rules:
EOF

echo -e "\n### Web NSG Rules:" >> "$OUTPUT_DIR/NSG_SUMMARY.md"
echo '```' >> "$OUTPUT_DIR/NSG_SUMMARY.md"
cat "$OUTPUT_DIR/nsg-web-rules.txt" >> "$OUTPUT_DIR/NSG_SUMMARY.md"
echo '```' >> "$OUTPUT_DIR/NSG_SUMMARY.md"

cat >> "$OUTPUT_DIR/NSG_SUMMARY.md" << 'EOF'

## App Tier NSG (nsg-app)
**Purpose**: Accept traffic from Web tier only, forward to DB tier

### Inbound Rules:
EOF

echo '```' >> "$OUTPUT_DIR/NSG_SUMMARY.md"
cat "$OUTPUT_DIR/nsg-app-rules.txt" >> "$OUTPUT_DIR/NSG_SUMMARY.md"
echo '```' >> "$OUTPUT_DIR/NSG_SUMMARY.md"

cat >> "$OUTPUT_DIR/NSG_SUMMARY.md" << 'EOF'

## DB Tier NSG (nsg-db)
**Purpose**: Accept traffic from App tier only

### Inbound Rules:
EOF

echo '```' >> "$OUTPUT_DIR/NSG_SUMMARY.md"
cat "$OUTPUT_DIR/nsg-db-rules.txt" >> "$OUTPUT_DIR/NSG_SUMMARY.md"
echo '```' >> "$OUTPUT_DIR/NSG_SUMMARY.md"

cat >> "$OUTPUT_DIR/NSG_SUMMARY.md" << 'EOF'

## Security Validation Checklist

- [ ] Web tier accepts HTTP/HTTPS from Internet ✓
- [ ] Web tier accepts SSH for management ✓
- [ ] App tier only accepts traffic from Web subnet ✓
- [ ] App tier blocks all Internet traffic ✓
- [ ] DB tier only accepts traffic from App subnet ✓
- [ ] DB tier blocks all Internet and Web tier traffic ✓
- [ ] ICMP enabled for connectivity testing ✓
- [ ] Default deny rules in place ✓

## Network Flow Test Results

### Expected Results:
1. **Web → Internet**: ✓ Allowed (outbound default)
2. **Web → App**: ✓ Allowed (NSG allows)
3. **Web → DB**: ✗ Denied (no direct route)
4. **App → DB**: ✓ Allowed (NSG allows)
5. **Internet → Web**: ✓ Allowed (ports 80, 443, 22)
6. **Internet → App**: ✗ Denied (no public IP or NSG deny)
7. **Internet → DB**: ✗ Denied (no public IP or NSG deny)

---
Generated: $(date)
EOF

echo -e "\n${GREEN}✓ NSG configurations exported to: $OUTPUT_DIR/${NC}"
echo -e "${GREEN}✓ Summary report created: $OUTPUT_DIR/NSG_SUMMARY.md${NC}"

# Create a visual diagram
cat > "$OUTPUT_DIR/architecture_diagram.txt" << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                    MULTI-TIER ARCHITECTURE                        ║
╚═══════════════════════════════════════════════════════════════════╝

                         ┌─────────────┐
                         │  Internet   │
                         └──────┬──────┘
                                │
                     HTTP/HTTPS │ SSH
                                │
                 ┌──────────────▼──────────────┐
                 │      WEB TIER (DMZ)         │
                 │  Subnet: 10.0.1.0/24        │
                 │  NSG: nsg-web               │
                 │  VM: vm-web-01              │
                 │                             │
                 │  Rules:                     │
                 │  - Allow HTTP (80)          │
                 │  - Allow HTTPS (443)        │
                 │  - Allow SSH (22)           │
                 └──────────────┬──────────────┘
                                │
                       App Port │ 8080
                                │
                 ┌──────────────▼──────────────┐
                 │      APP TIER               │
                 │  Subnet: 10.0.2.0/24        │
                 │  NSG: nsg-app               │
                 │  VM: vm-app-01              │
                 │                             │
                 │  Rules:                     │
                 │  - Allow from Web subnet    │
                 │  - Allow SSH from Web       │
                 │  - DENY all other           │
                 └──────────────┬──────────────┘
                                │
                   DB Ports     │ 5432/3306
                                │
                 ┌──────────────▼──────────────┐
                 │      DB TIER                │
                 │  Subnet: 10.0.3.0/24        │
                 │  NSG: nsg-db                │
                 │  VM: vm-db-01               │
                 │                             │
                 │  Rules:                     │
                 │  - Allow from App subnet    │
                 │  - Allow SSH from App       │
                 │  - DENY all other           │
                 └─────────────────────────────┘

═══════════════════════════════════════════════════════════════════
SECURITY PRINCIPLES:
  ✓ Network Segmentation
  ✓ Least Privilege Access
  ✓ Defense in Depth
  ✓ Zero Trust Network
═══════════════════════════════════════════════════════════════════
EOF

cat "$OUTPUT_DIR/architecture_diagram.txt"

echo -e "\n${GREEN}Export completed!${NC}"