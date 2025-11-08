#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration Variables
RESOURCE_GROUP="rg-multitier-prod"
LOCATION="francecentral"
VNET_NAME="vnet-multitier"
VNET_ADDRESS_PREFIX="10.0.0.0/16"

# Subnet Configuration
WEB_SUBNET_NAME="snet-web"
WEB_SUBNET_PREFIX="10.0.1.0/24"
APP_SUBNET_NAME="snet-app"
APP_SUBNET_PREFIX="10.0.2.0/24"
DB_SUBNET_NAME="snet-db"
DB_SUBNET_PREFIX="10.0.3.0/24"

# NSG Names
WEB_NSG="nsg-web"
APP_NSG="nsg-app"
DB_NSG="nsg-db"

# VM Configuration
WEB_VM_NAME="vm-web-01"
APP_VM_NAME="vm-app-01"
DB_VM_NAME="vm-db-01"
VM_SIZE="Standard_B1s"
ADMIN_USERNAME="azureuser"

# SSH Key (will be generated if not exists)
SSH_KEY_PATH="$HOME/.ssh/azure_multitier_key"

# Helper Functions

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}\n"
}

# Pre-deployment Checks

check_azure_cli() {
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    print_info "Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv)"
}

check_login() {
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login'"
        exit 1
    fi
    SUBSCRIPTION=$(az account show --query name -o tsv)
    print_info "Logged in to subscription: $SUBSCRIPTION"
}

generate_ssh_key() {
    if [ ! -f "$SSH_KEY_PATH" ]; then
        print_info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "azure-multitier-deployment"
        print_info "SSH key generated at: $SSH_KEY_PATH"
    else
        print_info "Using existing SSH key: $SSH_KEY_PATH"
    fi
}

# Resource Group

create_resource_group() {
    print_section "Creating Resource Group"
    
    if az group exists -n "$RESOURCE_GROUP" | grep -q "true"; then
        print_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags Environment=Production Tier=Multi Application=Demo
        print_info "Resource group created: $RESOURCE_GROUP"
    fi
}

# Network Security Groups

create_nsg_web() {
    print_section "Creating Web Tier NSG"
    
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_NSG" \
        --location "$LOCATION"
    
    # Allow HTTP from Internet
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$WEB_NSG" \
        --name "Allow-HTTP" \
        --priority 100 \
        --source-address-prefixes Internet \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 80 \
        --access Allow \
        --protocol Tcp \
        --description "Allow HTTP from Internet"
    
    # Allow HTTPS from Internet
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$WEB_NSG" \
        --name "Allow-HTTPS" \
        --priority 110 \
        --source-address-prefixes Internet \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 443 \
        --access Allow \
        --protocol Tcp \
        --description "Allow HTTPS from Internet"
    
    # Allow SSH from Internet (for management)
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$WEB_NSG" \
        --name "Allow-SSH" \
        --priority 120 \
        --source-address-prefixes Internet \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 22 \
        --access Allow \
        --protocol Tcp \
        --description "Allow SSH from Internet"
    
    print_info "Web NSG created with rules"
}

create_nsg_app() {
    print_section "Creating App Tier NSG"
    
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NSG" \
        --location "$LOCATION"
    
    # Allow traffic from Web subnet only
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$APP_NSG" \
        --name "Allow-From-Web" \
        --priority 100 \
        --source-address-prefixes "$WEB_SUBNET_PREFIX" \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 8080 \
        --access Allow \
        --protocol Tcp \
        --description "Allow App traffic from Web tier"
    
    # Allow SSH from Web subnet for management
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$APP_NSG" \
        --name "Allow-SSH-From-Web" \
        --priority 110 \
        --source-address-prefixes "$WEB_SUBNET_PREFIX" \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 22 \
        --access Allow \
        --protocol Tcp \
        --description "Allow SSH from Web tier"
    
    # Allow ICMP for ping tests
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$APP_NSG" \
        --name "Allow-ICMP-From-Web" \
        --priority 120 \
        --source-address-prefixes "$WEB_SUBNET_PREFIX" \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges '*' \
        --access Allow \
        --protocol Icmp \
        --description "Allow ICMP from Web tier"
    
    # Deny all other inbound traffic
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$APP_NSG" \
        --name "Deny-All-Inbound" \
        --priority 4096 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges '*' \
        --access Deny \
        --protocol '*' \
        --description "Deny all other inbound traffic"
    
    print_info "App NSG created with rules"
}

create_nsg_db() {
    print_section "Creating DB Tier NSG"
    
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DB_NSG" \
        --location "$LOCATION"
    
    # Allow PostgreSQL from App subnet only
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$DB_NSG" \
        --name "Allow-PostgreSQL-From-App" \
        --priority 100 \
        --source-address-prefixes "$APP_SUBNET_PREFIX" \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 5432 \
        --access Allow \
        --protocol Tcp \
        --description "Allow PostgreSQL from App tier"
    
    # Allow MySQL from App subnet
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$DB_NSG" \
        --name "Allow-MySQL-From-App" \
        --priority 110 \
        --source-address-prefixes "$APP_SUBNET_PREFIX" \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 3306 \
        --access Allow \
        --protocol Tcp \
        --description "Allow MySQL from App tier"
    
    # Allow SSH from App subnet for management
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$DB_NSG" \
        --name "Allow-SSH-From-App" \
        --priority 120 \
        --source-address-prefixes "$APP_SUBNET_PREFIX" \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 22 \
        --access Allow \
        --protocol Tcp \
        --description "Allow SSH from App tier"
    
    # Allow ICMP for ping tests
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$DB_NSG" \
        --name "Allow-ICMP-From-App" \
        --priority 130 \
        --source-address-prefixes "$APP_SUBNET_PREFIX" \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges '*' \
        --access Allow \
        --protocol Icmp \
        --description "Allow ICMP from App tier"
    
    # Deny all other inbound traffic
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$DB_NSG" \
        --name "Deny-All-Inbound" \
        --priority 4096 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges '*' \
        --access Deny \
        --protocol '*' \
        --description "Deny all other inbound traffic"
    
    print_info "DB NSG created with rules"
}

# Virtual Network and Subnets

create_vnet_and_subnets() {
    print_section "Creating Virtual Network and Subnets"
    
    # Create VNet
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "$VNET_ADDRESS_PREFIX" \
        --location "$LOCATION"
    
    print_info "VNet created: $VNET_NAME ($VNET_ADDRESS_PREFIX)"
    
    # Create Web Subnet
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$WEB_SUBNET_NAME" \
        --address-prefix "$WEB_SUBNET_PREFIX" \
    
    print_info "Web subnet created: $WEB_SUBNET_NAME ($WEB_SUBNET_PREFIX)"
    
    # Create App Subnet
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$APP_SUBNET_NAME" \
        --address-prefix "$APP_SUBNET_PREFIX" \
    
    print_info "App subnet created: $APP_SUBNET_NAME ($APP_SUBNET_PREFIX)"
    
    # Create DB Subnet
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$DB_SUBNET_NAME" \
        --address-prefix "$DB_SUBNET_PREFIX" \
    
    print_info "DB subnet created: $DB_SUBNET_NAME ($DB_SUBNET_PREFIX)"
}

# Attach NSGs to Subnets

attach_nsgs_to_subnets() {
    print_section "Attaching NSGs to Subnets"
    
    # Attach Web NSG
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$WEB_SUBNET_NAME" \
        --network-security-group "$WEB_NSG"
    print_info "Web NSG attached to Web subnet"
    
    # Attach App NSG
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$APP_SUBNET_NAME" \
        --network-security-group "$APP_NSG"
    print_info "App NSG attached to App subnet"
    
    # Attach DB NSG
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$DB_SUBNET_NAME" \
        --network-security-group "$DB_NSG"
    print_info "DB NSG attached to DB subnet"
}

# Virtual Machines

create_vm() {
    local VM_NAME=$1
    local SUBNET_NAME=$2
    local TIER=$3
    
    print_info "Creating VM: $VM_NAME in $SUBNET_NAME..."
    
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --location "$LOCATION" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --image Ubuntu2204 \
        --size "$VM_SIZE" \
        --admin-username "$ADMIN_USERNAME" \
        --ssh-key-values "@${SSH_KEY_PATH}.pub" \
        --public-ip-address "${VM_NAME}-pip" \
        --public-ip-sku Standard \
        --tags Tier="$TIER" Environment=Production \
        --no-wait
    
    print_info "VM creation initiated: $VM_NAME"
}

create_all_vms() {
    print_section "Creating Virtual Machines"
    
    create_vm "$WEB_VM_NAME" "$WEB_SUBNET_NAME" "Web"
    create_vm "$APP_VM_NAME" "$APP_SUBNET_NAME" "App"
    create_vm "$DB_VM_NAME" "$DB_SUBNET_NAME" "Database"
    
    print_info "Waiting for all VMs to be created (this may take 5-10 minutes)..."
    
    # Wait for each VM with better error handling
    if az vm wait --resource-group "$RESOURCE_GROUP" --name "$WEB_VM_NAME" --created --timeout 600 2>/dev/null; then
        print_info "✓ Web VM created successfully"
    else
        print_error "✗ Web VM creation failed or timed out"
        return 1
    fi
    
    if az vm wait --resource-group "$RESOURCE_GROUP" --name "$APP_VM_NAME" --created --timeout 600 2>/dev/null; then
        print_info "✓ App VM created successfully"
    else
        print_error "✗ App VM creation failed or timed out"
        return 1
    fi
    
    if az vm wait --resource-group "$RESOURCE_GROUP" --name "$DB_VM_NAME" --created --timeout 600 2>/dev/null; then
        print_info "✓ DB VM created successfully"
    else
        print_error "✗ DB VM creation failed or timed out"
        return 1
    fi
    
    print_info "All VMs created successfully"
}

# Get VM Information

get_vm_info() {
    print_section "VM Information"
    
    echo -e "\n${GREEN}Web Tier VM:${NC}"
    WEB_PUBLIC_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$WEB_VM_NAME" --query publicIps -o tsv)
    WEB_PRIVATE_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$WEB_VM_NAME" --query privateIps -o tsv)
    echo "  Name: $WEB_VM_NAME"
    echo "  Public IP: $WEB_PUBLIC_IP"
    echo "  Private IP: $WEB_PRIVATE_IP"
    echo "  SSH: ssh -i $SSH_KEY_PATH $ADMIN_USERNAME@$WEB_PUBLIC_IP"
    
    echo -e "\n${GREEN}App Tier VM:${NC}"
    APP_PUBLIC_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$APP_VM_NAME" --query publicIps -o tsv)
    APP_PRIVATE_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$APP_VM_NAME" --query privateIps -o tsv)
    echo "  Name: $APP_VM_NAME"
    echo "  Public IP: $APP_PUBLIC_IP"
    echo "  Private IP: $APP_PRIVATE_IP"
    echo "  SSH: ssh -i $SSH_KEY_PATH $ADMIN_USERNAME@$APP_PUBLIC_IP"
    
    echo -e "\n${GREEN}DB Tier VM:${NC}"
    DB_PUBLIC_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$DB_VM_NAME" --query publicIps -o tsv)
    DB_PRIVATE_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$DB_VM_NAME" --query privateIps -o tsv)
    echo "  Name: $DB_VM_NAME"
    echo "  Public IP: $DB_PUBLIC_IP"
    echo "  Private IP: $DB_PRIVATE_IP"
    echo "  SSH: ssh -i $SSH_KEY_PATH $ADMIN_USERNAME@$DB_PUBLIC_IP"
}

# Main Execution Flow
main() {
    echo -e "${GREEN}"
    echo "   Azure Multi-Tier Architecture Deployment    "
    echo "   Secure 3-Tier Setup with NSG Rules          "
    echo -e "${NC}\n"
    
    # Pre-deployment checks
    check_azure_cli
    check_login
    generate_ssh_key
    
    # Start deployment
    create_resource_group
    create_nsg_web
    create_nsg_app
    create_nsg_db
    create_vnet_and_subnets
    attach_nsgs_to_subnets
    create_all_vms
    
    # Post-deployment
    get_vm_info
    generate_test_script
    generate_documentation
    
    # Final summary
    print_section "Deployment Complete!"
    echo -e "${GREEN}✓ Resource Group: $RESOURCE_GROUP${NC}"
    echo -e "${GREEN}✓ VNet: $VNET_NAME with 3 subnets${NC}"
    echo -e "${GREEN}✓ NSGs: Web, App, and DB tiers configured${NC}"
    echo -e "${GREEN}✓ VMs: 3 Linux VMs provisioned${NC}"
    echo -e "${GREEN}✓ Documentation: DEPLOYMENT_GUIDE.md${NC}"
    echo -e "${GREEN}✓ Test Script: connectivity_tests.sh${NC}"
    
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "1. Review the DEPLOYMENT_GUIDE.md for detailed information"
    echo "2. SSH into each VM using the commands above"
    echo "3. Run connectivity_tests.sh to verify NSG rules"
    echo "4. Take screenshots of successful ping tests"
    echo "5. Commit all scripts to GitHub for version control"
    
    echo -e "\n${YELLOW}Quick Test Command:${NC}"
    echo "ssh -i $SSH_KEY_PATH $ADMIN_USERNAME@<VM_IP>"
}

# Run main function
main

print_info "Script execution completed successfully!"