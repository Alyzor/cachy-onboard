Step 1: get windows app list

```
$paths = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
         'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'

Get-ItemProperty $paths -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
  Select-Object -ExpandProperty DisplayName |
  Sort-Object -Unique |
  ForEach-Object { ($_ -replace ' \d[\d.]*$','').ToLower() -replace ' ','-' } | | Set-Content windows-apps.txt
```

Step 2: linux install

Step 3: check windows app list against pacman/aur (check-apps.sh)

Step 4/5: double check app list under apps.txt (remove unwanted apps) and run onboard.sh 

Step 6: check apps.manual.txt for missing apps and install manually

Step 7: reboot & it's done
