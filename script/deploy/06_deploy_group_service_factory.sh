echo "Deploying ExtensionGroupServiceFactory..."
echo "Note: GroupActionFactory (04) and GroupRecipients (05) must be deployed first"
forge_script ../DeployGroupServiceFactory.s.sol:DeployGroupServiceFactory --sig "run()"
