import 'dart:io' show Platform;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import '../constants/api_constants.dart';

class SosService {
  final AuthService _authService = AuthService();
  final Telephony telephony = Telephony.instance;

  Future<void> triggerEmergency() async {
    try {
      // 1. Fetch User Data
      final user = await _authService.getCurrentUserData();
      if (user == null || user.emergencyContacts.isEmpty) {
        throw Exception('No emergency contacts found. Please add them in your profile.');
      }

      // 2. Fetch High-Accuracy Location
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final String googleMapsUrl = 
          'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
      
      final String message = 
          '${user.fullName} is not feeling secure. Live Location: $googleMapsUrl';

      // 3. Dispatch SMS Messages
      for (var contact in user.emergencyContacts) {
        String phone = contact.phone;
        // Standardize to +91 if necessary
        String digits = phone.replaceAll(RegExp(r'\D'), '');
        if (digits.length == 10) {
          phone = '+91$digits';
        } else if (digits.length == 12 && digits.startsWith('91')) {
          phone = '+$digits';
        }

        if (Platform.isAndroid) {
          await telephony.sendSms(
            to: phone,
            message: message,
          );
        } else if (Platform.isIOS) {
          final Uri smsLaunchUri = Uri(
            scheme: 'sms',
            path: contact.phone,
            queryParameters: <String, String>{
              'body': message,
            },
          );
          if (await canLaunchUrl(smsLaunchUri)) {
            await launchUrl(smsLaunchUri);
          }
        }
      }

      // 4. Trigger Proximity Alerts via Backend
      await _notifyNearbyUsers(
        uid: user.uid,
        fullName: user.fullName,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      
      debugPrint('SOS Alerts Dispatched Successfully');
    } catch (e) {
      debugPrint('SOS Error: $e');
      rethrow;
    }
  }

  Future<void> _notifyNearbyUsers({
    required String uid,
    required String fullName,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.sosTrigger),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'fullName': fullName,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Proximity alert successful: ${data['notified_count']} users notified');
      } else {
        debugPrint('Backend SOS trigger failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error calling backend SOS trigger: $e');
    }
  }

  Future<void> respondToSos(String victimUid) async {
    try {
      final user = await _authService.getCurrentUserData();
      if (user == null) return;

      final response = await http.post(
        Uri.parse(ApiConstants.sosRespond),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'victim_uid': victimUid,
          'responder_name': user.fullName,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('SOS Response notified successfully');
      } else {
        debugPrint('SOS Response failed: ${response.body}');
        throw Exception('Failed to send response');
      }
    } catch (e) {
      debugPrint('Error in respondToSos: $e');
      rethrow;
    }
  }
}
