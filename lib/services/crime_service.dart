import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';

class ClusterCentroid {
  final double lat;
  final double lng;
  final int riskScore;
  final String safetyLevel;

  ClusterCentroid({
    required this.lat,
    required this.lng,
    required this.riskScore,
    required this.safetyLevel,
  });

  factory ClusterCentroid.fromJson(Map<String, dynamic> json) {
    return ClusterCentroid(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      riskScore: json['risk_score'] as int,
      safetyLevel: json['safety_level'] as String,
    );
  }
}

class CrimeService {
  List<ClusterCentroid> _centroids = [];
  List<WeightedLatLng> _heatmapPoints = [];
  bool _isDataLoaded = false;

  bool get isDataLoaded => _isDataLoaded;
  List<ClusterCentroid> get centroids => _centroids;

  Future<void> init() async {
    if (_isDataLoaded) return;
    try {
      await _fetchCentroids();
      await _fetchHeatmap();
      _isDataLoaded = true;
    } catch (e) {
      debugPrint('Error initializing CrimeService: $e');
    }
  }

  Future<void> _fetchCentroids() async {
    try {
      final response = await http.get(Uri.parse(ApiConstants.crimeCentroids));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _centroids = data.map((item) => ClusterCentroid.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching centroids: $e');
    }
  }

  Future<void> _fetchHeatmap() async {
    try {
      final response = await http.get(Uri.parse(ApiConstants.crimeHeatmap));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _heatmapPoints = data.map((item) {
          return WeightedLatLng(
            LatLng((item['lat'] as num).toDouble(), (item['lng'] as num).toDouble()),
            weight: (item['total_crime'] as num).toDouble(),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error fetching heatmap: $e');
    }
  }

  List<WeightedLatLng> getHeatmapPoints() => _heatmapPoints;
  
  int getRiskScoreAt(LatLng position) {
    if (_centroids.isEmpty) return 2;
    double minDistance = double.infinity;
    int risk = 2;
    for (var c in _centroids) {
      double dist = (position.latitude - c.lat) * (position.latitude - c.lat) +
                    (position.longitude - c.lng) * (position.longitude - c.lng);
      if (dist < minDistance) {
        minDistance = dist;
        risk = c.riskScore;
      }
    }
    return risk;
  }
}
