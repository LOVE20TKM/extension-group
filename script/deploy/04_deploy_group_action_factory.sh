echo "Deploying ExtensionGroupActionFactory..."
echo "Note: GroupManager, GroupJoin, and GroupVerify must be deployed first"
echo "Note: Singletons will be initialized separately using 06_initialize_singletons.sh"
forge_script ../DeployGroupActionFactory.s.sol:DeployGroupActionFactory --sig "run()"

