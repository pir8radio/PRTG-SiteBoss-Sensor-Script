# PRTG-SiteBoss-Sensor-Script

This repository provides a PowerShell script for integrating SiteBoss network device data with the PRTG Network Monitor system. The script queries the SiteBoss REST API, retrieves sensor data, and outputs results in an XML format readable by PRTG as a custom sensor.

## Features

- **Authenticates with the SiteBoss API** using provided credentials.
- **Retrieves dashboard data** including all available sensors.
- **Dynamically generates PRTG XML output** for each sensor/channel.
- **Supports custom units and lookups** for channel values.
- **Temperature channel alerting** with configurable warning and error thresholds.
- **Handles SSL certificate warnings** (useful for self-signed device certs).
- **Graceful error handling** with descriptive messages for PRTG.

## Requirements

- PowerShell 5.1 or newer (Windows Server recommended for PRTG integration).
- PRTG Network Monitor (must support custom/exe/script sensors).
- SiteBoss device with REST API v1 endpoints enabled.

## Usage

The script is intended to be run by PRTG as a custom EXE/Script sensor.

### Arguments

```
SiteBoss_API_v2.ps1 <host> <username> <password>
```

- `<host>`: Hostname or IP address of the SiteBoss device (do not include protocol).
- `<username>`: Username for SiteBoss API authentication.
- `<password>`: Password for SiteBoss API authentication.

### Example (manual test)

```powershell
.\SiteBoss_API_v2.ps1 192.168.1.100 admin "MySecretPassword"
```

### Integration with PRTG

1. Copy `SiteBoss_API_v2.ps1` to the `Custom Sensors\EXEXML` directory on your PRTG Probe system.
2. Copy `custom.prtgc.lookup.siteboss.rest.sensorstate.ovl` to the `lookups/custom` directory on your PRTG core(s).
3. Copy `SiteBoss (v2).odt` to the `devicetemplates` directory on your PRTG core(s).
4. In the PRTG web interface, add a new "EXE/Script Advanced" sensor to your SiteBoss device.
5. Select `SiteBoss_API_v2.ps1` as the script, and add the required parameters (`%host <username> "<password>"`) in the sensor settings and select "Auto discovery with template" and select the `SiteBoss (v2)` template.
6. Save and test the sensor.

## Output

- Returns `<prtg>` XML with a `<result>` for each detected sensor/channel.
- For temperature, includes PRTG limit settings for automatic warning/error alerts.
- When an error occurs, returns a PRTG-formatted error message for easy troubleshooting.

## Security

- The script disables SSL certificate validation to support self-signed certs; use with caution.
- Credentials are passed as arguments (plain text in PRTG), so restrict permissions on the script and sensor or use the script placeholders.

## Customization

- **Temperature limits** (warning/error) can be adjusted in the script under the "Temperature channel" section.
- **Sensor lookup**: Custom lookup ID is `custom.prtgc.lookup.siteboss.rest.sensorstate.ovl`. Ensure your PRTG server has this lookup defined if using custom states.
- **Device Template**: Included my device template `SiteBoss (v2).odt`, may not be what you want, but something you can edit to make work however you want.

## License

[MIT](LICENSE) (or specify your preferred license)

## Disclaimer

This script is provided as-is, without warranty. Use at your own risk. Tested with SiteBoss models 360 and 550.

## Credits

Created by [pir8radio](https://github.com/pir8radio)
