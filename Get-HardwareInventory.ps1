<#
.SYNOPSIS
    Hardware and OS inventory of Windows computers, exported to CSV.

.DESCRIPTION
    Collects manufacturer, model, serial number, OS, CPU, RAM (total and per module),
    motherboard, BIOS, disks, GPU, IP and MAC from each computer through CIM, and
    writes one CSV row per computer. It runs in three modes:

      1) Local computer only (no parameters).
      2) A list of computers (-ComputerName).
      3) Every enabled computer in Active Directory (-FromAD, needs the RSAT
         ActiveDirectory module).

    Remote computers are queried in one parallel Invoke-Command call (WinRM).
    Computers that cannot be reached are reported and written to the CSV as
    "Unreachable" rows, so a partial run is visible instead of silent.

.PARAMETER ComputerName
    Names of the computers to query.

.PARAMETER FromAD
    Query every enabled computer found in Active Directory.

.PARAMETER SearchBase
    Optional OU distinguished name to limit -FromAD, for example
    "OU=Workstations,DC=example,DC=local".

.PARAMETER Credential
    Account with local administrator rights on the targets. Defaults to the
    current user.

.PARAMETER ThrottleLimit
    Maximum number of simultaneous remote connections (default 16).

.PARAMETER OutputPath
    CSV path. Defaults to a timestamped file in the current folder.

.PARAMETER Delimiter
    CSV delimiter (default ';', which opens cleanly in Spanish-locale Excel).

.NOTES
    Requirements: PowerShell Remoting (WinRM) enabled on the targets. In a domain
    it can be enabled by GPO: "Windows Remote Management (WS-Management)" ->
    Allow remote server management through WinRM. Read-only: the script only
    queries CIM classes and never changes a computer.

.EXAMPLE
    .\Get-HardwareInventory.ps1

.EXAMPLE
    .\Get-HardwareInventory.ps1 -ComputerName PC01,PC02,SRV-FILE

.EXAMPLE
    .\Get-HardwareInventory.ps1 -FromAD -SearchBase "OU=Workstations,DC=example,DC=local" -OutputPath C:\Temp\inventory.csv
#>

[CmdletBinding()]
param(
    [string[]]$ComputerName,
    [switch]$FromAD,
    [string]$SearchBase,
    [System.Management.Automation.PSCredential]$Credential,
    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 16,
    [string]$OutputPath = ".\Inventory_$(Get-Date -Format yyyyMMdd_HHmm).csv",
    [string]$Delimiter = ';'
)

# --- 1. Decide which computers to query ---
if ($FromAD) {
    Import-Module ActiveDirectory -ErrorAction Stop
    $adParams = @{ Filter = { Enabled -eq $true } }
    if ($SearchBase) { $adParams.SearchBase = $SearchBase }
    $ComputerName = Get-ADComputer @adParams | Select-Object -ExpandProperty Name
    Write-Host "Computers found in AD: $($ComputerName.Count)" -ForegroundColor Cyan
}
elseif (-not $ComputerName) {
    $ComputerName = $env:COMPUTERNAME
}

# --- 2. Script block that runs on EACH computer (read-only CIM queries) ---
$collect = {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $cpu  = Get-CimInstance Win32_Processor
    $bios = Get-CimInstance Win32_BIOS
    $bb   = Get-CimInstance Win32_BaseBoard
    $ram  = @(Get-CimInstance Win32_PhysicalMemory)
    $disk = @(Get-CimInstance Win32_DiskDrive)
    $gpu  = Get-CimInstance Win32_VideoController
    $net  = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }

    [PSCustomObject]@{
        Computer        = $env:COMPUTERNAME
        Status          = 'OK'
        Manufacturer    = $cs.Manufacturer
        Model           = $cs.Model
        SerialNumber    = $bios.SerialNumber
        OS              = $os.Caption
        OSVersion       = $os.Version
        CPU             = ($cpu.Name -join '; ')
        Cores           = ($cpu.NumberOfCores | Measure-Object -Sum).Sum
        RAM_GB          = [math]::Round(($cs.TotalPhysicalMemory / 1GB), 1)
        RAM_Modules     = ($ram | ForEach-Object { "$([math]::Round($_.Capacity / 1GB))GB@$($_.Speed)MHz" }) -join ' + '
        RAM_SlotsUsed   = $ram.Count
        Motherboard     = "$($bb.Manufacturer) $($bb.Product)"
        BIOSVersion     = $bios.SMBIOSBIOSVersion
        Disks           = ($disk | ForEach-Object { "$($_.Model) ($([math]::Round($_.Size / 1GB))GB)" }) -join ' | '
        GPU             = ($gpu.Name -join '; ')
        IP              = ($net.IPAddress | Where-Object { $_ -match '\.' }) -join ', '
        MAC             = ($net.MACAddress) -join ', '
        InventoryDate   = Get-Date -Format 'yyyy-MM-dd HH:mm'
    }
}

# --- 3. Run it: local without remoting, the rest in one parallel call ---
$results = @()
$remote  = @($ComputerName | Where-Object { $_ -ne $env:COMPUTERNAME -and $_ -ne 'localhost' })

if ($remote.Count -lt $ComputerName.Count) {
    $results += & $collect
}

if ($remote.Count -gt 0) {
    $icParams = @{
        ComputerName  = $remote
        ScriptBlock   = $collect
        ThrottleLimit = $ThrottleLimit
        ErrorAction   = 'SilentlyContinue'
        ErrorVariable = 'remoteErrors'
    }
    if ($Credential) { $icParams.Credential = $Credential }

    $answered = @(Invoke-Command @icParams | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName)
    $results += $answered

    $okNames = $answered | ForEach-Object { $_.Computer }
    foreach ($name in $remote) {
        if ($okNames -notcontains $name) {
            $reason = ($remoteErrors | Where-Object { $_.TargetObject -eq $name } | Select-Object -First 1).Exception.Message
            Write-Warning "Could not query ${name}: $reason"
            $results += [PSCustomObject]@{ Computer = $name; Status = 'Unreachable' }
        }
    }
}

# --- 4. Export and summarise ---
$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
$ok = @($results | Where-Object { $_.Status -eq 'OK' }).Count
Write-Host ("`nInventory saved to {0}: {1} of {2} computers answered." -f $OutputPath, $ok, $results.Count) -ForegroundColor Green
$results | Format-Table Computer, Status, Model, CPU, RAM_GB, OS -AutoSize
