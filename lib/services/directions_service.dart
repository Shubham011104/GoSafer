import 'dart:convert';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';

class DirectionsRoute {
  final List<LatLng> polyline;
  final int distanceMeters;
  final String distanceText;
  final int durationSeconds;
  final String durationText;

  DirectionsRoute({
    required this.polyline,
    required this.distanceMeters,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
  });
}

class DirectionsService {
  Future<List<DirectionsRoute>> getDirections(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
        '${ApiConstants.directions}'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&alternatives=true'
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final List routesData = data['routes'];
          List<DirectionsRoute> routes = [];
          for (var routeData in routesData) {
            final leg = routeData['legs'][0];
            final String encodedPolyline = routeData['overview_polyline']['points'];
            
            List<PointLatLng> decodedPoints = PolylinePoints.decodePolyline(encodedPolyline);
            List<LatLng> points = decodedPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

            routes.add(DirectionsRoute(
              polyline: points,
              distanceMeters: leg['distance']['value'],
              distanceText: leg['distance']['text'],
              durationSeconds: leg['duration']['value'],
              durationText: leg['duration']['text'],
            ));
          }

          return routes;
        }
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
    }

    return [];
  }
}
