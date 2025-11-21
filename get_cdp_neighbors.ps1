Import-Module Posh-SSH -ErrorAction Stop

$switchFile = "C:\cdp_switches.txt"
$outCsv     = "C:\cdp_neighbors.csv"

$username   = "cisco"
$password   = "@dmin2012"
$enablePass = "@dmin2012"
$port       = 22

$result = @()
$creds = New-Object System.Management.Automation.PSCredential ($username, (ConvertTo-SecureString $password -AsPlainText -Force))
$ips = Get-Content $switchFile | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+' }

function Read-SSHOutput {
    param ($stream, [int]$timeout = 2000)
    Start-Sleep -Milliseconds $timeout
    $out = ""
    while ($stream.DataAvailable) {
        $out += $stream.Read()
        Start-Sleep -Milliseconds 200
    }
    return $out
}

function Resolve-DeviceIDToIP {
    param ([string]$deviceID)
    try {
        $addr = [System.Net.Dns]::GetHostAddresses($deviceID) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
        return $addr[0].IPAddressToString
    } catch {
        return "N/A"
    }
}

foreach ($ip in $ips) {
    try {
        $session = New-SSHSession -ComputerName $ip -Credential $creds -Port $port -ConnectionTimeout 10 -ErrorAction Stop
        $shell = New-SSHShellStream -SessionId $session.SessionId
        Start-Sleep -Seconds 1
        [void]$shell.Read()

        $shell.WriteLine("enable")
        Start-Sleep -Seconds 1
        $out = Read-SSHOutput $shell

        if ($out -match "Password") {
            $shell.WriteLine($enablePass)
            Start-Sleep -Seconds 1
            $out = Read-SSHOutput $shell
        }

        $shell.WriteLine("terminal length 0")
        Start-Sleep -Seconds 1
        [void]$shell.Read()

        $shell.WriteLine("show cdp neighbors")
        Start-Sleep -Seconds 3
        $raw = Read-SSHOutput $shell

        $rawFile = "$env:TEMP\cdp_raw_$ip.txt"
        $raw | Out-File $rawFile -Encoding UTF8

        $neighbors = @()
        $lines = Get-Content $rawFile | Where-Object { $_ -match '\S' }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\S' -and $i + 1 -lt $lines.Count -and $lines[$i + 1] -match 'Gig|Fa|Eth') {
                $device = $lines[$i].Trim()
                $details = $lines[$i + 1] -split '\s{2,}'
                if ($details.Length -ge 5) {
                    $neighborIP = Resolve-DeviceIDToIP -deviceID $device
                    $neighbors += [PSCustomObject]@{
                        SwitchIP        = $ip
                        DeviceID        = $device
                        NeighborIP      = $neighborIP
                        LocalInterface  = $details[0].Trim()
                        HoldTime        = $details[1].Trim()
                        Capability      = $details[2].Trim()
                        Platform        = $details[3].Trim()
                        PortID          = $details[4].Trim()
                    }
                }
            }
        }

        if ($neighbors.Count -eq 0) {
            Write-Host "fail a l etape $ip"
        } else {
            Write-Host "operation $ip reussite"
            $result += $neighbors
        }

        $shell.WriteLine("exit")
        Remove-SSHSession -SessionId $session.SessionId | Out-Null
    }
    catch {
        Write-Host "fail a l etape $ip"
    }
}

if ($result.Count -gt 0) {
    $result | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8
    Write-Host "operation termine"
} else {
    Write-Host "fail global"
}

Pause
