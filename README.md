# Azure Multi-Tier Architecture Deployment Guide

## Architecture Overview

This deployment creates a secure 3-tier architecture in Azure:

- **Web Tier**: Public-facing web servers (subnet: 10.0.1.0/24)
- **App Tier**: Application servers (subnet: 10.0.2.0/24)
- **DB Tier**: Database servers (subnet: 10.0.3.0/24)

## Network Security Rules

### Web Tier (NSG: nsg-web)
- ✓ Allow HTTP (80) from Internet
- ✓ Allow HTTPS (443) from Internet
- ✓ Allow SSH (22) from Internet (for management)
- ✓ Allow all outbound traffic

### App Tier (NSG: nsg-app)
- ✓ Allow App traffic (8080) from Web subnet only
- ✓ Allow SSH (22) from Web subnet only
- ✓ Allow ICMP from Web subnet (for ping tests)
- ✗ Deny all other inbound traffic

### DB Tier (NSG: nsg-db)
- ✓ Allow PostgreSQL (5432) from App subnet only
- ✓ Allow MySQL (3306) from App subnet only
- ✓ Allow SSH (22) from App subnet only
- ✓ Allow ICMP from App subnet (for ping tests)
- ✗ Deny all other inbound traffic

## Deployed Resources

- **Resource Group**: rg-multitier-prod
- **Location**: francecentral
- **VNet**: vnet-multitier (10.0.0.0/16)
- **VMs**: vm-web-01, vm-app-01, vm-db-01

## Access Information

### SSH Access
Use the generated SSH key at: `/home/osboxes/.ssh/azure_multitier_key`

### Web VM
```bash
ssh -i /home/osboxes/.ssh/azure_multitier_key azureuser@<WEB_PUBLIC_IP>
```

### App VM
```bash
ssh -i /home/osboxes/.ssh/azure_multitier_key azureuser@<APP_PUBLIC_IP>
```

### DB VM
```bash
ssh -i /home/osboxes/.ssh/azure_multitier_key azureuser@<DB_PUBLIC_IP>
```

## Connectivity Testing

### Step 1: SSH into Web VM
```bash
ssh -i /home/osboxes/.ssh/azure_multitier_key azureuser@<WEB_PUBLIC_IP>
```

### Step 2: Test Web → App connectivity
```bash
ping -c 4 <APP_PRIVATE_IP>
# Should succeed
```

### Step 3: Test Web → DB connectivity
```bash
ping -c 4 <DB_PRIVATE_IP>
# Should FAIL (Web cannot directly access DB)
```

### Step 4: SSH from Web to App
```bash
ssh azureuser@<APP_PRIVATE_IP>
```

### Step 5: From App VM, test App → DB connectivity
```bash
ping -c 4 <DB_PRIVATE_IP>
# Should succeed
```

### Step 6: Test DB ports from App VM
```bash
nc -zv <DB_PRIVATE_IP> 5432  # PostgreSQL
nc -zv <DB_PRIVATE_IP> 3306  # MySQL
# Should succeed
```

## Using the Connectivity Test Script

A script has been generated to automate testing:

```bash
# Copy the script to each VM
scp -i /home/osboxes/.ssh/azure_multitier_key connectivity_tests.sh azureuser@<VM_IP>:~/

# SSH into the VM and run
ssh -i /home/osboxes/.ssh/azure_multitier_key azureuser@<VM_IP>
chmod +x connectivity_tests.sh
./connectivity_tests.sh
```

## NSG Rule Verification

View NSG rules:
```bash
# Web NSG
az network nsg show -g rg-multitier-prod -n nsg-web --query "securityRules[].{Name:name, Priority:priority, Direction:direction, Access:access}" -o table

# App NSG
az network nsg show -g rg-multitier-prod -n nsg-app --query "securityRules[].{Name:name, Priority:priority, Direction:direction, Access:access}" -o table

# DB NSG
az network nsg show -g rg-multitier-prod -n nsg-db --query "securityRules[].{Name:name, Priority:priority, Direction:direction, Access:access}" -o table
```

## Cleanup

To delete all resources:
```bash
az group delete --name rg-multitier-prod --yes --no-wait
```

## Security Best Practices Implemented

1. ✓ Network segmentation with separate subnets
2. ✓ NSGs with least-privilege access
3. ✓ No direct Internet access to App and DB tiers
4. ✓ Traffic flow restricted to: Web → App → DB
5. ✓ SSH key-based authentication (no passwords)
6. ✓ Public IPs only on necessary VMs

## Troubleshooting

### Cannot SSH to VM
- Verify NSG rules allow SSH from your IP
- Check VM is running: `az vm get-instance-view -g rg-multitier-prod -n <VM_NAME>`

### Cannot ping between VMs
- Verify NSG rules allow ICMP
- Check VMs are in correct subnets
- Verify VMs are running

### Network connectivity issues
- Review NSG effective rules: `az network nic show-effective-nsg -g rg-multitier-prod -n <NIC_NAME>`
- Check route tables: `az network nic show-effective-route-table -g rg-multitier-prod -n <NIC_NAME>`

## Next Steps

1. Install web server on Web VM (nginx/apache)
2. Install application on App VM (Node.js, Python, etc.)
3. Install database on DB VM (PostgreSQL, MySQL)
4. Configure application connectivity
5. Set up monitoring and alerts
6. Implement backup strategies

---
**Generated**: Wed Nov  5 01:54:44 AM EST 2025
**Deployment Script**: deploy.sh
