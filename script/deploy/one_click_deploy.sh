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
echo -e "\n[Step 1/7] Initializing environment..."
source 00_init.sh $network
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize environment"
    return 1
fi

# ------ Step 2: Deploy GroupDistrust (singleton) ------
echo -e "\n[Step 2/7] Deploying LOVE20GroupDistrust..."
forge_script_deploy_group_distrust
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupDistrust deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -z "$groupDistrustAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupDistrust address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupDistrust deployed at: $groupDistrustAddress"

# ------ Step 3: Deploy GroupManager (singleton) ------
echo -e "\n[Step 3/7] Deploying LOVE20GroupManager..."
forge_script_deploy_group_manager
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupManager deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -z "$groupManagerAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupManager address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupManager deployed at: $groupManagerAddress"

# ------ Step 4: Deploy GroupActionFactory ------
echo -e "\n[Step 4/7] Deploying LOVE20ExtensionGroupActionFactory..."
forge_script_deploy_group_action_factory
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupActionFactory deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -z "$groupActionFactoryAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupActionFactory address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupActionFactory deployed at: $groupActionFactoryAddress"

# ------ Step 5: Deploy GroupServiceFactory ------
echo -e "\n[Step 5/7] Deploying LOVE20ExtensionGroupServiceFactory..."
forge_script_deploy_group_service_factory
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupServiceFactory deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -z "$groupServiceFactoryAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupServiceFactory address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupServiceFactory deployed at: $groupServiceFactoryAddress"

# ------ Step 6: Verify contracts (for thinkium70001 networks) ------
if [[ "$network" == thinkium70001* ]]; then
    echo -e "\n[Step 6/7] Verifying contracts on explorer..."
    source 03_verify.sh
    if [ $? -ne 0 ]; then
        echo -e "\033[33mWarning:\033[0m Contract verification failed (deployment is still successful)"
    else
        echo -e "\033[32m✓\033[0m Contracts verified successfully"
    fi
else
    echo -e "\n[Step 6/7] Skipping contract verification (not a thinkium network)"
fi

# ------ Step 7: Run deployment checks ------
echo -e "\n[Step 7/7] Running deployment checks..."
source 99_check.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Deployment checks failed"
    return 1
fi

echo -e "\n========================================="
echo -e "\033[32m✓ Deployment completed successfully!\033[0m"
echo -e "========================================="
echo -e "GroupDistrust:       $groupDistrustAddress"
echo -e "GroupManager:        $groupManagerAddress"
echo -e "GroupActionFactory:  $groupActionFactoryAddress"
echo -e "GroupServiceFactory: $groupServiceFactoryAddress"
echo -e "Network: $network"
echo -e "=========================================\n"

