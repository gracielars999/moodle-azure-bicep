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

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'Git is not required on Moodle nodes. Skipping Git installation.'
    }

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

    # Store credentials once for both shares
    cmdkey.exe /add:"$storageAccount.file.core.windows.net" /user:"localhost\$storageAccount" /pass:"$storageKey" | Out-Null

    # Z:\ -> moodledata (user files)
    if (Get-PSDrive -Name 'Z' -ErrorAction SilentlyContinue) { Remove-PSDrive -Name 'Z' -Force }
    New-PSDrive -Name 'Z' -PSProvider FileSystem -Root "\\$storageAccount.file.core.windows.net\$dataShare" -Persist -Scope Global | Out-Null
    New-Item -ItemType Directory -Force -Path 'Z:\moodledata' | Out-Null

    # Y:\ -> moodlehtml (PHP code — source of truth, written by controller)
    if (Get-PSDrive -Name 'Y' -ErrorAction SilentlyContinue) { Remove-PSDrive -Name 'Y' -Force }
    New-PSDrive -Name 'Y' -PSProvider FileSystem -Root "\\$storageAccount.file.core.windows.net\$htmlShare" -Persist -Scope Global | Out-Null
    New-Item -ItemType Directory -Force -Path 'Y:\html' | Out-Null
}

function Sync-MoodleCodeToLocal {
    # Mirror Azure Files Y:\html → C:\moodle\html (local SSD).
    # IIS serves from local disk for best PHP performance.
    # Equivalent to what the official Azure/Moodle repo does with rsync on Linux.
    New-Item -ItemType Directory -Force -Path 'C:\moodle\html', 'C:\moodle\logs' | Out-Null
    $robocopyArgs = @(
        'Y:\html', 'C:\moodle\html',
        '/MIR',          # mirror — adds new, removes deleted
        '/Z',            # restartable mode for large files
        '/MT:8',         # 8 parallel threads
        '/R:3',          # 3 retries on failure
        '/W:5',          # 5s wait between retries
        '/NP',           # no progress output
        '/LOG+:C:\moodle\logs\robocopy-sync.log'
    )
    & robocopy @robocopyArgs
    # Robocopy exit codes 0-7 are success (>7 means real error)
    if ($LASTEXITCODE -gt 7) {
        throw "Robocopy sync failed with exit code $LASTEXITCODE"
    }
}

function Register-MoodleSyncTask {
    # Scheduled task: pulls latest code from Azure Files every 5 minutes.
    # No IP addresses — uses Azure Files UNC path directly.
    # Mirrors the official Azure/Moodle Linux pattern (rsync via cron on webserver nodes).
    $scriptPath = 'C:\moodle\sync-local.ps1'
    $syncScript = @'
$ErrorActionPreference = 'Stop'
$robocopyArgs = @(
    'Y:\html', 'C:\moodle\html',
    '/MIR', '/Z', '/MT:8', '/R:3', '/W:5', '/NP',
    '/LOG+:C:\moodle\logs\robocopy-sync.log'
)
& robocopy @robocopyArgs
if ($LASTEXITCODE -gt 7) { exit $LASTEXITCODE }
'@
    Set-Content -Path $scriptPath -Value $syncScript -Encoding UTF8

    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                   -Argument "-NonInteractive -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once `
                   -At (Get-Date)
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 4) `
                    -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'Moodle Code Sync' -Action $action `
        -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
}

function Write-MoodleWebConfig {
    # web.config lives on local disk alongside the synced code
    $webConfig = @'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="ForceHttpsWhenNotForwarded" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="off" />
            <add input="{HTTP_X_FORWARDED_PROTO}" pattern="^https$" negate="true" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
        <rule name="AllowMoodleFiles" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAny">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" />
          </conditions>
          <action type="None" />
        </rule>
      </rules>
    </rewrite>
    <defaultDocument>
      <files>
        <add value="index.php" />
      </files>
    </defaultDocument>
  </system.webServer>
</configuration>
'@
    Set-Content -Path 'C:\moodle\html\web.config' -Value $webConfig -Encoding UTF8
}

Install-IISAndPhpPrerequisites
Mount-MoodleShares
Sync-MoodleCodeToLocal   # Initial copy from Azure Files to local SSD
Write-MoodleWebConfig
Register-MoodleSyncTask  # Schedule recurring pull every 5 min (no IPs needed)
