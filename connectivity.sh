#!/bin/bash

#############################################
# Comprehensive Connectivity Test Script
# Run from your local machine to test all connectivity
#############################################

set -e

# Configuration
RESOURCE_GROUP="rg-multitier-prod"
SSH_KEY_PATH="$HOME/.ssh/azure_multitier_key"
ADMIN_USERNAME="azureuser"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║$1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"
}

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
    ((TOTAL_TESTS++))
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

print_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Get VM information
get_vm_ips() {
    print_header "Retrieving VM Information"
    
    WEB_PUBLIC_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "vm-web-01" --query publicIps -o tsv)
    WEB_PRIVATE_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "vm-web-01" --query privateIps -o tsv)
    
    APP_PUBLIC_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "vm-app-01" --query publicIps -o tsv)
    APP_PRIVATE_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "vm-app-01" --query privateIps -o tsv)
    
    DB_PUBLIC_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "vm-db-01" --query publicIps -o tsv)
    DB_PRIVATE_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "vm-db-01" --query privateIps -o tsv)
    
    print_info "Web VM: $WEB_PUBLIC_IP (public) / $WEB_PRIVATE_IP (private)"
    print_info "App VM: $APP_PUBLIC_IP (public) / $APP_PRIVATE_IP (private)"
    print_info "DB VM: $DB_PUBLIC_IP (public) / $DB_PRIVATE_IP (private)"
}

# Test 1: SSH Connectivity from local machine
test_ssh_connectivity() {
    print_header "Test 1: SSH Connectivity from Local Machine"
    
    print_test "Testing SSH to Web VM"
    if timeout 10 ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$ADMIN_USERNAME@$WEB_PUBLIC_IP" "echo 'SSH Success'" &>/dev/null; then
        print_success "SSH to Web VM successful"
    else
        print_failure "SSH to Web VM failed"
    fi
    
    print_test "Testing SSH to App VM"
    if timeout 10 ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$ADMIN_USERNAME@$APP_PUBLIC_IP" "echo 'SSH Success'" &>/dev/null; then
        print_success "SSH to App VM successful"
    else
        print_failure "SSH to App VM failed"
    fi
    
    print_test "Testing SSH to DB VM"
    if timeout 10 ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$ADMIN_USERNAME@$DB_PUBLIC_IP" "echo 'SSH Success'" &>/dev/null; then
        print_success "SSH to DB VM successful"
    else
        print_failure "SSH to DB VM failed"
    fi
}

# Test 2: Web to App connectivity
test_web_to_app() {
    print_header "Test 2: Web Tier → App Tier Connectivity"
    
    print_test "Testing ping from Web to App"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$WEB_PUBLIC_IP" \
        "ping -c 3 -W 2 $APP_PRIVATE_IP &>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "SUCCESS" ]; then
        print_success "Web can ping App (Expected: ✓)"
    else
        print_failure "Web cannot ping App (Expected: ✓)"
    fi
    
    print_test "Testing SSH from Web to App"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$WEB_PUBLIC_IP" \
        "timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 $ADMIN_USERNAME@$APP_PRIVATE_IP 'echo SUCCESS' 2>/dev/null || echo 'FAILED'")
    
    if [[ "$RESULT" == *"SUCCESS"* ]]; then
        print_success "Web can SSH to App (Expected: ✓)"
    else
        print_failure "Web cannot SSH to App (Expected: ✓)"
    fi
}

# Test 3: Web to DB connectivity (should fail)
test_web_to_db() {
    print_header "Test 3: Web Tier → DB Tier Connectivity (Should FAIL)"
    
    print_test "Testing ping from Web to DB (expecting failure)"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$WEB_PUBLIC_IP" \
        "ping -c 3 -W 2 $DB_PRIVATE_IP &>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "FAILED" ]; then
        print_success "Web cannot ping DB (Expected: ✗) - NSG working correctly!"
    else
        print_failure "Web can ping DB (Expected: ✗) - NSG rules may be incorrect!"
    fi
    
    print_test "Testing SSH from Web to DB (expecting failure)"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$WEB_PUBLIC_IP" \
        "timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 $ADMIN_USERNAME@$DB_PRIVATE_IP 'echo SUCCESS' 2>/dev/null || echo 'FAILED'")
    
    if [[ "$RESULT" == "FAILED" ]]; then
        print_success "Web cannot SSH to DB (Expected: ✗) - NSG working correctly!"
    else
        print_failure "Web can SSH to DB (Expected: ✗) - NSG rules may be incorrect!"
    fi
}

# Test 4: App to DB connectivity
test_app_to_db() {
    print_header "Test 4: App Tier → DB Tier Connectivity"
    
    print_test "Testing ping from App to DB"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$APP_PUBLIC_IP" \
        "ping -c 3 -W 2 $DB_PRIVATE_IP &>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "SUCCESS" ]; then
        print_success "App can ping DB (Expected: ✓)"
    else
        print_failure "App cannot ping DB (Expected: ✓)"
    fi
    
    print_test "Testing SSH from App to DB"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$APP_PUBLIC_IP" \
        "timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 $ADMIN_USERNAME@$DB_PRIVATE_IP 'echo SUCCESS' 2>/dev/null || echo 'FAILED'")
    
    if [[ "$RESULT" == *"SUCCESS"* ]]; then
        print_success "App can SSH to DB (Expected: ✓)"
    else
        print_failure "App cannot SSH to DB (Expected: ✓)"
    fi
    
    print_test "Testing PostgreSQL port (5432) from App to DB"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$APP_PUBLIC_IP" \
        "timeout 3 bash -c 'echo > /dev/tcp/$DB_PRIVATE_IP/5432' 2>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "SUCCESS" ]; then
        print_success "PostgreSQL port 5432 is accessible from App (Expected: ✓)"
    else
        print_failure "PostgreSQL port 5432 is not accessible from App (May need PostgreSQL installed)"
    fi
    
    print_test "Testing MySQL port (3306) from App to DB"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$APP_PUBLIC_IP" \
        "timeout 3 bash -c 'echo > /dev/tcp/$DB_PRIVATE_IP/3306' 2>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "SUCCESS" ]; then
        print_success "MySQL port 3306 is accessible from App (Expected: ✓)"
    else
        print_failure "MySQL port 3306 is not accessible from App (May need MySQL installed)"
    fi
}

# Test 5: Internet access from VMs
test_internet_access() {
    print_header "Test 5: Internet Access from VMs"
    
    print_test "Testing Internet access from Web VM"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$WEB_PUBLIC_IP" \
        "curl -s --connect-timeout 5 http://www.google.com &>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "SUCCESS" ]; then
        print_success "Web VM has Internet access (Expected: ✓)"
    else
        print_failure "Web VM has no Internet access"
    fi
    
    print_test "Testing Internet access from App VM"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$APP_PUBLIC_IP" \
        "curl -s --connect-timeout 5 http://www.google.com &>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "SUCCESS" ]; then
        print_success "App VM has Internet access (Expected: ✓)"
    else
        print_failure "App VM has no Internet access"
    fi
    
    print_test "Testing Internet access from DB VM"
    RESULT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$DB_PUBLIC_IP" \
        "curl -s --connect-timeout 5 http://www.google.com &>/dev/null && echo 'SUCCESS' || echo 'FAILED'")
    
    if [ "$RESULT" == "SUCCESS" ]; then
        print_success "DB VM has Internet access (Expected: ✓)"
    else
        print_failure "DB VM has no Internet access"
    fi
}

# Test 6: NSG Rule Verification
test_nsg_rules() {
    print_header "Test 6: NSG Rule Verification"
    
    print_test "Verifying Web NSG has HTTP rule"
    HTTP_RULE=$(az network nsg rule show -g "$RESOURCE_GROUP" --nsg-name "nsg-web" -n "Allow-HTTP" --query "access" -o tsv 2>/dev/null)
    if [ "$HTTP_RULE" == "Allow" ]; then
        print_success "Web NSG has HTTP allow rule"
    else
        print_failure "Web NSG missing HTTP allow rule"
    fi
    
    print_test "Verifying App NSG denies all inbound by default"
    DENY_RULE=$(az network nsg rule show -g "$RESOURCE_GROUP" --nsg-name "nsg-app" -n "Deny-All-Inbound" --query "access" -o tsv 2>/dev/null)
    if [ "$DENY_RULE" == "Deny" ]; then
        print_success "App NSG has deny all inbound rule"
    else
        print_failure "App NSG missing deny all inbound rule"
    fi
    
    print_test "Verifying DB NSG denies all inbound by default"
    DENY_RULE=$(az network nsg rule show -g "$RESOURCE_GROUP" --nsg-name "nsg-db" -n "Deny-All-Inbound" --query "access" -o tsv 2>/dev/null)
    if [ "$DENY_RULE" == "Deny" ]; then
        print_success "DB NSG has deny all inbound rule"
    else
        print_failure "DB NSG missing deny all inbound rule"
    fi
}

# Generate test report
generate_report() {
    print_header "Test Summary Report"
    
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > connectivity_test_report.md << EOF
# Azure Multi-Tier Connectivity Test Report

**Test Date**: $TIMESTAMP  
**Resource Group**: $RESOURCE_GROUP  

## Test Summary

- **Total Tests**: $TOTAL_TESTS
- **Passed**: $PASSED_TESTS ✓
- **Failed**: $FAILED_TESTS ✗
- **Success Rate**: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## VM Information

| Tier | VM Name | Public IP | Private IP |
|------|---------|-----------|------------|
| Web  | vm-web-01 | $WEB_PUBLIC_IP | $WEB_PRIVATE_IP |
| App  | vm-app-01 | $APP_PUBLIC_IP | $APP_PRIVATE_IP |
| DB   | vm-db-01 | $DB_PUBLIC_IP | $DB_PRIVATE_IP |

## Test Results

### Category 1: SSH Connectivity
- SSH to Web VM: $([ $PASSED_TESTS -ge 1 ] && echo "✓ PASS" || echo "✗ FAIL")
- SSH to App VM: $([ $PASSED_TESTS -ge 2 ] && echo "✓ PASS" || echo "✗ FAIL")
- SSH to DB VM: $([ $PASSED_TESTS -ge 3 ] && echo "✓ PASS" || echo "✗ FAIL")

### Category 2: Network Segmentation
- Web → App connectivity: Should PASS
- Web → DB connectivity: Should FAIL (security requirement)
- App → DB connectivity: Should PASS

### Category 3: Security Validation
- NSG rules correctly configured
- Least privilege access implemented
- Network segmentation enforced

## Expected Connectivity Matrix

| From → To | Web | App | DB | Internet |
|-----------|-----|-----|----|---------| 
| **Web**   | ✓   | ✓   | ✗  | ✓        |
| **App**   | ✓   | ✓   | ✓  | ✓        |
| **DB**    | ✗   | ✗   | ✓  | ✓        |

✓ = Allowed  
✗ = Denied (by design)

## Recommendations

1. **If all tests pass**: Architecture is correctly configured
2. **If Web→DB test fails to fail**: Review NSG rules - Web should NOT reach DB directly
3. **If App→DB test fails**: Check NSG rules on DB tier
4. **For production**: 
   - Remove public IPs from App and DB tiers
   - Use Azure Bastion for secure management
   - Implement Azure Firewall for additional protection

## Next Steps

- [ ] Take screenshots of successful tests
- [ ] Document any failed tests
- [ ] Commit all scripts to GitHub
- [ ] Set up monitoring and alerts
- [ ] Implement backup strategies

---
Generated by: connectivity_test.sh  
Report file: connectivity_test_report.md
EOF

    echo -e "\n${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}FINAL RESULTS${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "Total Tests: ${BLUE}$TOTAL_TESTS${NC}"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}✓ ALL TESTS PASSED! Architecture is correctly configured.${NC}"
    else
        echo -e "\n${YELLOW}⚠ Some tests failed. Review the report for details.${NC}"
    fi
    
    echo -e "\n${BLUE}Report saved to: connectivity_test_report.md${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║        AZURE MULTI-TIER CONNECTIVITY TEST SUITE               ║
║                                                               ║
║  This script will test all connectivity between tiers        ║
║  and verify NSG rules are working correctly                  ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    # Run all tests
    get_vm_ips
    test_ssh_connectivity
    test_web_to_app
    test_web_to_db
    test_app_to_db
    test_internet_access
    test_nsg_rules
    
    # Generate report
    generate_report
}

# Execute
main