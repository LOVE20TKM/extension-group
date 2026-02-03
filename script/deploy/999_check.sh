echo "===================="
echo "       check        "
echo "===================="

base_dir="../network/$network"
check_failed=0

source "$base_dir/address.extension.center.params"
source "$base_dir/address.group.params"
source "$base_dir/address.extension.group.params"

echo "-------------------- expected addresses --------------------"
echo "  centerAddress: $centerAddress"
echo "  groupAddress: $groupAddress"

echo "-------------------- GroupManager check --------------------"
if [ -n "$groupManagerAddress" ]; then
    echo "  groupManagerAddress: $groupManagerAddress"
    check_equal "GroupManager: FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupManagerAddress "FACTORY_ADDRESS()(address)") || ((check_failed++))
    if [ -n "$groupActionFactoryAddress" ]; then
        check_equal "GroupManager factory: GROUP_ADDRESS" $groupAddress $(cast_call $groupActionFactoryAddress "GROUP_ADDRESS()(address)") || ((check_failed++))
        check_equal "GroupManager factory: center" $centerAddress $(cast_call $groupActionFactoryAddress "CENTER_ADDRESS()(address)") || ((check_failed++))
    fi
else
    echo "(warning) GroupManager not deployed"
fi

echo "-------------------- GroupJoin check --------------------"
if [ -n "$groupJoinAddress" ]; then
    echo "  groupJoinAddress: $groupJoinAddress"
    check_equal "GroupJoin: FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupJoinAddress "FACTORY_ADDRESS()(address)") || ((check_failed++))
else
    echo "(warning) GroupJoin not deployed"
fi

echo "-------------------- GroupVerify check --------------------"
if [ -n "$groupVerifyAddress" ]; then
    echo "  groupVerifyAddress: $groupVerifyAddress"
    check_equal "GroupVerify: FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupVerifyAddress "FACTORY_ADDRESS()(address)") || ((check_failed++))
else
    echo "(warning) GroupVerify not deployed"
fi

echo "-------------------- GroupActionFactory check --------------------"
if [ -n "$groupActionFactoryAddress" ]; then
    echo "  groupActionFactoryAddress: $groupActionFactoryAddress"
    check_equal "GroupActionFactory: center" $centerAddress $(cast_call $groupActionFactoryAddress "CENTER_ADDRESS()(address)") || ((check_failed++))
    check_equal "GroupActionFactory: GROUP_MANAGER_ADDRESS" $groupManagerAddress $(cast_call $groupActionFactoryAddress "GROUP_MANAGER_ADDRESS()(address)") || ((check_failed++))
    check_equal "GroupActionFactory: GROUP_JOIN_ADDRESS" $groupJoinAddress $(cast_call $groupActionFactoryAddress "GROUP_JOIN_ADDRESS()(address)") || ((check_failed++))
    check_equal "GroupActionFactory: GROUP_VERIFY_ADDRESS" $groupVerifyAddress $(cast_call $groupActionFactoryAddress "GROUP_VERIFY_ADDRESS()(address)") || ((check_failed++))
    check_equal "GroupActionFactory: GROUP_ADDRESS" $groupAddress $(cast_call $groupActionFactoryAddress "GROUP_ADDRESS()(address)") || ((check_failed++))
else
    echo "(warning) GroupActionFactory not deployed"
fi

echo "-------------------- GroupServiceFactory check --------------------"
if [ -n "$groupServiceFactoryAddress" ]; then
    echo "  groupServiceFactoryAddress: $groupServiceFactoryAddress"
    check_equal "GroupServiceFactory: center" $centerAddress $(cast_call $groupServiceFactoryAddress "CENTER_ADDRESS()(address)") || ((check_failed++))
    check_equal "GroupServiceFactory: GROUP_ACTION_FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupServiceFactoryAddress "GROUP_ACTION_FACTORY_ADDRESS()(address)") || ((check_failed++))
    if [ -n "$groupRecipientsAddress" ]; then
        check_equal "GroupServiceFactory: GROUP_RECIPIENTS_ADDRESS" $groupRecipientsAddress $(cast_call $groupServiceFactoryAddress "GROUP_RECIPIENTS_ADDRESS()(address)") || ((check_failed++))
    fi
else
    echo "(warning) GroupServiceFactory not deployed"
fi

echo "-------------------- GroupRecipients check --------------------"
if [ -n "$groupRecipientsAddress" ]; then
    echo "  groupRecipientsAddress: $groupRecipientsAddress"
    if [ -n "$groupAddress" ]; then
        check_equal "GroupRecipients: GROUP_ADDRESS" $groupAddress $(cast_call $groupRecipientsAddress "GROUP_ADDRESS()(address)") || ((check_failed++))
    fi
    check_equal "GroupRecipients: PRECISION" "1000000000000000000" $(cast_call $groupRecipientsAddress "PRECISION()(uint256)") || ((check_failed++))
    check_equal "GroupRecipients: DEFAULT_MAX_RECIPIENTS" "10" $(cast_call $groupRecipientsAddress "DEFAULT_MAX_RECIPIENTS()(uint256)") || ((check_failed++))
else
    echo "(warning) GroupRecipients not deployed"
fi

echo "-------------------- address uniqueness check --------------------"
# Verify all addresses are not zero addresses
addresses=($groupManagerAddress $groupJoinAddress $groupVerifyAddress $groupActionFactoryAddress $groupRecipientsAddress $groupServiceFactoryAddress)
for addr in "${addresses[@]}"; do
    if [[ -n "$addr" && "$(echo "$addr" | tr '[:upper:]' '[:lower:]')" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "(failed) Found zero address in deployment: $addr"
        ((check_failed++))
    fi
done

# Verify all addresses are unique
non_empty_addresses=()
for addr in "${addresses[@]}"; do
    if [[ -n "$addr" ]]; then
        non_empty_addresses+=("$addr")
    fi
done
unique_addresses=($(printf '%s\n' "${non_empty_addresses[@]}" | sort | uniq))
if [[ ${#non_empty_addresses[@]} -ne ${#unique_addresses[@]} ]]; then
    echo "(failed) Found duplicate addresses in deployment"
    ((check_failed++))
else
    echo "  (passed) All deployed addresses are unique"
fi

echo "===================="
echo "    check done      "
echo "===================="
if [ "$check_failed" -gt 0 ]; then
    echo -e "\033[31m$check_failed check(s) failed\033[0m"
    return 1
fi
return 0
