import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../constants/api_constants.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}
class PlacesService {
  Future<List<PlaceSuggestion>> getAutocompleteSuggestions(String input) async {
    if (input.isEmpty) return [];

    final url = Uri.parse(
        '${ApiConstants.placesAutocomplete}?input=$input'
    );

    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final List predictions = data['predictions'];
          return predictions.map((p) => PlaceSuggestion(
            placeId: p['place_id'],
            description: p['description'],
            mainText: p['structured_formatting']['main_text'],
            secondaryText: p['structured_formatting']['secondary_text'] ?? '',
          )).toList();
        }
      }
    } catch (e) {
      // Error handling without print for production
    }
    
    return [];
  }

  Future<LatLng?> getPlaceDetails(String placeId) async {
    final url = Uri.parse(
        '${ApiConstants.placesDetails}?place_id=$placeId'
    );

    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          return LatLng(location['lat'], location['lng']);
        }
      }
    } catch (e) {
      // Error handling without print for production
    }
    
    return null;
  }
}
