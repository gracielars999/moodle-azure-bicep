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
    Set-IniDirective -Path $phpIni -Key 'memory_limit' -Value '256M'
    Set-IniDirective -Path $phpIni -Key 'upload_max_filesize' -Value '128M'
    Set-IniDirective -Path $phpIni -Key 'post_max_size' -Value '128M'
    Set-IniDirective -Path $phpIni -Key 'max_execution_time' -Value '300'
    Set-IniDirective -Path $phpIni -Key 'opcache.enable' -Value '1'
    Set-IniDirective -Path $phpIni -Key 'opcache.enable_cli' -Value '1'
    Set-IniDirective -Path $phpIni -Key 'opcache.memory_consumption' -Value '192'
    Set-IniDirective -Path $phpIni -Key 'opcache.interned_strings_buffer' -Value '16'
    Set-IniDirective -Path $phpIni -Key 'opcache.max_accelerated_files' -Value '10000'
    Set-IniDirective -Path $phpIni -Key 'opcache.revalidate_freq' -Value '60'
    Set-IniDirective -Path $phpIni -Key 'cgi.fix_pathinfo' -Value '1'

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
    # Controller serves from local disk too — same pattern as VMSS nodes
    New-Item -ItemType Directory -Force -Path 'C:\moodle\html' | Out-Null
    # Initial copy from Azure Files to local
    $robocopyArgs = @('Y:\html', 'C:\moodle\html', '/MIR', '/Z', '/MT:8', '/NP')
    & robocopy @robocopyArgs
    if ($LASTEXITCODE -gt 7) { throw "Initial Robocopy failed: $LASTEXITCODE" }

    if (-not (Test-Path 'IIS:\Sites\Moodle')) {
        New-Website -Name 'Moodle' -Port 80 -PhysicalPath 'C:\moodle\html' -ApplicationPool 'MoodleAppPool' | Out-Null
    } else {
        Set-ItemProperty 'IIS:\Sites\Moodle' -Name physicalPath -Value 'C:\moodle\html'
    }
}

Install-IISAndPhpPrerequisites
Install-GitForWindows
Mount-MoodleShares
Install-Moodle          # Downloads Moodle to Y:\html (Azure Files — source of truth)
Set-ControllerIISSite   # Copies Y:\html → C:\moodle\html, points IIS to local
Register-MoodleCron     # cron.php runs from local disk
