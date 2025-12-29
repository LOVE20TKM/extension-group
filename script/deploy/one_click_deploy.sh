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
echo -e "\n[Step 1/9] Initializing environment..."
source 00_init.sh $network
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize environment"
    return 1
fi

# ------ Step 2: Deploy GroupManager (singleton) ------
echo -e "\n[Step 2/9] Deploying GroupManager..."
source 01_deploy_group_manager.sh
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

# ------ Step 3: Deploy GroupJoin (singleton) ------
echo -e "\n[Step 3/9] Deploying GroupJoin..."
source 02_deploy_group_join.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupJoin deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -z "$groupJoinAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupJoin address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupJoin deployed at: $groupJoinAddress"

# ------ Step 4: Deploy GroupVerify (singleton) ------
echo -e "\n[Step 4/9] Deploying GroupVerify..."
source 03_deploy_group_verify.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupVerify deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -z "$groupVerifyAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupVerify address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupVerify deployed at: $groupVerifyAddress"

# ------ Step 5: Deploy GroupActionFactory ------
echo -e "\n[Step 5/9] Deploying LOVE20ExtensionGroupActionFactory..."
source 04_deploy_group_action_factory.sh
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

# ------ Step 6: Deploy GroupServiceFactory ------
echo -e "\n[Step 6/9] Deploying LOVE20ExtensionGroupServiceFactory..."
source 05_deploy_group_service_factory.sh
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

# ------ Step 7: Initialize Singletons ------
echo -e "\n[Step 7/9] Initializing GroupManager, GroupJoin, and GroupVerify..."
echo -e "  (All contracts deployed, now initializing singletons)"
source 06_initialize_singletons.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Singletons initialization failed"
    return 1
fi
echo -e "\033[32m✓\033[0m Singletons initialized successfully"

# ------ Step 8: Verify contracts (for thinkium70001 networks) ------
echo -e "\n[Step 8/9] Verifying contracts..."
source 07_verify.sh

# ------ Step 9: Run deployment checks ------
echo -e "\n[Step 9/9] Running deployment checks..."
source 999_check.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Deployment checks failed"
    return 1
fi

echo -e "\n========================================="
echo -e "\033[32m✓ Deployment completed successfully!\033[0m"
echo -e "========================================="
echo -e "GroupManager:        $groupManagerAddress"
echo -e "GroupJoin:           $groupJoinAddress"
echo -e "GroupVerify:         $groupVerifyAddress"
echo -e "GroupActionFactory:  $groupActionFactoryAddress"
echo -e "GroupServiceFactory: $groupServiceFactoryAddress"
echo -e "Network: $network"
echo -e "=========================================\n"
