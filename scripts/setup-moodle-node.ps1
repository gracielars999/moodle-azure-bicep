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

function Mount-MoodleDataShare {
    $storageAccount = $env:MOODLE_STORAGE_ACCOUNT
    $shareName = $env:MOODLE_FILE_SHARE
    $storageKey = $env:MOODLE_STORAGE_KEY

    if ([string]::IsNullOrWhiteSpace($storageAccount) -or [string]::IsNullOrWhiteSpace($shareName) -or [string]::IsNullOrWhiteSpace($storageKey)) {
        throw 'Storage account values were not provided to the setup script.'
    }

    cmdkey.exe /add:"$storageAccount.file.core.windows.net" /user:"localhost\$storageAccount" /pass:"$storageKey" | Out-Null

    if (Get-PSDrive -Name 'Z' -ErrorAction SilentlyContinue) {
        Remove-PSDrive -Name 'Z' -Force
    }

    $uncPath = "\\$storageAccount.file.core.windows.net\$shareName"
    New-PSDrive -Name 'Z' -PSProvider FileSystem -Root $uncPath -Persist -Scope Global | Out-Null
    New-Item -ItemType Directory -Force -Path 'Z:\moodledata' | Out-Null
}

function Write-MoodleWebConfig {
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
Mount-MoodleDataShare
Write-MoodleWebConfig
