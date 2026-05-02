# 1. 準備環境
apt-get update && apt-get install -y default-jre
dotnet tool install --global dotnet-sonarscanner
export PATH="$PATH:/root/.dotnet/tools"

# 2. 清理與還原依賴 (獨立出來，若 NuGet 壞掉會在這裡報錯)
dotnet clean
dotnet restore

# 3. 啟動 SonarQube 監聽 (必須放在 Build 之前)
dotnet sonarscanner begin /k:"my-dotnet-webapp" 

# 4. 核心編譯 (加上 --no-restore 節省時間)
dotnet build -c Release --no-restore

# (可選) 5. 執行單元測試，SonarQube 會在背景收集測試結果與覆蓋率
# dotnet test -c Release --no-build --no-restore 

# 6. 結束 SonarQube 掃描並上傳報告 (必須放在 Build 之後)
dotnet sonarscanner end

# 7. 打包發佈 (加上 --no-build 表示直接拿剛剛編譯好的結果來打包)
dotnet publish -c Release -o ./publish_output --no-build --no-restore

