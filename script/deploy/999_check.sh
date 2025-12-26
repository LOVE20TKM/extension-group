echo "===================="
echo "       check        "
echo "===================="

base_dir="../network/$network"

source "$base_dir/address.params"
source "$base_dir/address.extension.center.params"
source "$base_dir/address.group.params"
source "$base_dir/address.extension.group.params"

check_equal(){
    local msg="$1"
    local expected="$2"
    local actual="$3"

    # check params
    if [ -z "$msg" ] || [ -z "$expected" ] || [ -z "$actual" ]; then
        echo "Error: 3 params needed: msg, expected, actual"
        return 1
    fi

    # remove double quotes
    actual_clean=$(echo "$actual" | sed 's/^"//;s/"$//')

    if [ "$expected" != "$actual_clean" ]; then
        echo "(failed) $msg: $expected != $actual_clean"
    else
        echo "  (passed) $msg: $expected == $actual_clean"
    fi
}

echo "-------------------- expected addresses --------------------"
echo "  centerAddress: $centerAddress"
echo "  groupAddress: $groupAddress"
echo "  stakeAddress: $stakeAddress"
echo "  joinAddress: $joinAddress"
echo "  verifyAddress: $verifyAddress"

echo "-------------------- GroupDistrust check --------------------"
if [ -n "$groupDistrustAddress" ]; then
    echo "  groupDistrustAddress: $groupDistrustAddress"
    # GroupDistrust doesn't expose internal variables directly
    # Verify by checking contract has code deployed
    code_size=$(cast code $groupDistrustAddress --rpc-url $RPC_URL | wc -c)
    if [ "$code_size" -gt 2 ]; then
        echo "  (passed) GroupDistrust: contract deployed"
    else
        echo "(failed) GroupDistrust: contract not deployed"
    fi
else
    echo "(warning) GroupDistrust not deployed"
fi

echo "-------------------- GroupManager check --------------------"
if [ -n "$groupManagerAddress" ]; then
    echo "  groupManagerAddress: $groupManagerAddress"
    check_equal "GroupManager: CENTER_ADDRESS" $centerAddress $(cast_call $groupManagerAddress "CENTER_ADDRESS()(address)")
    check_equal "GroupManager: GROUP_ADDRESS" $groupAddress $(cast_call $groupManagerAddress "GROUP_ADDRESS()(address)")
    check_equal "GroupManager: STAKE_ADDRESS" $stakeAddress $(cast_call $groupManagerAddress "STAKE_ADDRESS()(address)")
    check_equal "GroupManager: JOIN_ADDRESS" $joinAddress $(cast_call $groupManagerAddress "JOIN_ADDRESS()(address)")
else
    echo "(warning) GroupManager not deployed"
fi

echo "-------------------- GroupActionFactory check --------------------"
if [ -n "$groupActionFactoryAddress" ]; then
    echo "  groupActionFactoryAddress: $groupActionFactoryAddress"
    check_equal "GroupActionFactory: center" $centerAddress $(cast_call $groupActionFactoryAddress "center()(address)")
    check_equal "GroupActionFactory: GROUP_MANAGER_ADDRESS" $groupManagerAddress $(cast_call $groupActionFactoryAddress "GROUP_MANAGER_ADDRESS()(address)")
    check_equal "GroupActionFactory: GROUP_DISTRUST_ADDRESS" $groupDistrustAddress $(cast_call $groupActionFactoryAddress "GROUP_DISTRUST_ADDRESS()(address)")
else
    echo "(warning) GroupActionFactory not deployed"
fi

echo "-------------------- GroupServiceFactory check --------------------"
if [ -n "$groupServiceFactoryAddress" ]; then
    echo "  groupServiceFactoryAddress: $groupServiceFactoryAddress"
    check_equal "GroupServiceFactory: center" $centerAddress $(cast_call $groupServiceFactoryAddress "center()(address)")
else
    echo "(warning) GroupServiceFactory not deployed"
fi

echo "-------------------- address uniqueness check --------------------"
# Verify all addresses are not zero addresses
addresses=($groupDistrustAddress $groupManagerAddress $groupActionFactoryAddress $groupServiceFactoryAddress)
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
