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
echo -e "\n[Step 1/11] Initializing environment..."
source 00_init.sh $network
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize environment"
    return 1
fi

# ------ Step 2: Deploy GroupManager (singleton) ------
echo -e "\n[Step 2/11] Deploying GroupManager..."
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
echo -e "\n[Step 3/11] Deploying GroupJoin..."
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
echo -e "\n[Step 4/11] Deploying GroupVerify..."
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
echo -e "\n[Step 5/11] Deploying ExtensionGroupActionFactory..."
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

# ------ Step 6: Deploy GroupRecipients (singleton) ------
echo -e "\n[Step 6/11] Deploying GroupRecipients..."
source 05_deploy_group_recipients.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupRecipients deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -z "$groupRecipientsAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupRecipients address not found"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupRecipients deployed at: $groupRecipientsAddress"

# ------ Step 7: Deploy GroupNotice ------
echo -e "\n[Step 7/11] Deploying GroupNotice..."
source 05a_deploy_group_notice.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m GroupNotice deployment failed"
    return 1
fi

source $network_dir/address.extension.group.params
if [ -n "$groupNoticeAddress" ]; then
    echo -e "\033[32m✓\033[0m GroupNotice deployed at: $groupNoticeAddress"
fi

# ------ Step 8: Deploy GroupServiceFactory ------
echo -e "\n[Step 8/11] Deploying ExtensionGroupServiceFactory..."
source 06_deploy_group_service_factory.sh
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

# ------ Step 9: Initialize Singletons ------
echo -e "\n[Step 9/11] Initializing GroupManager, GroupJoin, and GroupVerify..."
echo -e "  (GroupRecipients has no initialize; it is constructed with the GroupActionFactory address)"
source 06_initialize_singletons.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Singletons initialization failed"
    return 1
fi
echo -e "\033[32m✓\033[0m Singletons initialized successfully"

# ------ Step 10: Verify contracts (for thinkium70001 networks) ------
echo -e "\n[Step 10/11] Verifying contracts..."
source 07_verify.sh

# ------ Step 11: Run deployment checks ------
echo -e "\n[Step 11/11] Running deployment checks..."
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
echo -e "GroupRecipients:     $groupRecipientsAddress"
echo -e "GroupNotice:         $groupNoticeAddress"
echo -e "GroupServiceFactory: $groupServiceFactoryAddress"
echo -e "Network: $network"
echo -e "=========================================\n"
