import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_colors.dart';

import '../services/places_service.dart';

class RidePlannerPanel extends StatefulWidget {
  final Function(LatLng pickup, LatLng destination) onRouteSelected;
  final VoidCallback onCancel;

  const RidePlannerPanel({super.key, required this.onRouteSelected, required this.onCancel});

  @override
  State<RidePlannerPanel> createState() => _RidePlannerPanelState();
}

class _RidePlannerPanelState extends State<RidePlannerPanel> {
  final PlacesService _placesService = PlacesService();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _destFocus = FocusNode();
  
  LatLng? _pickupLocation;
  LatLng? _destLocation;
  bool _isLoading = false;
  
  List<PlaceSuggestion> _suggestions = [];
  final List<String> _recentSearches = ['Kothrud, Pune', 'Shivajinagar, Pune', 'Hinjewadi Phase 1'];
  Timer? _debounce;
  bool _showSuggestions = false;
  bool _isPickupActive = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _pickupFocus.addListener(_onFocusChange);
    _destFocus.addListener(_onFocusChange);
    _getCurrentLocation();
  }

  void _onFocusChange() {
    if (_pickupFocus.hasFocus) {
      setState(() {
        _isPickupActive = true;
        _showSuggestions = _pickupController.text.length >= 2;
      });
    } else if (_destFocus.hasFocus) {
      setState(() {
        _isPickupActive = false;
        _showSuggestions = _destController.text.length >= 2;
      });
    } else {
      // Delay hiding suggestions so onTap on a ListTile can fire first
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_pickupFocus.hasFocus && !_destFocus.hasFocus) {
          setState(() => _showSuggestions = false);
        }
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _pickupLocation = latLng;
        _pickupController.text = "Current Location";
        _isLoading = false;
      });
      _checkAndSubmit();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destController.dispose();
    _pickupFocus.dispose();
    _destFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    
    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
      
      
      try {
        final results = await _placesService.getAutocompleteSuggestions(query);
        setState(() {
          _suggestions = results;
          _showSuggestions = true;
          _isLoading = false;
          if (results.isEmpty) _errorMessage = 'No matching places found';
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Connection error. Is backend running?';
        });
      }
    });
  }

  void _checkAndSubmit() {
    if (_pickupLocation != null && _destLocation != null) {
      widget.onRouteSelected(_pickupLocation!, _destLocation!);
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _showSuggestions = false;
      _isLoading = true;
      if (_isPickupActive) {
        _pickupController.text = suggestion.mainText;
      } else {
        _destController.text = suggestion.mainText;
      }
    });

    final latLng = await _placesService.getPlaceDetails(suggestion.placeId);
    
    setState(() {
      _isLoading = false;
      if (latLng != null) {
        if (!_recentSearches.contains(suggestion.mainText)) {
          _recentSearches.insert(0, suggestion.mainText);
          if (_recentSearches.length > 5) _recentSearches.removeLast();
        }
        
        if (_isPickupActive) {
          _pickupLocation = latLng;
        } else {
          _destLocation = latLng;
        }
        _checkAndSubmit();
      } else {
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8, right: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
                  onPressed: widget.onCancel,
                ),
                const Text(
                  'Plan Safe Route',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
              ],
            ),
          ),
          
          // Input Fields
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Column(
                  children: [
                    const Icon(Icons.my_location, size: 16, color: AppColors.primary),
                    Container(
                      width: 1,
                      height: 40,
                      color: isDark ? AppColors.borderDark : AppColors.border,
                    ),
                    const Icon(Icons.location_on, size: 16, color: Colors.blue),
                  ],
                ),
                const SizedBox(width: 16),
                
                Expanded(
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: _pickupController,
                        focusNode: _pickupFocus,
                        hint: 'Pickup Location',
                        isDark: isDark,
                        suffixIcon: Icons.gps_fixed,
                        onSuffixTap: _getCurrentLocation,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _destController,
                        focusNode: _destFocus,
                        hint: 'Where to?',
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Error Message
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),

          // Suggestions List
          if (_showSuggestions || (_pickupFocus.hasFocus && _pickupController.text.isEmpty) || (_destFocus.hasFocus && _destController.text.isEmpty))
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   // "Use Current Location" - Always show first if focused on empty field or searching
                  if ((_isPickupActive && _pickupController.text.isEmpty) || (!_isPickupActive && _destController.text.isEmpty) || _suggestions.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.gps_fixed, size: 18, color: AppColors.primary),
                      title: const Text('Use Current Location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      onTap: _getCurrentLocation,
                      dense: true,
                    ),
                  
                  if ((_isPickupActive && _pickupController.text.isEmpty && _recentSearches.isNotEmpty) || (!_isPickupActive && _destController.text.isEmpty && _recentSearches.isNotEmpty))
                    ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('RECENT SEARCHES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textHint)),
                      ),
                      ..._recentSearches.map((s) => ListTile(
                        leading: const Icon(Icons.history, size: 18, color: AppColors.textHint),
                        title: Text(s, style: const TextStyle(fontSize: 14)),
                        onTap: () {
                           if (_isPickupActive) {
                             _pickupController.text = s;
                             _onSearchChanged(s);
                           } else {
                             _destController.text = s;
                             _onSearchChanged(s);
                           }
                        },
                        dense: true,
                      )),
                    ],

                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Expanded(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: isDark ? AppColors.borderDark : AppColors.border),
                        itemBuilder: (context, index) {
                          final s = _suggestions[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primary),
                            title: Text(s.mainText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: Text(s.secondaryText, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                            onTap: () => _selectSuggestion(s),
                            dense: true,
                          );
                        },
                      ),
                    ),
                  
                  if (_showSuggestions && _suggestions.isEmpty && !_isLoading && _errorMessage.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No results found', style: TextStyle(color: AppColors.textHint)),
                    ),
                ],
              ),
            ),
            
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required bool isDark,
    IconData? suffixIcon,
    VoidCallback? onSuffixTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: _onSearchChanged,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: suffixIcon != null 
            ? IconButton(icon: Icon(suffixIcon, size: 18, color: AppColors.primary), onPressed: onSuffixTap) 
            : null,
        ),
      ),
    );
  }
}
