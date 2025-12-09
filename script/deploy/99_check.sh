#!/bin/bash

echo "========================================="
echo "Verifying Group Extension Factories"
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

# Track failures
failed_checks=0

echo -e "\nExtension Center Address: $extensionCenterAddress"

# Check GroupActionFactory
if [ -n "$groupActionFactoryAddress" ]; then
    echo -e "\nGroupActionFactory Address: $groupActionFactoryAddress"
    
    check_equal "groupActionFactory: extensionCenterAddress" $extensionCenterAddress $(cast_call $groupActionFactoryAddress "extensionCenterAddress()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
else
    echo -e "\033[33mWarning:\033[0m GroupActionFactory not deployed"
fi

# Check GroupServiceFactory
if [ -n "$groupServiceFactoryAddress" ]; then
    echo -e "\nGroupServiceFactory Address: $groupServiceFactoryAddress"
    
    check_equal "groupServiceFactory: extensionCenterAddress" $extensionCenterAddress $(cast_call $groupServiceFactoryAddress "extensionCenterAddress()(address)")
    [ $? -ne 0 ] && ((failed_checks++))
else
    echo -e "\033[33mWarning:\033[0m GroupServiceFactory not deployed"
fi

# Summary
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

