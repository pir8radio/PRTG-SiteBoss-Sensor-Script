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
    Write-Output "<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
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
    $loginResp = Invoke-WebRequest -Uri $loginUri -Method POST -Body ($body | ConvertTo-Json -Compress) -ContentType "application/json" -UseBasicParsing -TimeoutSec 15
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

# --- Fetch sensor dashboard ---
try {
    $dashboardUri = "https://$hostAddr/api/v1/sensor/dashboard"
    $request = [System.Net.WebRequest]::Create($dashboardUri)
    $request.Method = "GET"
    $request.Timeout = 15000
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

    # --- Generate PRTG XML Output ---
    $xml = New-Object System.Xml.XmlDocument
    $prtg = $xml.CreateElement("prtg")
    $xml.AppendChild($prtg) | Out-Null

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

        # Add limit settings for Temperature channel
        if ($sensor.name -eq "Temperature") {
            $limitmode = $xml.CreateElement("limitmode")
            $limitmode.InnerText = "1"  # Enable alerting
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

    $xml.OuterXml
} catch {
    Write-PRTG-Error "Failed to fetch or parse dashboard: $($_.Exception.Message)"
}

# --- Log out (optional) ---
$logoutUri = "https://$hostAddr/api/v1/logout"
try {
    Invoke-WebRequest -Uri $logoutUri -Headers @{ "Cookie" = $cookieHeader } -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
} catch {
    # Logout failure is non-critical
}

