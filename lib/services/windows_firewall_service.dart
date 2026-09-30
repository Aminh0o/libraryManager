import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config/network_config.dart';

/// Result of a pairing diagnostic run. Each field is a human-readable line
/// that the UI can display directly (already localized by the caller).
class PairingDiagnosticResult {
  final bool isWindows;
  final bool udpListening;
  final bool firewallRulesInstalled;
  final bool blockRuleFound;
  final String? rawOutput;

  const PairingDiagnosticResult({
    required this.isWindows,
    required this.udpListening,
    required this.firewallRulesInstalled,
    required this.blockRuleFound,
    this.rawOutput,
  });
}

class WindowsFirewallService {
  static const String _tcpRuleName = 'Library Manager LAN TCP 8080';
  static const String _udpRuleName = 'Library Manager LAN UDP 19001';

  static Uint8List _toUtf16LeBytes(String s) {
    final units = s.codeUnits;
    final bytes = Uint8List(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      final v = units[i];
      bytes[i * 2] = v & 0xFF;
      bytes[i * 2 + 1] = (v >> 8) & 0xFF;
    }
    return bytes;
  }

  static Future<bool> ensureLanFirewallRules({
    int httpPort = NetworkConfig.defaultHttpPort,
    int pairingUdpPort = NetworkConfig.defaultPairingUdpPort,
  }) async {
    if (!Platform.isWindows) return false;

    final script =
        r'''
$ErrorActionPreference = 'Stop'

function Ensure-NetRule([string]$Name, [string]$Protocol, [int]$Port) {
  $rule = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
  if ($rule) {
    $rule | Remove-NetFirewallRule | Out-Null
  }
  New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow -Protocol $Protocol -LocalPort $Port -Profile Any -RemoteAddress LocalSubnet | Out-Null
}

try {
  if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
    Ensure-NetRule '$_TCP_RULE' 'TCP' $_HTTP_PORT
    Ensure-NetRule '$_UDP_RULE' 'UDP' $_UDP_PORT
  }
  else {
    netsh advfirewall firewall delete rule name='$_TCP_RULE' 1>$null 2>$null
    netsh advfirewall firewall delete rule name='$_UDP_RULE' 1>$null 2>$null
    netsh advfirewall firewall add rule name='$_TCP_RULE' dir=in action=allow protocol=TCP localport=$_HTTP_PORT profile=any remoteip=localsubnet 1>$null
    netsh advfirewall firewall add rule name='$_UDP_RULE' dir=in action=allow protocol=UDP localport=$_UDP_PORT profile=any remoteip=localsubnet 1>$null
  }
  exit 0
}
catch {
  exit 1
}
'''
            .replaceAll(r'$_TCP_RULE', _tcpRuleName)
            .replaceAll(r'$_UDP_RULE', _udpRuleName)
            .replaceAll(r'$_HTTP_PORT', httpPort.toString())
            .replaceAll(r'$_UDP_PORT', pairingUdpPort.toString());

    final encodedScript = base64.encode(_toUtf16LeBytes(script));

    final startProcessCommand =
        r"Start-Process -FilePath powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','" +
        encodedScript +
        r"') -WindowStyle Hidden -Wait -PassThru | ForEach-Object { exit `$_.ExitCode }";

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        startProcessCommand,
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Runs a non-elevated diagnostic to check whether the pairing prerequisites
  /// are met on this machine. Returns a structured result the UI can render as
  /// a checklist. Does NOT require admin rights.
  static Future<PairingDiagnosticResult> runPairingDiagnostic({
    int pairingUdpPort = NetworkConfig.defaultPairingUdpPort,
  }) async {
    if (!Platform.isWindows) {
      return const PairingDiagnosticResult(
        isWindows: false,
        udpListening: false,
        firewallRulesInstalled: false,
        blockRuleFound: false,
      );
    }

    final script =
        '''
\$ErrorActionPreference = 'SilentlyContinue'
\$udp = Get-NetUDPEndpoint -LocalPort $pairingUdpPort -ErrorAction SilentlyContinue
\$udpOk = if (\$udp) { 'true' } else { 'false' }
\$fwRules = Get-NetFirewallRule -DisplayName 'Library Manager LAN *' -ErrorAction SilentlyContinue
\$fwOk = if (\$fwRules -and (\$fwRules | Where-Object { \$_.Enabled -eq 'True' }).Count -ge 2) { 'true' } else { 'false' }
\$blockRules = Get-NetFirewallRule -Direction Inbound -Action Block -Enabled True -ErrorAction SilentlyContinue | Where-Object {
  (\$_ | Get-NetFirewallPortFilter).LocalPort -eq '$pairingUdpPort'
}
\$blockOk = if (\$blockRules) { 'true' } else { 'false' }
Write-Output "UDP=\$udpOk"
Write-Output "FW=\$fwOk"
Write-Output "BLOCK=\$blockOk"
''';

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ], runInShell: true);

      final output = result.stdout.toString();
      final udpListening = output.contains('UDP=true');
      final firewallRulesInstalled = output.contains('FW=true');
      final blockRuleFound = output.contains('BLOCK=true');

      return PairingDiagnosticResult(
        isWindows: true,
        udpListening: udpListening,
        firewallRulesInstalled: firewallRulesInstalled,
        blockRuleFound: blockRuleFound,
        rawOutput: output.trim(),
      );
    } catch (e) {
      return PairingDiagnosticResult(
        isWindows: true,
        udpListening: false,
        firewallRulesInstalled: false,
        blockRuleFound: false,
        rawOutput: 'Diagnostic failed: $e',
      );
    }
  }
}
