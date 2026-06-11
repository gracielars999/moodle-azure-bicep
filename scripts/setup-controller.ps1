$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Install-IISAndPhpPrerequisites {
    $features = @(
        'Web-Server',
        'Web-CGI',
        'Web-ISAPI-Ext',
        'Web-ISAPI-Filter',
        'Web-Url-Auth',
        'Web-Windows-Auth',
        'Web-Mgmt-Console',
        'Web-Scripting-Tools'
    )

    Install-WindowsFeature -Name $features -IncludeManagementTools | Out-Null

    $workingDir = 'C:\moodle\install'
    $phpRoot = 'C:\PHP'
    $phpZip = Join-Path $workingDir 'php-8.2.29-nts-x64.zip'
    $rewriteMsi = Join-Path $workingDir 'rewrite_amd64_en-US.msi'
    New-Item -ItemType Directory -Force -Path $workingDir, $phpRoot, 'C:\moodle\html' | Out-Null

    if (-not (Test-Path $rewriteMsi)) {
        Invoke-WebRequest -Uri 'https://download.microsoft.com/download/D/D/9/DD9A82D8-4451-48F9-8E5E-17B3F1F0CA3A/rewrite_amd64_en-US.msi' -OutFile $rewriteMsi
    }
    Start-Process -FilePath msiexec.exe -ArgumentList '/i', $rewriteMsi, '/qn', '/norestart' -Wait

    if (-not (Test-Path $phpZip)) {
        Invoke-WebRequest -Uri 'https://windows.php.net/downloads/releases/php-8.2.29-nts-Win32-vs16-x64.zip' -OutFile $phpZip
    }

    if (Test-Path $phpRoot) {
        Get-ChildItem -Path $phpRoot -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Expand-Archive -Path $phpZip -DestinationPath $phpRoot -Force

    $phpIni = Join-Path $phpRoot 'php.ini'
    Copy-Item -Path (Join-Path $phpRoot 'php.ini-production') -Destination $phpIni -Force

    function Set-IniDirective {
        param(
            [string]$Path,
            [string]$Key,
            [string]$Value
        )

        $content = Get-Content -Path $Path -Raw
        $escapedKey = [regex]::Escape($Key)
        $replacement = "$Key = $Value"
        if ($content -match "(?m)^[;#]?\s*$escapedKey\s*=") {
            $content = [regex]::Replace($content, "(?m)^[;#]?\s*$escapedKey\s*=.*$", $replacement)
        }
        else {
            $content += "`r`n$replacement`r`n"
        }

        Set-Content -Path $Path -Value $content -Encoding ASCII
    }

    function Enable-PhpExtension {
        param(
            [string]$Path,
            [string]$ExtensionDll
        )

        $extensionPath = Join-Path $phpRoot "ext\$ExtensionDll"
        if (-not (Test-Path $extensionPath)) {
            Write-Warning "Skipping missing PHP extension $ExtensionDll"
            return
        }

        $line = "extension=$ExtensionDll"
        $content = Get-Content -Path $Path -Raw
        if ($content -notmatch [regex]::Escape($line)) {
            $content += "`r`n$line`r`n"
            Set-Content -Path $Path -Value $content -Encoding ASCII
        }
    }

    Set-IniDirective -Path $phpIni -Key 'extension_dir' -Value '"ext"'
    Set-IniDirective -Path $phpIni -Key 'memory_limit'          -Value '512M'
    Set-IniDirective -Path $phpIni -Key 'upload_max_filesize'   -Value '1024M'
    Set-IniDirective -Path $phpIni -Key 'post_max_size'         -Value '1056M'
    Set-IniDirective -Path $phpIni -Key 'max_execution_time'    -Value '18000'
    Set-IniDirective -Path $phpIni -Key 'max_input_time'        -Value '600'
    Set-IniDirective -Path $phpIni -Key 'max_input_vars'        -Value '100000'
    Set-IniDirective -Path $phpIni -Key 'opcache.enable'                   -Value '1'
    Set-IniDirective -Path $phpIni -Key 'opcache.enable_cli'               -Value '1'
    Set-IniDirective -Path $phpIni -Key 'opcache.memory_consumption'       -Value '512'
    Set-IniDirective -Path $phpIni -Key 'opcache.interned_strings_buffer'  -Value '16'
    Set-IniDirective -Path $phpIni -Key 'opcache.max_accelerated_files'    -Value '20000'
    Set-IniDirective -Path $phpIni -Key 'opcache.validate_timestamps'      -Value '1'
    Set-IniDirective -Path $phpIni -Key 'opcache.revalidate_freq'          -Value '0'
    Set-IniDirective -Path $phpIni -Key 'opcache.save_comments'            -Value '1'
    Set-IniDirective -Path $phpIni -Key 'opcache.use_cwd'                  -Value '1'
    Set-IniDirective -Path $phpIni -Key 'opcache.enable_file_override'     -Value '0'
    Set-IniDirective -Path $phpIni -Key 'cgi.fix_pathinfo'                 -Value '1'

    $extensions = @(
        'php_curl.dll',
        'php_fileinfo.dll',
        'php_gd.dll',
        'php_intl.dll',
        'php_mbstring.dll',
        'php_mysqli.dll',
        'php_openssl.dll',
        'php_soap.dll',
        'php_xmlrpc.dll',
        'php_zip.dll',
        'php_opcache.dll'
    )

    foreach ($extension in $extensions) {
        Enable-PhpExtension -Path $phpIni -ExtensionDll $extension
    }

    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config /section:system.webServer/fastCgi /+"[fullPath='C:\PHP\php-cgi.exe']" | Out-Null
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config /section:system.webServer/handlers /+"[name='PHP_via_FastCGI',path='*.php',verb='GET,HEAD,POST',modules='FastCgiModule',scriptProcessor='C:\PHP\php-cgi.exe',resourceType='Either']" | Out-Null
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config /section:system.webServer/defaultDocument /+"files.[value='index.php']" | Out-Null

    Import-Module WebAdministration
    if (-not (Test-Path 'IIS:\AppPools\MoodleAppPool')) {
        New-WebAppPool -Name 'MoodleAppPool' | Out-Null
    }
    Set-ItemProperty 'IIS:\AppPools\MoodleAppPool' -Name managedRuntimeVersion -Value ''
    Set-ItemProperty 'IIS:\AppPools\MoodleAppPool' -Name processModel.identityType -Value 'ApplicationPoolIdentity'

    if (Test-Path 'IIS:\Sites\Default Web Site') {
        Remove-Website -Name 'Default Web Site'
    }

    if (-not (Test-Path 'IIS:\Sites\Moodle')) {
        New-Website -Name 'Moodle' -Port 80 -PhysicalPath 'C:\moodle\html' -ApplicationPool 'MoodleAppPool' | Out-Null
    }
    else {
        Set-ItemProperty 'IIS:\Sites\Moodle' -Name physicalPath -Value 'C:\moodle\html'
    }

    Start-Service W3SVC
}

function Install-GitForWindows {
    $workingDir = 'C:\moodle\install'
    $gitInstaller = Join-Path $workingDir 'Git-64-bit.exe'
    if (-not (Test-Path $gitInstaller)) {
        Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe' -OutFile $gitInstaller
    }
    Start-Process -FilePath $gitInstaller -ArgumentList '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-' -Wait
}

function Mount-MoodleShares {
    $storageAccount = $env:MOODLE_STORAGE_ACCOUNT
    $dataShare     = $env:MOODLE_FILE_SHARE
    $htmlShare     = $env:MOODLE_HTML_SHARE
    $storageKey    = $env:MOODLE_STORAGE_KEY

    if ([string]::IsNullOrWhiteSpace($storageAccount) -or
        [string]::IsNullOrWhiteSpace($dataShare) -or
        [string]::IsNullOrWhiteSpace($htmlShare) -or
        [string]::IsNullOrWhiteSpace($storageKey)) {
        throw 'Storage account values were not provided to the setup script.'
    }

    cmdkey.exe /add:"$storageAccount.file.core.windows.net" /user:"localhost\$storageAccount" /pass:"$storageKey" | Out-Null

    # Z:\ -> moodledata (user files)
    if (Get-PSDrive -Name 'Z' -ErrorAction SilentlyContinue) { Remove-PSDrive -Name 'Z' -Force }
    New-PSDrive -Name 'Z' -PSProvider FileSystem -Root "\\$storageAccount.file.core.windows.net\$dataShare" -Persist -Scope Global | Out-Null
    New-Item -ItemType Directory -Force -Path 'Z:\moodledata' | Out-Null

    # Y:\ -> moodlehtml (PHP code — shared with all VMSS nodes via Azure Files)
    if (Get-PSDrive -Name 'Y' -ErrorAction SilentlyContinue) { Remove-PSDrive -Name 'Y' -Force }
    New-PSDrive -Name 'Y' -PSProvider FileSystem -Root "\\$storageAccount.file.core.windows.net\$htmlShare" -Persist -Scope Global | Out-Null
    New-Item -ItemType Directory -Force -Path 'Y:\html' | Out-Null
}

function Install-Moodle {
    $workingDir = 'C:\moodle\install'
    New-Item -ItemType Directory -Force -Path $workingDir | Out-Null
    $moodleZip = Join-Path $workingDir 'moodle-latest.zip'
    if (-not (Test-Path $moodleZip)) {
        Invoke-WebRequest -Uri 'https://download.moodle.org/latest.zip' -OutFile $moodleZip
    }

    $tempExtract = 'C:\moodle\extract'
    Expand-Archive -Path $moodleZip -DestinationPath $tempExtract -Force

    $src = if (Test-Path "$tempExtract\moodle") { "$tempExtract\moodle\*" } else { "$tempExtract\*" }
    Copy-Item -Path $src -Destination 'Y:\html' -Recurse -Force
    Remove-Item -Path $tempExtract -Recurse -Force

    # Write deploy timestamp to Azure Files — VMSS nodes watch this file.
    # Run this script again after every Moodle upgrade or plugin install
    # to signal all VMSS nodes to re-sync. Mirrors the official Azure/Moodle
    # 'update_last_modified_time.moodle_on_azure.sh' pattern.
    Update-MoodleDeployTimestamp
}

function Update-MoodleDeployTimestamp {
    # Touching this file triggers Robocopy sync on all VMSS nodes within 1 minute.
    # Run this manually on the controller after every code change to Y:\html.
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    Set-Content -Path 'Y:\html\.last_modified_time.moodle_on_azure' -Value $timestamp -Encoding UTF8
    Write-Host "Deploy timestamp updated: $timestamp — VMSS nodes will sync within ~1 minute."
}

function Register-MoodleCron {
    $taskName = 'Moodle Cron'
    # Runs from local disk C:\moodle\html (synced from Azure Files Y:\html)
    schtasks.exe /Create /TN $taskName /TR '"C:\PHP\php.exe" "C:\moodle\html\admin\cli\cron.php"' /SC MINUTE /MO 1 /RU SYSTEM /F | Out-Null
}

function Set-ControllerIISSite {
    Import-Module WebAdministration
    if (Test-Path 'IIS:\Sites\Default Web Site') { Remove-Website -Name 'Default Web Site' }
    New-Item -ItemType Directory -Force -Path 'C:\moodle\html' | Out-Null
    $robocopyArgs = @('Y:\html', 'C:\moodle\html', '/MIR', '/Z', '/MT:8', '/NP')
    & robocopy @robocopyArgs
    if ($LASTEXITCODE -gt 7) { throw "Initial Robocopy failed: $LASTEXITCODE" }

    if (-not (Test-Path 'IIS:\Sites\Moodle')) {
        New-Website -Name 'Moodle' -Port 80 -PhysicalPath 'C:\moodle\html' -ApplicationPool 'MoodleAppPool' | Out-Null
    } else {
        Set-ItemProperty 'IIS:\Sites\Moodle' -Name physicalPath -Value 'C:\moodle\html'
    }

    # Recycle App Pool after 300,000 requests — equivalent to PHP-FPM pm.max_requests=300000
    # in the official repo. Prevents PHP-CGI memory leaks in long-running processes.
    Set-ItemProperty 'IIS:\AppPools\MoodleAppPool' `
        -Name recycling.periodicRestart.requests -Value 300000
    # Also recycle daily at 03:00 as fallback (official repo recycles via process manager)
    Clear-ItemProperty 'IIS:\AppPools\MoodleAppPool' -Name recycling.periodicRestart.schedule
    $recycleTime = New-TimeSpan -Hours 3
    Add-WebConfiguration -Filter "system.applicationHost/applicationPools/add[@name='MoodleAppPool']/recycling/periodicRestart/schedule" `
        -Value @{ value = $recycleTime } -Force
}

function Register-DbBackupTask {
    # Daily MySQL dump to Azure Files Z:\ — mirrors official Azure/Moodle:
    # "22 02 * * * root mysqldump ... | gzip > /moodle/db-backup.sql.gz"
    $mysqlHost = $env:MOODLE_MYSQL_HOST
    $mysqlUser = $env:MOODLE_MYSQL_USER
    $mysqlPass = $env:MOODLE_MYSQL_PASS
    $mysqlDb   = $env:MOODLE_MYSQL_DB

    if ([string]::IsNullOrWhiteSpace($mysqlHost)) { return }  # skip if not configured

    $scriptPath = 'C:\moodle\backup-db.ps1'
    $backupScript = @"
`$ErrorActionPreference = 'Stop'
`$date = Get-Date -Format 'yyyyMMdd'
`$backupFile = "Z:\db-backup-`$date.sql.gz"
New-Item -ItemType Directory -Force -Path 'Z:\' | Out-Null
# Requires mysqldump in PATH (installed with MySQL client tools)
`$env:MYSQL_PWD = '$mysqlPass'
& mysqldump -h '$mysqlHost' -u '$mysqlUser' --databases '$mysqlDb' | `
    & { param([string]`$in) [System.IO.Compression.GZipStream]::new([System.IO.File]::Create(`$backupFile), [System.IO.Compression.CompressionMode]::Compress).Write([System.Text.Encoding]::UTF8.GetBytes(`$in), 0, `$in.Length) }
# Keep last 7 days of backups
Get-ChildItem -Path 'Z:\' -Filter 'db-backup-*.sql.gz' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 7 |
    Remove-Item -Force
"@
    Set-Content -Path $scriptPath -Value $backupScript -Encoding UTF8

    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
                    -Argument "-NonInteractive -WindowStyle Hidden -File `"$scriptPath`""
    # Daily at 02:22 — same time as official repo
    $trigger  = New-ScheduledTaskTrigger -Daily -At '02:22'
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskName 'Moodle DB Backup' -Action $action `
        -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
}

Install-IISAndPhpPrerequisites
Install-GitForWindows
Mount-MoodleShares
Install-Moodle          # Downloads Moodle to Y:\html (Azure Files — source of truth)
Set-ControllerIISSite   # Copies Y:\html → C:\moodle\html, IIS → local, App Pool recycling
Register-MoodleCron     # cron.php every 1 min from local disk
Register-DbBackupTask   # Daily mysqldump at 02:22 → Z:\db-backup-YYYYMMDD.sql.gz
