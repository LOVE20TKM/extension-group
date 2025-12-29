echo "Deploying LOVE20ExtensionGroupServiceFactory..."
# #region agent log
LOG_FILE="../../.cursor/debug.log"
echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"E\",\"location\":\"05_deploy_group_service_factory.sh:2\",\"message\":\"Starting forge_script for GroupServiceFactory\",\"data\":{\"network\":\"$network\"},\"timestamp\":$(date +%s)000}" >> "$LOG_FILE"
GAF_ADDR=$(grep groupActionFactoryAddress ../network/$network/address.extension.group.params | cut -d= -f2)
echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"E\",\"location\":\"05_deploy_group_service_factory.sh:4\",\"message\":\"GroupActionFactory address from params\",\"data\":{\"groupActionFactoryAddress\":\"$GAF_ADDR\"},\"timestamp\":$(date +%s)000}" >> "$LOG_FILE"
# #endregion
forge_script ../DeployGroupServiceFactory.s.sol:DeployGroupServiceFactory --sig "run()"
# #region agent log
EXIT_CODE=$?
echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"E\",\"location\":\"05_deploy_group_service_factory.sh:7\",\"message\":\"forge_script exit code\",\"data\":{\"exitCode\":$EXIT_CODE},\"timestamp\":$(date +%s)000}" >> "$LOG_FILE"
if [ $EXIT_CODE -ne 0 ]; then
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"E\",\"location\":\"05_deploy_group_service_factory.sh:10\",\"message\":\"forge_script failed\",\"data\":{\"exitCode\":$EXIT_CODE},\"timestamp\":$(date +%s)000}" >> "$LOG_FILE"
fi
# #endregion

