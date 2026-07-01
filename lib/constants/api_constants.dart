import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConstants {
  // --- REPLACE THIS WITH YOUR COMPUTER'S LOCAL IP (from ipconfig) ---
  // When connected to your phone's hotspot, look for IPv4 Address in 'ipconfig'
  static const String physicalDeviceIp = "192.168.1.5";

  static String get baseUrl {
    if (kIsWeb) return "http://localhost:8000";

    // For Android, update this based on your testing target:
    if (Platform.isAndroid) {
      // 1. For Physical Phone: Use the computer's IP
      return "http://$physicalDeviceIp:8000";

      // 2. For Emulator: Use 10.0.2.2
      // return "http://10.0.2.2:8000";
    }

    return "http://localhost:8000";
  }

  static String get crimeCentroids => "$baseUrl/crime/centroids";
  static String get crimeHeatmap => "$baseUrl/crime/heatmap";
  static String get routeEvaluate => "$baseUrl/route/evaluate";
  static String get placesAutocomplete => "$baseUrl/places/autocomplete";
  static String get placesDetails => "$baseUrl/places/details";
  static String get directions => "$baseUrl/directions/json";
  static String get sosTrigger => "$baseUrl/sos/trigger";
  static String get sosRespond => "$baseUrl/sos/respond";

  // Google Maps (Not used for Routing/Places currently as we use OSRM/Nominatim)
  static const String googleMapsApiKey = "YOUR_API_KEY";
}
