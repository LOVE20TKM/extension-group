echo "Deploying GroupNotice..."
echo "Note: Requires groupAddress from address.group.params"
forge_script ../DeployGroupNotice.s.sol:DeployGroupNotice --sig "run()"
