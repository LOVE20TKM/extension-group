echo "===================="
echo "       check        "
echo "===================="

base_dir="../network/$network"

source "$base_dir/address.extension.center.params"
source "$base_dir/address.group.params"
source "$base_dir/address.extension.group.params"

echo "-------------------- expected addresses --------------------"
echo "  centerAddress: $centerAddress"
echo "  groupAddress: $groupAddress"

echo "-------------------- GroupManager check --------------------"
if [ -n "$groupManagerAddress" ]; then
    echo "  groupManagerAddress: $groupManagerAddress"
    check_equal "GroupManager: FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupManagerAddress "FACTORY_ADDRESS()(address)")
    # Verify addresses through factory
    if [ -n "$groupActionFactoryAddress" ]; then
        check_equal "GroupManager factory: GROUP_ADDRESS" $groupAddress $(cast_call $groupActionFactoryAddress "GROUP_ADDRESS()(address)")
        check_equal "GroupManager factory: center" $centerAddress $(cast_call $groupActionFactoryAddress "CENTER_ADDRESS()(address)")
    fi
else
    echo "(warning) GroupManager not deployed"
fi

echo "-------------------- GroupJoin check --------------------"
if [ -n "$groupJoinAddress" ]; then
    echo "  groupJoinAddress: $groupJoinAddress"
    check_equal "GroupJoin: FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupJoinAddress "FACTORY_ADDRESS()(address)")
else
    echo "(warning) GroupJoin not deployed"
fi

echo "-------------------- GroupVerify check --------------------"
if [ -n "$groupVerifyAddress" ]; then
    echo "  groupVerifyAddress: $groupVerifyAddress"
    check_equal "GroupVerify: FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupVerifyAddress "FACTORY_ADDRESS()(address)")
else
    echo "(warning) GroupVerify not deployed"
fi

echo "-------------------- GroupActionFactory check --------------------"
if [ -n "$groupActionFactoryAddress" ]; then
    echo "  groupActionFactoryAddress: $groupActionFactoryAddress"
    check_equal "GroupActionFactory: center" $centerAddress $(cast_call $groupActionFactoryAddress "CENTER_ADDRESS()(address)")
    check_equal "GroupActionFactory: GROUP_MANAGER_ADDRESS" $groupManagerAddress $(cast_call $groupActionFactoryAddress "GROUP_MANAGER_ADDRESS()(address)")
    check_equal "GroupActionFactory: GROUP_JOIN_ADDRESS" $groupJoinAddress $(cast_call $groupActionFactoryAddress "GROUP_JOIN_ADDRESS()(address)")
    check_equal "GroupActionFactory: GROUP_VERIFY_ADDRESS" $groupVerifyAddress $(cast_call $groupActionFactoryAddress "GROUP_VERIFY_ADDRESS()(address)")
    check_equal "GroupActionFactory: GROUP_ADDRESS" $groupAddress $(cast_call $groupActionFactoryAddress "GROUP_ADDRESS()(address)")
else
    echo "(warning) GroupActionFactory not deployed"
fi

echo "-------------------- GroupServiceFactory check --------------------"
if [ -n "$groupServiceFactoryAddress" ]; then
    echo "  groupServiceFactoryAddress: $groupServiceFactoryAddress"
    check_equal "GroupServiceFactory: center" $centerAddress $(cast_call $groupServiceFactoryAddress "CENTER_ADDRESS()(address)")
    check_equal "GroupServiceFactory: GROUP_ACTION_FACTORY_ADDRESS" $groupActionFactoryAddress $(cast_call $groupServiceFactoryAddress "GROUP_ACTION_FACTORY_ADDRESS()(address)")
else
    echo "(warning) GroupServiceFactory not deployed"
fi

echo "-------------------- address uniqueness check --------------------"
# Verify all addresses are not zero addresses
addresses=($groupManagerAddress $groupJoinAddress $groupVerifyAddress $groupActionFactoryAddress $groupServiceFactoryAddress)
for addr in "${addresses[@]}"; do
    if [[ -n "$addr" && "$addr" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "(failed) Found zero address in deployment: $addr"
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
else
    echo "  (passed) All deployed addresses are unique"
fi

echo "===================="
echo "    check done      "
echo "===================="
