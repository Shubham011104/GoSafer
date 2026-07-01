import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class PermissionService {
  /// Requests Location and SMS permissions required for safety features.
  static Future<void> requestInitialPermissions() async {
    try {
      // Request SMS and Location permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.sms,
      ].request();

      if (kDebugMode) {
        statuses.forEach((permission, status) {
          debugPrint('Permission $permission: $status');
        });
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    }
  }

  /// Checks if both critical permissions are granted.
  static Future<bool> hasCriticalPermissions() async {
    bool locationGranted = await Permission.location.isGranted;
    bool smsGranted = await Permission.sms.isGranted;
    return locationGranted && smsGranted;
  }
}
