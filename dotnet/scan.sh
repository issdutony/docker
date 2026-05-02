#!/bin/bash

dotnet-sonarscanner begin \
  /k:"InventoryApp" \
  /d:sonar.host.url="http://sonarqube:9000" \
  /d:sonar.token="sqa_79189745226e17b22d9b0607b1b7cc071b520d06"

dotnet build

dotnet-sonarscanner end /d:sonar.token="sqa_79189745226e17b22d9b0607b1b7cc071b520d06"

sleep 20 

STATUS=$(curl -s -u "sqa_79189745226e17b22d9b0607b1b7cc071b520d06:" "http://sonarqube:9000/api/qualitygates/project_status?projectKey=InventoryApp" | jq -r '.projectStatus.status')

if [ "$STATUS" = "ERROR" ]; then
	echo "Quality Gate Failed! Status: $STATUS"
	exit 1
fi
echo "Quality Gate Passed!"
