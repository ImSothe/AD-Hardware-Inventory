# Enabling WinRM on every computer with one GPO

The script needs PowerShell Remoting (WinRM) on the targets. Instead of visiting each computer, create one Group Policy Object linked to the domain (or to the OU you want to inventory) with three settings.

Path in the Group Policy editor: `Computer Configuration > Policies`.

## 1. Allow remote management through WinRM

`Administrative Templates > Windows Components > Windows Remote Management (WinRM) > WinRM Service`

- **Allow remote server management through WinRM**: Enabled.
- IPv4 filter and IPv6 filter: `*` (or, better, your local network range).

## 2. Start the service automatically

`Windows Settings > Security Settings > System Services`

- **Windows Remote Management (WS-Management)**: Startup mode `Automatic`.

## 3. Open the firewall port

`Windows Settings > Security Settings > Windows Defender Firewall with Advanced Security > Inbound Rules`

- New rule for **TCP 5985**, profile **Domain** only, action Allow.

## Verifying

On the server, against one test machine first:

```powershell
Test-WSMan -ComputerName PC01
```

The policy reaches each computer when it refreshes its Group Policy, usually after a restart. Run `gpupdate /force` on a test machine to speed it up, then check the others in waves.

## Notes

- Restrict the IP filter and the firewall rule to your management network if you can.
- Machines that are off, or that have not applied the policy yet, will show as `Unreachable` in the report. Run it again after they restart.
