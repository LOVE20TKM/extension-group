#!/bin/bash

# Deploy all contracts to Anvil in the correct order
# Usage: bash deploy_all_to_anvil.sh

set -e

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export network=anvil
export KEYSTORE_PASSWORD=anvil

# Helper function to run scripts with automatic password input
run_with_password() {
    local script_path="$1"
    local password="$2"
    
    expect << EOF
set timeout 300
spawn bash "$script_path" anvil
expect {
    "Please enter keystore password" {
        send "$password\r"
        exp_continue
    }
    "Password saved" {
        exp_continue
    }
    eof
}
catch wait result
exit [lindex \$result 3]
EOF
}

# Sync address files from submodule to main project (used after deploy)
sync_to_main_project() {
    local submodule_dir="$1"
    local network="$2"
    
    local submodule_network_dir="$submodule_dir/script/network/$network"
    local main_network_dir="$PROJECT_ROOT/script/network/$network"
    
    if [ ! -d "$submodule_network_dir" ]; then
        echo "  Warning: Submodule network directory not found: $submodule_network_dir"
        return 0
    fi
    
    # Create the main project network directory if it doesn't exist
    mkdir -p "$main_network_dir"
    
    # Only sync address files (address*.params), not config files such as LOVE20.params, WETH.params, etc.
    for file in "$submodule_network_dir"/address*.params; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            echo "  → Syncing $filename from submodule to main project..."
            cp "$file" "$main_network_dir/$filename"
        fi
    done
}

# Sync address files from main project to submodule (used before deploy)
sync_from_main_project() {
    local submodule_dir="$1"
    local network="$2"
    local files_to_sync="$3"  # Space-separated file name list, e.g., "address.extension.center.params"
    
    local submodule_network_dir="$submodule_dir/script/network/$network"
    local main_network_dir="$PROJECT_ROOT/script/network/$network"
    
    if [ ! -d "$main_network_dir" ]; then
        echo "  Warning: Main project network directory not found: $main_network_dir"
        return 0
    fi
    
    # Create the submodule network directory if it doesn't exist
    mkdir -p "$submodule_network_dir"
    
    # Sync the specified files
    for filename in $files_to_sync; do
        local main_file="$main_network_dir/$filename"
        if [ -f "$main_file" ]; then
            echo "  ← Syncing $filename from main project to submodule..."
            cp "$main_file" "$submodule_network_dir/$filename"
        else
            echo "  Warning: File not found in main project: $filename"
        fi
    done
}

# Sync required config files from main project to submodule (used before deploy)
sync_config_files() {
    local submodule_dir="$1"
    local network="$2"
    
    local submodule_network_dir="$submodule_dir/script/network/$network"
    local main_network_dir="$PROJECT_ROOT/script/network/$network"
    
    if [ ! -d "$main_network_dir" ]; then
        echo "  Warning: Main project network directory not found: $main_network_dir"
        return 0
    fi
    
    # Create the submodule network directory if it doesn't exist
    mkdir -p "$submodule_network_dir"
    
    # Sync required config files if they do not exist in the submodule
    for filename in ".account" "network.params"; do
        local main_file="$main_network_dir/$filename"
        local submodule_file="$submodule_network_dir/$filename"
        if [ -f "$main_file" ] && [ ! -f "$submodule_file" ]; then
            echo "  ← Syncing $filename from main project to submodule..."
            cp "$main_file" "$submodule_file"
        fi
    done
}

echo "========================================="
echo "  Deploy All Contracts to Anvil"
echo "========================================="
echo ""

# Step 1: Deploy Core contracts
echo "[Step 1/4] Deploying Core contracts..."
cd "$PROJECT_ROOT/lib/extension/lib/core/script/deploy"
run_with_password "one_click_deploy.sh" "$KEYSTORE_PASSWORD"
cd "$PROJECT_ROOT"
# After deploy: sync Core address files to main project
echo "  Syncing Core deployment addresses to main project..."
sync_to_main_project "$PROJECT_ROOT/lib/extension/lib/core" "$network"

# Step 2: Deploy Extension Center
echo ""
echo "[Step 2/4] Deploying Extension Center..."
# Before deploy: sync required config files and Step 1 address files from main project to Extension submodule
echo "  Syncing dependencies from main project to Extension submodule..."
sync_config_files "$PROJECT_ROOT/lib/extension" "$network"
cd "$PROJECT_ROOT/lib/extension/script/deploy"
run_with_password "one_click_deploy.sh" "$KEYSTORE_PASSWORD"
cd "$PROJECT_ROOT"
# After deploy: sync Extension Center address files to main project
echo "  Syncing Extension Center deployment addresses to main project..."
sync_to_main_project "$PROJECT_ROOT/lib/extension" "$network"

# Step 3: Deploy Group
echo ""
echo "[Step 3/4] Deploying Group..."
# Before deploy: sync required config files and Step 1 address files from main project to Group submodule
echo "  Syncing dependencies from main project to Group submodule..."
sync_config_files "$PROJECT_ROOT/lib/group" "$network"
cd "$PROJECT_ROOT/lib/group/script/deploy"
run_with_password "one_click_deploy.sh" "$KEYSTORE_PASSWORD"
cd "$PROJECT_ROOT"
# After deploy: sync Group address files to main project
echo "  Syncing Group deployment addresses to main project..."
sync_to_main_project "$PROJECT_ROOT/lib/group" "$network"

# Step 4: Deploy Group Extension
echo ""
echo "[Step 4/4] Deploying Group Extension..."
# Before deploy: sync all dependent address files to main project script/deploy directory (if needed)
# Note: Step 4 runs in main project directory, so no sync to submodule is required
# But to be sure, dependencies in main project can be checked
echo "  Verifying dependencies in main project..."
cd "$PROJECT_ROOT/script/deploy"
source one_click_deploy.sh anvil
cd "$PROJECT_ROOT"
# Step 4 writes address files directly to main project, no sync needed

echo ""
echo "========================================="
echo "  ✓ All deployments completed!"
echo "========================================="

