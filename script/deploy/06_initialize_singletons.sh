#!/bin/bash

# Initialize GroupManager, GroupJoin, and GroupVerify singletons
# This script must be called after GroupActionFactory is deployed

echo "Initializing GroupManager, GroupJoin, and GroupVerify..."

# Ensure environment is initialized
if [ -z "$network_dir" ]; then
    source 00_init.sh $network
fi

# Load addresses
source $network_dir/address.extension.group.params
source $network_dir/address.group.params

# Validate addresses
if [ -z "$groupManagerAddress" ] || [ -z "$groupJoinAddress" ] || [ -z "$groupVerifyAddress" ] || [ -z "$groupActionFactoryAddress" ]; then
    echo -e "\033[31mError:\033[0m Required addresses not found in params file"
    echo "  groupManagerAddress: $groupManagerAddress"
    echo "  groupJoinAddress: $groupJoinAddress"
    echo "  groupVerifyAddress: $groupVerifyAddress"
    echo "  groupActionFactoryAddress: $groupActionFactoryAddress"
    return 1
fi

# Initialize GroupManager
echo "Initializing GroupManager at $groupManagerAddress..."
cast send $groupManagerAddress \
    "initialize(address)" \
    $groupActionFactoryAddress \
    --rpc-url $RPC_URL \
    --account $KEYSTORE_ACCOUNT \
    --password "$KEYSTORE_PASSWORD" \
    --gas-price 5000000000 \
    --legacy

if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize GroupManager"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupManager initialized"

# Initialize GroupJoin
echo "Initializing GroupJoin at $groupJoinAddress..."
cast send $groupJoinAddress \
    "initialize(address)" \
    $groupActionFactoryAddress \
    --rpc-url $RPC_URL \
    --account $KEYSTORE_ACCOUNT \
    --password "$KEYSTORE_PASSWORD" \
    --gas-price 5000000000 \
    --legacy

if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize GroupJoin"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupJoin initialized"

# Initialize GroupVerify
echo "Initializing GroupVerify at $groupVerifyAddress..."
cast send $groupVerifyAddress \
    "initialize(address)" \
    $groupActionFactoryAddress \
    --rpc-url $RPC_URL \
    --account $KEYSTORE_ACCOUNT \
    --password "$KEYSTORE_PASSWORD" \
    --gas-price 5000000000 \
    --legacy

if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize GroupVerify"
    return 1
fi
echo -e "\033[32m✓\033[0m GroupVerify initialized"

echo -e "\033[32m✓\033[0m All singletons initialized successfully"

