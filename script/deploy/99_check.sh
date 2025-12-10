#!/bin/bash

echo "========================================="
echo "Verifying Group Extension Contracts"
echo "========================================="

# Ensure environment is initialized
if [ -z "$extensionCenterAddress" ]; then
    echo -e "\033[31mError:\033[0m Extension center address not set"
    return 1
fi

# Load deployed addresses
if [ -f "$network_dir/address.extension.group.params" ]; then
    source $network_dir/address.extension.group.params
fi

if [ -f "$network_dir/address.group.params" ]; then
    source $network_dir/address.group.params
fi

# Track failures
failed_checks=0

echo -e "\n--- Expected Addresses ---"
echo "extensionCenterAddress: $extensionCenterAddress"
echo "groupAddress: $groupAddress"
echo "stakeAddress: $stakeAddress"
echo "joinAddress: $joinAddress"
echo "verifyAddress: $verifyAddress"

# ============ Check GroupDistrust ============
if [ -n "$groupDistrustAddress" ]; then
    echo -e "\n--- GroupDistrust: $groupDistrustAddress ---"
    
    # GroupDistrust doesn't expose internal variables directly
    # We verify by checking it has code deployed
    code_size=$(cast code $groupDistrustAddress --rpc-url $RPC_URL | wc -c)
    if [ "$code_size" -gt 2 ]; then
        echo -e "\033[32m✓\033[0m GroupDistrust: contract deployed"
    else
        echo -e "\033[31m✗\033[0m GroupDistrust: contract not deployed"
        ((failed_checks++))
    fi
else
    echo -e "\n\033[33mWarning:\033[0m GroupDistrust not deployed"
fi

# ============ Check GroupManager ============
if [ -n "$groupManagerAddress" ]; then
    echo -e "\n--- GroupManager: $groupManagerAddress ---"
    
    check_equal "GroupManager: CENTER_ADDRESS" \
        $extensionCenterAddress \
        $(cast_call $groupManagerAddress "CENTER_ADDRESS()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
    
    check_equal "GroupManager: GROUP_ADDRESS" \
        $groupAddress \
        $(cast_call $groupManagerAddress "GROUP_ADDRESS()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
    
    check_equal "GroupManager: STAKE_ADDRESS" \
        $stakeAddress \
        $(cast_call $groupManagerAddress "STAKE_ADDRESS()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
    
    check_equal "GroupManager: JOIN_ADDRESS" \
        $joinAddress \
        $(cast_call $groupManagerAddress "JOIN_ADDRESS()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
else
    echo -e "\n\033[33mWarning:\033[0m GroupManager not deployed"
fi

# ============ Check GroupActionFactory ============
if [ -n "$groupActionFactoryAddress" ]; then
    echo -e "\n--- GroupActionFactory: $groupActionFactoryAddress ---"
    
    check_equal "GroupActionFactory: center" \
        $extensionCenterAddress \
        $(cast_call $groupActionFactoryAddress "center()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
else
    echo -e "\n\033[33mWarning:\033[0m GroupActionFactory not deployed"
fi

# ============ Check GroupServiceFactory ============
if [ -n "$groupServiceFactoryAddress" ]; then
    echo -e "\n--- GroupServiceFactory: $groupServiceFactoryAddress ---"
    
    check_equal "GroupServiceFactory: center" \
        $extensionCenterAddress \
        $(cast_call $groupServiceFactoryAddress "center()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
else
    echo -e "\n\033[33mWarning:\033[0m GroupServiceFactory not deployed"
fi

# ============ Summary ============
echo -e "\n========================================="
if [ $failed_checks -eq 0 ]; then
    echo -e "\033[32m✓ All checks passed\033[0m"
    echo "========================================="
    return 0
else
    echo -e "\033[31m✗ $failed_checks check(s) failed\033[0m"
    echo "========================================="
    return 1
fi

