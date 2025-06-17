##############################################################
#  https://github.com/pir8radio/PRTG-SiteBoss-Sensor-Script  #
##############################################################

# Track script start time
$scriptStart = Get-Date

# Ignore SSL certificate errors
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-PRTG-Error($msg) {
    Write-Output "<?xml version='1.0' encoding='UTF-8' ?>"
    Write-Output "<prtg><error>1</error><text>$msg</text></prtg>"
    exit 2
}

# Parse arguments
if ($args.Count -lt 3) {
    Write-PRTG-Error "Usage: SiteBoss_API_v2.ps1 <host> <username> <password>"
}
$hostAddr = $args[0]
$user = $args[1]
$pass = $args[2]

# --- Authenticate to SiteBoss ---
$loginUri = "https://$hostAddr/api/v1/auth"
$body = @{ username = $user; password = $pass }
try {
    $loginResp = Invoke-WebRequest -Uri $loginUri -Method POST -Body ($body | ConvertTo-Json -Compress) -ContentType "application/json" -UseBasicParsing -TimeoutSec 20
    $setCookie = $loginResp.Headers["Set-Cookie"]
    if (-not $setCookie) {
        Write-PRTG-Error "No Set-Cookie header received during authentication."
    }
    $cookieHeader = ($setCookie -split ',' | Select-Object -First 1).Trim()
    if ($cookieHeader -notmatch "GUID=") {
        Write-PRTG-Error "No GUID found in Set-Cookie header: $setCookie"
    }
} catch {
    Write-PRTG-Error "Failed to authenticate: $_"
}

# --- Fetch device name (sys.sitename) ---
$deviceName = "SB-Site-Name-Not-Set"
try {
    $nameUri = "https://$hostAddr/api/v1/settingkey/sys.sitename"
    $nameRequest = [System.Net.WebRequest]::Create($nameUri)
    $nameRequest.Method = "GET"
    $nameRequest.Timeout = 20000
    $nameRequest.Headers.Add("Cookie", $cookieHeader)
    $nameResponse = $nameRequest.GetResponse()
    $nameReader = New-Object System.IO.StreamReader($nameResponse.GetResponseStream())
    $nameContent = $nameReader.ReadToEnd()
    $nameReader.Close()
    $nameResponse.Close()
    $nameJson = $nameContent | ConvertFrom-Json
    $deviceName = $nameJson.'sys.sitename'.Trim()
} catch {}

# --- Fetch product model (sys.product) ---
$deviceModel = "SB-Model-Not-Set"
try {
    $modelUri = "https://$hostAddr/api/v1/settingkey/sys.product"
    $modelRequest = [System.Net.WebRequest]::Create($modelUri)
    $modelRequest.Method = "GET"
    $modelRequest.Timeout = 20000
    $modelRequest.Headers.Add("Cookie", $cookieHeader)
    $modelResponse = $modelRequest.GetResponse()
    $modelReader = New-Object System.IO.StreamReader($modelResponse.GetResponseStream())
    $modelContent = $modelReader.ReadToEnd()
    $modelReader.Close()
    $modelResponse.Close()
    $modelJson = $modelContent | ConvertFrom-Json
    $deviceModel = $modelJson.'sys.product'.Trim()
} catch {}

# --- Fetch sensor dashboard ---
try {
    $dashboardUri = "https://$hostAddr/api/v1/sensor/dashboard"
    $request = [System.Net.WebRequest]::Create($dashboardUri)
    $request.Method = "GET"
    $request.Timeout = 20000
    $request.Headers.Add("Cookie", $cookieHeader)
    $response = $request.GetResponse()
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
    $content = $reader.ReadToEnd()
    $reader.Close()
    $response.Close()
    $dashboardJson = $content | ConvertFrom-Json
    $sensors = $dashboardJson.'sensor-dashboard'
    if (-not $sensors) {
        Write-PRTG-Error "No 'sensor-dashboard' field found in response."
    }

    # --- Calculate how long this script took to get API data ---
    $scriptEnd = Get-Date
    $duration = $scriptEnd - $scriptStart
    $durationMilliseconds = [math]::Round($duration.TotalMilliseconds, 0)

    # --- Generate PRTG XML Output ---
    $xml = New-Object System.Xml.XmlDocument
    $prtg = $xml.CreateElement("prtg")
    $xml.AppendChild($prtg) | Out-Null

    # --- Add API Response Time as Channel 0 ---
    $channel0 = $xml.CreateElement("result")
    $channelName = $xml.CreateElement("channel")
    $channelName.InnerText = "API Response"
    $channel0.AppendChild($channelName) | Out-Null

    $channelValue = $xml.CreateElement("value")
    $channelValue.InnerText = $durationMilliseconds.ToString()
    $channel0.AppendChild($channelValue) | Out-Null

    $unit = $xml.CreateElement("unit")
    $unit.InnerText = "Custom"
    $channel0.AppendChild($unit) | Out-Null

    $customUnit = $xml.CreateElement("customunit")
    $customUnit.InnerText = "ms"
    $channel0.AppendChild($customUnit) | Out-Null

    $prtg.AppendChild($channel0) | Out-Null

    # --- Add SiteBoss sensor channels ---
    foreach ($sensor in $sensors) {
        $result = $xml.CreateElement("result")
        $channel = $xml.CreateElement("channel")
        $channel.InnerText = $sensor.name
        $result.AppendChild($channel) | Out-Null

        if ($sensor.unit -and $sensor.unit.Trim() -ne "") {
            $value = $xml.CreateElement("value")
            $value.InnerText = $sensor.value
            $result.AppendChild($value) | Out-Null

            $unit = $xml.CreateElement("unit")
            $unit.InnerText = "Custom"
            $result.AppendChild($unit) | Out-Null

            $customUnit = $xml.CreateElement("customunit")
            $customUnit.InnerText = $sensor.unit.Trim()
            $result.AppendChild($customUnit) | Out-Null
        } else {
            $value = $xml.CreateElement("value")
            $value.InnerText = $sensor.severity
            $result.AppendChild($value) | Out-Null

            $lookup = $xml.CreateElement("valuelookup")
            $lookup.InnerText = "custom.prtgc.lookup.siteboss.rest.sensorstate"
            $result.AppendChild($lookup) | Out-Null
        }

        if ($sensor.name -like "Temperature*" -or $sensor.name -like "Temp*") {
            $limitmode = $xml.CreateElement("limitmode")
            $limitmode.InnerText = "1"
            $result.AppendChild($limitmode) | Out-Null

            $maxError = $xml.CreateElement("limitmaxerror")
            $maxError.InnerText = "90"
            $result.AppendChild($maxError) | Out-Null

            $maxWarning = $xml.CreateElement("limitmaxwarning")
            $maxWarning.InnerText = "80"
            $result.AppendChild($maxWarning) | Out-Null

            $minError = $xml.CreateElement("limitminerror")
            $minError.InnerText = "40"
            $result.AppendChild($minError) | Out-Null

            $minWarning = $xml.CreateElement("limitminwarning")
            $minWarning.InnerText = "50"
            $result.AppendChild($minWarning) | Out-Null
        }

        $prtg.AppendChild($result) | Out-Null
    }

    # --- Add device name and model to <text> field ---
    $text = $xml.CreateElement("text")
    $text.InnerText = "$deviceName $deviceModel"
    $prtg.AppendChild($text) | Out-Null

    # Output final XML
    Write-Output "<?xml version='1.0' encoding='UTF-8' ?>"
    Write-Output $xml.OuterXml
} catch {
    Write-PRTG-Error "Failed to fetch or parse dashboard: $($_.Exception.Message)"
}

# --- Log out (optional) ---
$logoutUri = "https://$hostAddr/api/v1/logout"
try {
    Invoke-WebRequest -Uri $logoutUri -Headers @{ "Cookie" = $cookieHeader } -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null
} catch {}
