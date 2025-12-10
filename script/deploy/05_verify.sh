#!/bin/bash

if [[ "$network" != thinkium70001* ]]; then
  echo "Network is not thinkium70001 related, skipping verification"
  return 0
fi

# Ensure environment is initialized
if [ -z "$RPC_URL" ]; then
    source 00_init.sh $network
fi

# Ensure addresses are loaded
source $network_dir/address.extension.group.params

verify_contract(){
  local contract_address=$1
  local contract_name=$2
  local contract_path=$3

  echo "Verifying contract: $contract_name at $contract_address"

  forge verify-contract \
    --chain-id $CHAIN_ID \
    --verifier $VERIFIER \
    --verifier-url $VERIFIER_URL \
    $contract_address \
    $contract_path:$contract_name

  if [ $? -eq 0 ]; then
    echo -e "\033[32m✓\033[0m Contract $contract_name verified successfully"
    return 0
  else
    echo -e "\033[31m✗\033[0m Failed to verify contract $contract_name"
    return 1
  fi
}
echo "verify_contract() loaded"

# Verify LOVE20GroupDistrust
if [ -n "$groupDistrustAddress" ]; then
    verify_contract $groupDistrustAddress "LOVE20GroupDistrust" "src/LOVE20GroupDistrust.sol"
fi

# Verify LOVE20GroupManager
if [ -n "$groupManagerAddress" ]; then
    verify_contract $groupManagerAddress "LOVE20GroupManager" "src/LOVE20GroupManager.sol"
fi

# Verify LOVE20ExtensionGroupActionFactory
if [ -n "$groupActionFactoryAddress" ]; then
    verify_contract $groupActionFactoryAddress "LOVE20ExtensionGroupActionFactory" "src/LOVE20ExtensionGroupActionFactory.sol"
fi

# Verify LOVE20ExtensionGroupServiceFactory
if [ -n "$groupServiceFactoryAddress" ]; then
    verify_contract $groupServiceFactoryAddress "LOVE20ExtensionGroupServiceFactory" "src/LOVE20ExtensionGroupServiceFactory.sol"
fi
