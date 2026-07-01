import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'package:flutter/foundation.dart';

import 'directions_service.dart';

class RouteEvaluation {
  final List<LatLng> polyline;
  final String distanceText;
  final String durationText;
  final double riskScore;
  final bool isNightModeActive;
  final String type; // 'Fastest', 'Shortest', 'Safest'

  RouteEvaluation({
    required this.polyline,
    required this.distanceText,
    required this.durationText,
    required this.riskScore,
    required this.isNightModeActive,
    required this.type,
  });
}

class RouteService {
  final DirectionsService _directionsService = DirectionsService();

  RouteService();

  Future<List<RouteEvaluation>> getRouteRecommendations(LatLng start, LatLng end) async {
    List<RouteEvaluation> evaluatedRoutes = [];

    // 1. Get real routes from Google Directions API
    List<DirectionsRoute> googleRoutes = await _directionsService.getDirections(start, end);

    if (googleRoutes.isEmpty) return [];

    // 2. Evaluate each route's safety against the Python Backend
    for (int i = 0; i < googleRoutes.length; i++) {
      final route = googleRoutes[i];
      
      // Call Python Backend for AI Risk Evaluation
      final evaluation = await _evaluateRouteWithBackend(route.polyline);
      
      evaluatedRoutes.add(RouteEvaluation(
        polyline: route.polyline,
        distanceText: route.distanceText,
        durationText: route.durationText,
        riskScore: evaluation['risk_score'],
        isNightModeActive: evaluation['is_night_mode'],
        type: 'Standard', // Will sort and assign later
      ));
    }

    // 3. Sort and assign types — always produce exactly 3 (Safest, Fastest, Shortest)
    if (evaluatedRoutes.isEmpty) return [];

    // Identify best index for each category
    int safestIdx = 0;
    int fastestIdx = 0;
    int shortestIdx = 0;

    for (int i = 1; i < evaluatedRoutes.length; i++) {
      if (evaluatedRoutes[i].riskScore < evaluatedRoutes[safestIdx].riskScore) {
        safestIdx = i;
      }
      if (googleRoutes[i].durationSeconds < googleRoutes[fastestIdx].durationSeconds) {
        fastestIdx = i;
      }
      if (googleRoutes[i].distanceMeters < googleRoutes[shortestIdx].distanceMeters) {
        shortestIdx = i;
      }
    }

    // Build exactly 3 route evaluations (may reuse same route under different labels)
    RouteEvaluation makeRoute(int idx, String type) {
      return RouteEvaluation(
        polyline: evaluatedRoutes[idx].polyline,
        distanceText: evaluatedRoutes[idx].distanceText,
        durationText: evaluatedRoutes[idx].durationText,
        riskScore: evaluatedRoutes[idx].riskScore,
        isNightModeActive: evaluatedRoutes[idx].isNightModeActive,
        type: type,
      );
    }

    return [
      makeRoute(safestIdx, 'Safest'),
      makeRoute(fastestIdx, 'Fastest'),
      makeRoute(shortestIdx, 'Shortest'),
    ];
  }

  Future<Map<String, dynamic>> _evaluateRouteWithBackend(List<LatLng> path) async {
    try {
      final List<List<double>> polylineData = path.map((p) => [p.latitude, p.longitude]).toList();
      
      final response = await http.post(
        Uri.parse(ApiConstants.routeEvaluate),
        headers: {"Content-Type": "application/json"},
        body: json.encode(polylineData),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Error evaluating route with backend: $e');
    }
    
    // Fallback logic
    return {"risk_score": 2.5, "is_night_mode": false};
  }
}
