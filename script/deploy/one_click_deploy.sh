#!/bin/bash

# ------ Validate network parameter ------
export network=$1
if [ -z "$network" ] || [ ! -d "../network/$network" ]; then
    echo -e "\033[31mError:\033[0m Network parameter is required."
    echo -e "\nAvailable networks:"
    for net in $(ls ../network); do
        echo "  - $net"
    done
    return 1
fi

echo -e "\n========================================="
echo -e "  One-Click Deploy Group Extension"
echo -e "  Network: $network"
echo -e "=========================================\n"

# ------ Step 1: Initialize environment ------
echo -e "\n[Step 1/5] Initializing environment..."
source 00_init.sh $network
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize environment"
    return 1
fi

# ------ Step 2: Deploy GroupActionFactory ------
echo -e "\n[Step 2/5] Deploying LOVE20ExtensionGroupActionFactory..."
forge_script_deploy_group_action_factory
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupActionFactory deployment failed"
    return 1
fi

# Load deployed address
source $network_dir/address.extension.group.params
if [ -z "$groupActionFactoryAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupActionFactory address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupActionFactory deployed at: $groupActionFactoryAddress"

# ------ Step 3: Deploy GroupServiceFactory ------
echo -e "\n[Step 3/5] Deploying LOVE20ExtensionGroupServiceFactory..."
forge_script_deploy_group_service_factory
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupServiceFactory deployment failed"
    return 1
fi

# Reload deployed addresses
source $network_dir/address.extension.group.params
if [ -z "$groupServiceFactoryAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupServiceFactory address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupServiceFactory deployed at: $groupServiceFactoryAddress"

# ------ Step 4: Verify contracts (for thinkium70001 networks) ------
if [[ "$network" == thinkium70001* ]]; then
    echo -e "\n[Step 4/5] Verifying contracts on explorer..."
    source 03_verify.sh
    if [ $? -ne 0 ]; then
        echo -e "\033[33mWarning:\033[0m Contract verification failed (deployment is still successful)"
    else
        echo -e "\033[32m✓\033[0m Contracts verified successfully"
    fi
else
    echo -e "\n[Step 4/5] Skipping contract verification (not a thinkium network)"
fi

# ------ Step 5: Run deployment checks ------
echo -e "\n[Step 5/5] Running deployment checks..."
source 99_check.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Deployment checks failed"
    return 1
fi

echo -e "\n========================================="
echo -e "\033[32m✓ Deployment completed successfully!\033[0m"
echo -e "========================================="
echo -e "GroupActionFactory:  $groupActionFactoryAddress"
echo -e "GroupServiceFactory: $groupServiceFactoryAddress"
echo -e "Network: $network"
echo -e "=========================================\n"

