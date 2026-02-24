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

# Verify GroupManager
if [ -n "$groupManagerAddress" ]; then
    verify_contract $groupManagerAddress "GroupManager" "src/GroupManager.sol"
fi

# Verify GroupJoin
if [ -n "$groupJoinAddress" ]; then
    verify_contract $groupJoinAddress "GroupJoin" "src/GroupJoin.sol"
fi

# Verify GroupVerify
if [ -n "$groupVerifyAddress" ]; then
    verify_contract $groupVerifyAddress "GroupVerify" "src/GroupVerify.sol"
fi

# Verify ExtensionGroupActionFactory
if [ -n "$groupActionFactoryAddress" ]; then
    verify_contract $groupActionFactoryAddress "ExtensionGroupActionFactory" "src/ExtensionGroupActionFactory.sol"
fi

# Verify GroupRecipients
if [ -n "$groupRecipientsAddress" ]; then
    verify_contract $groupRecipientsAddress "GroupRecipients" "src/GroupRecipients.sol"
fi

# Verify GroupNotice
if [ -n "$groupNoticeAddress" ]; then
    verify_contract $groupNoticeAddress "GroupNotice" "src/GroupNotice.sol"
fi

# Verify ExtensionGroupServiceFactory
if [ -n "$groupServiceFactoryAddress" ]; then
    verify_contract $groupServiceFactoryAddress "ExtensionGroupServiceFactory" "src/ExtensionGroupServiceFactory.sol"
fi
