# AD Hardware Inventory

Agentless hardware and OS inventory for a Windows domain, in a single PowerShell script. It asks every computer for its specs over WinRM, collects the answers on one machine and writes a CSV you can open in Excel. Nothing is installed on the workstations and nobody has to visit them.

> **Built with AI assistance (Claude Code).** I designed the approach, ran it in a real work environment and validated the results. The script is read-only: it only queries CIM classes and never changes a computer.

## Why it exists

A small organisation had no reliable, up-to-date inventory of its computers. Building one by hand, desk by desk, was not realistic: it takes a lot of time and interrupts users. Third-party inventory agents were not an option either, because the goal was to use only what Windows already provides.

So the problem became: **collect the hardware of a whole Active Directory domain, from one server, with native tools, and make the process repeatable.**

Goals:

- Get the components of every computer in the domain automatically.
- No visits to workstations and no extra software.
- Collect centrally and export to a format people can use (CSV/Excel).
- Make it re-runnable so the inventory can be refreshed periodically.

## What it collects

| Category | Fields |
|---|---|
| Identity | computer name, manufacturer, model, serial number |
| System | OS and version, BIOS version |
| CPU | model, number of cores |
| Memory | total RAM, modules with size and speed, used slots |
| Motherboard | manufacturer and model |
| Storage | model and size of each disk |
| Graphics | video adapter |
| Network | IP address and MAC address |
| Run info | `Status` (`OK` or `Unreachable`) and the inventory date |

Computers that do not answer (switched off, or the policy has not reached them yet) are reported and written as `Unreachable` rows, so a partial run is visible instead of silent.

## Quick start

```powershell
# This computer only
.\Get-HardwareInventory.ps1

# A list of computers
.\Get-HardwareInventory.ps1 -ComputerName PC01,PC02,SRV-FILE

# Every enabled computer in Active Directory (needs the RSAT ActiveDirectory module)
.\Get-HardwareInventory.ps1 -FromAD -OutputPath C:\Temp\inventory.csv

# One OU only, with another admin account
.\Get-HardwareInventory.ps1 -FromAD -SearchBase "OU=Workstations,DC=example,DC=local" -Credential (Get-Credential)
```

| Parameter | Meaning |
|---|---|
| `-ComputerName` | Names of the computers to query. |
| `-FromAD` | Query every enabled computer found in Active Directory. |
| `-SearchBase` | Optional OU distinguished name to limit `-FromAD`. |
| `-Credential` | Account with local admin rights on the targets (default: current user). |
| `-ThrottleLimit` | Maximum simultaneous remote connections (default 16). |
| `-OutputPath` | CSV path (default: timestamped file in the current folder). |
| `-Delimiter` | CSV delimiter (default `;`, which opens cleanly in Spanish-locale Excel). |

Full help: `Get-Help .\Get-HardwareInventory.ps1 -Full`.

## Requirements

- PowerShell 5.1 or later.
- **WinRM enabled on the targets.** In a domain you do it once with a GPO: see [docs/GPO-WinRM.md](docs/GPO-WinRM.md).
- An account with local administrator rights on the targets.
- For `-FromAD`: the RSAT ActiveDirectory module.

## How it works

```
Server (AD + PowerShell) --WinRM--> workstations and servers --> one consolidated CSV
```

1. **Build the list.** Either you pass the names, or the script reads every enabled computer from Active Directory (optionally under one OU).
2. **Query.** One parallel `Invoke-Command` runs the same read-only CIM block on every remote target (`Win32_ComputerSystem`, `Win32_OperatingSystem`, `Win32_Processor`, `Win32_BIOS`, `Win32_BaseBoard`, `Win32_PhysicalMemory`, `Win32_DiskDrive`, `Win32_VideoController`, `Win32_NetworkAdapterConfiguration`). The local computer is queried directly, without remoting.
3. **Handle failures.** Any target that does not answer is matched against the remoting errors and written as an `Unreachable` row, with the reason printed as a warning. One dead machine never stops the run.
4. **Export.** All rows are written to a CSV and a summary shows how many computers answered, for example `Inventory saved to inventory.csv: 20 of 26 computers answered.`

### Rollout approach that worked

Incremental, to keep the risk low:

1. Create and link the GPO that enables WinRM.
2. Validate a **single test machine** (`Test-WSMan`) before going further.
3. Run against a **small group** and confirm the data and the remote access between machines.
4. Run against the **whole domain** and produce the full CSV.

## Tested

- **In a real work environment.** The approach and the first version of the script were built and run on a real Active Directory domain of **26 computers** (workstations and servers). After the GPO spread and the machines restarted, **20 of 26** answered and were inventoried correctly. The other 6 were switched off at the time of the run, which is why the report marks unreachable machines explicitly instead of dropping them: you can simply re-run it once they are on.
- **This public version** is a cleaned and refactored rewrite (English, parallel remoting, error report, OU filter, credentials). I re-tested it on a single machine in local mode, and tested the unreachable-computer path with a non-existent host (it is reported and the run continues). I have not re-run the refactored remote path against a full domain, so please open an issue if you hit anything.

## Output example

A fictional example is in [sample/sample-output.csv](sample/sample-output.csv). Typical use of the result: filter by OS to plan a Windows upgrade, find machines with little RAM, or list the computers that did not answer and check them in Active Directory.

## Good to know

- **Treat real output as internal data.** The CSV contains serial numbers and MAC/IP addresses. It is ignored by git here and you should not publish it.
- **WinRM scope.** Limit the WinRM IP filter and the firewall rule (TCP 5985, domain profile) to your management network where you can.
- **Easy to extend:** installed software, monitors, free disk space, encryption status.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Unreachable` for many computers | WinRM policy not applied yet (restart or `gpupdate /force`) or the computer is off. |
| Access denied | The account is not a local admin on the target: use `-Credential`. |
| `-FromAD` fails to start | RSAT ActiveDirectory module is not installed. |
| WinRM error about TrustedHosts | You are querying from a computer that is not in the domain, or by IP instead of name. Use names in the domain. |

## License

MIT. See [LICENSE](LICENSE).
