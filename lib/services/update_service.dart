import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // Service to check for application updates.

  // Replace with your actual GitHub repository URL (e.g., 'https://api.github.com/repos/USERNAME/REPO/releases/latest')
  static const String _updateApiUrl = ''; 

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // If the API URL is empty, we stay in simulation/manual mode
      if (_updateApiUrl.isEmpty) {
        return null;
      }

      // Real implementation
      final response = await http.get(Uri.parse(_updateApiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // GitHub API format: data['tag_name'] (e.g., "v1.1.0")
        // Generic JSON format: data['version'] (e.g., "1.1.0")
        final latestVersion = (data['tag_name'] ?? data['version'])
            .toString()
            .replaceAll('v', '');
        
        final downloadUrl = data['html_url'] ?? data['url'];

        if (_isNewer(latestVersion, currentVersion)) {
          return {
            'version': latestVersion,
            'url': downloadUrl
          };
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Update check error: $e');
      return null;
    }
  }

  static bool _isNewer(String latest, String current) {
    List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return latestParts.length > currentParts.length;
  }

  static Future<void> launchUpdate(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
