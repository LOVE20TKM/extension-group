#!/bin/bash

# Deploy all contracts to anvil in the correct order
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

# 同步地址文件从子模块到主项目（部署后使用）
sync_to_main_project() {
    local submodule_dir="$1"
    local network="$2"
    
    local submodule_network_dir="$submodule_dir/script/network/$network"
    local main_network_dir="$PROJECT_ROOT/script/network/$network"
    
    if [ ! -d "$submodule_network_dir" ]; then
        echo "  Warning: Submodule network directory not found: $submodule_network_dir"
        return 0
    fi
    
    # 创建主项目网络目录（如果不存在）
    mkdir -p "$main_network_dir"
    
    # 只同步地址文件（address*.params），不包括配置文件（LOVE20.params, WETH.params 等）
    for file in "$submodule_network_dir"/address*.params; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            echo "  → Syncing $filename from submodule to main project..."
            cp "$file" "$main_network_dir/$filename"
        fi
    done
}

# 同步地址文件从主项目到子模块（部署前使用）
sync_from_main_project() {
    local submodule_dir="$1"
    local network="$2"
    local files_to_sync="$3"  # 空格分隔的文件名列表，如 "address.params address.extension.center.params"
    
    local submodule_network_dir="$submodule_dir/script/network/$network"
    local main_network_dir="$PROJECT_ROOT/script/network/$network"
    
    if [ ! -d "$main_network_dir" ]; then
        echo "  Warning: Main project network directory not found: $main_network_dir"
        return 0
    fi
    
    # 创建子模块网络目录（如果不存在）
    mkdir -p "$submodule_network_dir"
    
    # 同步指定的文件
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

# 同步必要的配置文件从主项目到子模块（部署前使用）
sync_config_files() {
    local submodule_dir="$1"
    local network="$2"
    
    local submodule_network_dir="$submodule_dir/script/network/$network"
    local main_network_dir="$PROJECT_ROOT/script/network/$network"
    
    if [ ! -d "$main_network_dir" ]; then
        echo "  Warning: Main project network directory not found: $main_network_dir"
        return 0
    fi
    
    # 创建子模块网络目录（如果不存在）
    mkdir -p "$submodule_network_dir"
    
    # 同步必要的配置文件（如果子模块中没有）
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
# 部署后：同步 Core 的地址文件到主项目
echo "  Syncing Core deployment addresses to main project..."
sync_to_main_project "$PROJECT_ROOT/lib/extension/lib/core" "$network"

# Step 2: Deploy Extension Center
echo ""
echo "[Step 2/4] Deploying Extension Center..."
# 部署前：从主项目同步必要的配置文件和 Step 1 的地址文件到 Extension 子模块目录
echo "  Syncing dependencies from main project to Extension submodule..."
sync_config_files "$PROJECT_ROOT/lib/extension" "$network"
sync_from_main_project "$PROJECT_ROOT/lib/extension" "$network" "address.params"
cd "$PROJECT_ROOT/lib/extension/script/deploy"
run_with_password "one_click_deploy.sh" "$KEYSTORE_PASSWORD"
cd "$PROJECT_ROOT"
# 部署后：同步 Extension Center 的地址文件到主项目
echo "  Syncing Extension Center deployment addresses to main project..."
sync_to_main_project "$PROJECT_ROOT/lib/extension" "$network"

# Step 3: Deploy Group
echo ""
echo "[Step 3/4] Deploying Group..."
# 部署前：从主项目同步必要的配置文件和 Step 1 的地址文件到 Group 子模块目录
echo "  Syncing dependencies from main project to Group submodule..."
sync_config_files "$PROJECT_ROOT/lib/group" "$network"
sync_from_main_project "$PROJECT_ROOT/lib/group" "$network" "address.params"
cd "$PROJECT_ROOT/lib/group/script/deploy"
run_with_password "one_click_deploy.sh" "$KEYSTORE_PASSWORD"
cd "$PROJECT_ROOT"
# 部署后：同步 Group 的地址文件到主项目
echo "  Syncing Group deployment addresses to main project..."
sync_to_main_project "$PROJECT_ROOT/lib/group" "$network"

# Step 4: Deploy Group Extension
echo ""
echo "[Step 4/4] Deploying Group Extension..."
# 部署前：从主项目同步所有依赖的地址文件到主项目 script/deploy 目录（如果需要）
# 注意：Step 4 在主项目目录运行，所以不需要同步到子模块
# 但为了确保文件存在，可以验证一下
echo "  Verifying dependencies in main project..."
cd "$PROJECT_ROOT/script/deploy"
source 00_init.sh anvil
bash one_click_deploy.sh anvil
cd "$PROJECT_ROOT"
# Step 4 在主项目目录，地址文件直接写入主项目，不需要同步

echo ""
echo "========================================="
echo "  ✓ All deployments completed!"
echo "========================================="

