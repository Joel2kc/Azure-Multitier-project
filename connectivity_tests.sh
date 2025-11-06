

# Connectivity Test Script
# Run this script after SSHing into each VM

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_test() {
    echo -e "\n${YELLOW}Testing: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
}

# Get current VM tier
HOSTNAME=$(hostname)
TIER=""
if [[ $HOSTNAME == *"web"* ]]; then
    TIER="WEB"
elif [[ $HOSTNAME == *"app"* ]]; then
    TIER="APP"
elif [[ $HOSTNAME == *"db"* ]]; then
    TIER="DB"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Running Connectivity Tests from $TIER Tier${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Read IP addresses
read -p "Enter APP VM Private IP: " APP_IP
read -p "Enter DB VM Private IP: " DB_IP

if [ "$TIER" == "WEB" ]; then
    print_test "Web → App connectivity"
    if ping -c 3 $APP_IP > /dev/null 2>&1; then
        print_success "Can ping App tier ($APP_IP)"
    else
        print_failure "Cannot ping App tier ($APP_IP)"
    fi
    
    print_test "Web → DB connectivity (should fail)"
    if ping -c 3 $DB_IP > /dev/null 2>&1; then
        print_failure "Can ping DB tier ($DB_IP) - NSG rules may be incorrect!"
    else
        print_success "Cannot ping DB tier ($DB_IP) - Correct! Web should not reach DB directly"
    fi

elif [ "$TIER" == "APP" ]; then
    print_test "App → DB connectivity"
    if ping -c 3 $DB_IP > /dev/null 2>&1; then
        print_success "Can ping DB tier ($DB_IP)"
    else
        print_failure "Cannot ping DB tier ($DB_IP)"
    fi
    
    print_test "Testing SSH to DB (port 22)"
    if timeout 3 bash -c "echo > /dev/tcp/$DB_IP/22" 2>/dev/null; then
        print_success "Port 22 is reachable on DB tier"
    else
        print_failure "Port 22 is not reachable on DB tier"
    fi

elif [ "$TIER" == "DB" ]; then
    print_test "DB tier should only accept connections from App tier"
    echo "DB tier is protected. Test from App tier to verify connectivity."
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Test completed${NC}"
echo -e "${GREEN}========================================${NC}\n"
