# TWDS-Traffic-Boom
一個能刷TWDS mirror的小script，使用wget來獲取檔案  
使用方法皆一樣，不過看你想選擇能夠限速的版本，又或者選擇能夠直接跑滿速度的版本
# 使用方法
把此專案clone到你的裝置上
```
git clone https://github.com/Zhuyuan0907/TWDS-Traffic-Boom
```
進入該資料夾，並且給這script權限
```
cd TWDS-Traffic-Boom
```
```
chmod +x twds-traffic.sh
```
然後你可以開個screen，以便離開ssh的時候也可以繼續刷
```
screen
```
最後打上指令
```
./twds-traffic.sh
```
enjoy!，享受開始刷TWDS流量的過程  

2025/10/28 更新
Windows Powershell 請先以系統管理員身份執行
啟動指令:
```
.\Traffic-Boom-Windows-Version.ps1 -AllowExternalDownload -Url "https://mirror.twds.com.tw/centos-stream/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-latest-x86_64-dvd1.iso" -ParallelDownloads 3
```
