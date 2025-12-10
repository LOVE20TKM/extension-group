# ------ set network ------
export network=$1
if [ -z "$network" ] || [ ! -d "../network/$network" ]; then
    echo -e "\033[31mError:\033[0m Network parameter is required."
    echo -e "\nAvailable networks:"
    for net in $(ls ../network); do
        echo "  - $net"
    done
    return 1
fi

# ------ dont change below ------
network_dir="../network/$network"

source $network_dir/.account && \
source $network_dir/network.params && \
source $network_dir/LOVE20.params && \
source $network_dir/WETH.params && \
source $network_dir/address.params && \
source $network_dir/address.extension.center.params

# ------ Request keystore password ------
echo -e "\nPlease enter keystore password (for $KEYSTORE_ACCOUNT):"
read -s KEYSTORE_PASSWORD
export KEYSTORE_PASSWORD
echo "Password saved, will not be requested again in this session"

cast_call() {
    local address=$1
    local function_signature=$2
    shift 2
    local args=("$@")

    cast call "$address" \
        "$function_signature" \
        "${args[@]}" \
        --rpc-url "$RPC_URL" \
        --account "$KEYSTORE_ACCOUNT" \
        --password "$KEYSTORE_PASSWORD"
}
echo "cast_call() loaded"

check_equal() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    
    expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
    actual=$(echo "$actual" | tr '[:upper:]' '[:lower:]')
    
    if [ "$expected" = "$actual" ]; then
        echo -e "\033[32m✓\033[0m $description"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        return 0
    else
        echo -e "\033[31m✗\033[0m $description"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        return 1
    fi
}
echo "check_equal() loaded"

forge_script() {
  forge script "$@" \
    --rpc-url $RPC_URL \
    --account $KEYSTORE_ACCOUNT \
    --sender $ACCOUNT_ADDRESS \
    --password "$KEYSTORE_PASSWORD" \
    --gas-price 5000000000 \
    --gas-limit 50000000 \
    --broadcast \
    --legacy \
    $([[ "$network" != "anvil" ]] && [[ "$network" != thinkium* ]] && echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY")
}
echo "forge_script() loaded"

forge_script_deploy_group_action_factory() {
  forge_script ../DeployGroupActionFactory.s.sol:DeployGroupActionFactory --sig "run()"
}
echo "forge_script_deploy_group_action_factory() loaded"

forge_script_deploy_group_service_factory() {
  forge_script ../DeployGroupServiceFactory.s.sol:DeployGroupServiceFactory --sig "run()"
}
echo "forge_script_deploy_group_service_factory() loaded"

forge_script_deploy_group_distrust() {
  forge_script ../DeployGroupDistrust.s.sol:DeployGroupDistrust --sig "run()"
}
echo "forge_script_deploy_group_distrust() loaded"

forge_script_deploy_group_manager() {
  forge_script ../DeployGroupManager.s.sol:DeployGroupManager --sig "run()"
}
echo "forge_script_deploy_group_manager() loaded"

