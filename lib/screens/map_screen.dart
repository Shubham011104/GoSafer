import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../services/crime_service.dart';
import '../services/route_service.dart';
import '../services/sos_service.dart';
import '../components/ride_planner_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late CrimeService _crimeService;
  late RouteService _routeService;
  final SosService _sosService = SosService();
  StreamSubscription<Position>? _positionStream;
  bool _isResponding = false;
  
  // Rescue Mode State
  bool _isRescueMode = false;
  String? _victimName;
  LatLng? _victimLocation;
  StreamSubscription<DocumentSnapshot>? _victimStream;
  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;
  
  static const CameraPosition _puneInitialPosition = CameraPosition(
    target: LatLng(18.5204, 73.8567), // Pune City Center
    zoom: 12.0,
  );

  Set<Polyline> _polylines = {};
  Set<Circle> _heatmapCircles = {};
  Set<Marker> _markers = {};
  List<RouteEvaluation> _availableRoutes = [];
  RouteEvaluation? _selectedRoute;
  bool _isLoading = true;
  bool _isRoutingMode = false;
  GoogleMapController? _mapController;
  
  LatLng? _currentLocation;
  double _currentHeading = 0;
  double _currentAccuracy = 0;
  bool _myLocationEnabled = false;
  bool _isFollowingUser = true;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initServices();
  }

  void _initAnimations() {
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
    // Removed addListener(() => setState(() {})) to stop 60FPS full-screen rebuilds
    // The ripple will now update only when other state changes (like location)
    // or we can use an AnimatedBuilder for just the marker if needed later.
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _victimStream?.cancel();
    _rippleController.dispose();
    super.dispose();
  }

  Future<void> _initServices() async {
    _crimeService = CrimeService();
    _routeService = RouteService();
    await _crimeService.init();
    _generateHeatmap();
    await _checkLocationPermission();
    
    // Listen for Rescues
    NotificationService.activeRescue.addListener(_checkActiveRescues);
    NotificationService.statusUpdate.addListener(_handleStatusUpdate);
    _checkActiveRescues(); // Catch initial on startup

    setState(() {
      _isLoading = false;
    });
  }

  void _checkActiveRescues() {
    final rescue = NotificationService.activeRescue.value;
    if (rescue != null && !_isRescueMode) {
      _startRescueTracking(
        rescue['victim_uid'],
        rescue['caller_name'],
        LatLng(rescue['latitude'], rescue['longitude']),
      );
    }
  }

  void _startRescueTracking(String uid, String name, LatLng initialLocation) {
    _victimStream?.cancel();
    
    setState(() {
      _isRescueMode = true;
      _victimName = name;
      _victimLocation = initialLocation;
      _isFollowingUser = false; // Zoom to both or victim
    });

    // Listen to live updates of the victim
    _victimStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        
        if (lat != null && lng != null) {
          setState(() {
            _victimLocation = LatLng(lat, lng);
            _updateRescueCamera();
          });
        }
      }
    });

    // Reset the notifier so it doesn't trigger again on every rebuild
    // NotificationService.activeRescue.value = null;
  }

  void _updateRescueCamera() {
    if (_mapController == null || _victimLocation == null || _currentLocation == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(
        _currentLocation!.latitude < _victimLocation!.latitude ? _currentLocation!.latitude : _victimLocation!.latitude,
        _currentLocation!.longitude < _victimLocation!.longitude ? _currentLocation!.longitude : _victimLocation!.longitude,
      ),
      northeast: LatLng(
        _currentLocation!.latitude > _victimLocation!.latitude ? _currentLocation!.latitude : _victimLocation!.latitude,
        _currentLocation!.longitude > _victimLocation!.longitude ? _currentLocation!.longitude : _victimLocation!.longitude,
      ),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  void _exitRescueMode() {
    _victimStream?.cancel();
    setState(() {
      _isRescueMode = false;
      _victimName = null;
      _victimLocation = null;
      NotificationService.activeRescue.value = null;
    });
  }

  Future<void> _openNavigation() async {
    if (_victimLocation == null) return;
    
    final url = 'google.navigation:q=${_victimLocation!.latitude},${_victimLocation!.longitude}';
    final fallbackUrl = 'https://www.google.com/maps/search/?api=1&query=${_victimLocation!.latitude},${_victimLocation!.longitude}';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      await launchUrl(Uri.parse(fallbackUrl));
    }
  }

  void _handleStatusUpdate() {
    final status = NotificationService.statusUpdate.value;
    if (status != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _respondToEmergency() async {
    final rescue = NotificationService.activeRescue.value;
    if (rescue == null) return;

    setState(() => _isResponding = true);
    try {
      await _sosService.respondToSos(rescue['victim_uid']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Response sent! The user has been notified."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled. Please enable GPS.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      setState(() => _myLocationEnabled = true);
      await _goToCurrentLocation();
      return;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are permanently denied. Please enable them in settings.')),
        );
      }
      return;
    }

    // After permission is granted, enable tracking and move camera
    setState(() => _myLocationEnabled = true);
    _startLocationTracking();
  }

  void _startLocationTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _currentLocation = latLng;
        _currentHeading = position.heading;
        _currentAccuracy = position.accuracy;
      });

      if (_isFollowingUser && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: latLng,
              zoom: 15.0,
              tilt: 45.0, // Slight tilt for navigation feel
            ),
          ),
        );
      }
    });
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _isFollowingUser = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final latLng = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _currentLocation = latLng;
        _currentHeading = position.heading;
      });

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: latLng, zoom: 15.0, tilt: 45.0),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch current location.')),
        );
      }
    }
  }

  void _generateHeatmap() {
    final points = _crimeService.getHeatmapPoints();
    if (points.isEmpty) return;

    // Optimization: Clustering points into a grid to reduce Circle count for GPU performance
    // This groups points into ~250m grid squares
    final Map<String, List<WeightedLatLng>> clusters = {};
    for (var p in points) {
      final double gridLat = (p.point.latitude * 400).roundToDouble() / 400;
      final double gridLng = (p.point.longitude * 400).roundToDouble() / 400;
      final String key = "$gridLat,$gridLng";
      clusters.putIfAbsent(key, () => []).add(p);
    }

    final heatmapCircles = clusters.entries.map((entry) {
      final coords = entry.key.split(',');
      final lat = double.parse(coords[0]);
      final lng = double.parse(coords[1]);
      final double totalWeight = entry.value.fold(0, (acc, p) => acc + p.weight);
      
      return Circle(
        circleId: CircleId("heat_cluster_${entry.key}"),
        center: LatLng(lat, lng),
        radius: 400, // Slightly larger for clusters
        fillColor: _getHeatmapColor(totalWeight.toInt()),
        strokeWidth: 0,
      );
    }).toSet();
    
    setState(() {
      _heatmapCircles = heatmapCircles;
    });
  }

  Color _getHeatmapColor(int risk) {
    if (risk <= 1) return Colors.green.withValues(alpha: 0.2);
    if (risk == 2) return Colors.lightGreen.withValues(alpha: 0.25);
    if (risk == 3) return Colors.yellow.withValues(alpha: 0.3);
    if (risk == 4) return Colors.orange.withValues(alpha: 0.35);
    return Colors.red.withValues(alpha: 0.4);
  }

  Future<void> _handleRouteSelection(LatLng start, LatLng end) async {
    setState(() {
      _isLoading = true;
      
      // Add Map Markers
      _markers = {
        Marker(
          markerId: const MarkerId('pickup'),
          position: start,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Pickup Location'),
        ),
        Marker(
          markerId: const MarkerId('dest'),
          position: end,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      };
    });

    try {
      final results = await _routeService.getRouteRecommendations(start, end);
      
      setState(() {
        _availableRoutes = results;
        _selectedRoute = results.firstWhere((r) => r.type == 'Safest', orElse: () => results.first);
        _isLoading = false;
        _updatePolylines();
      });

      // Adjust Camera to fit the selected route
      if (_mapController != null && _selectedRoute != null && _selectedRoute!.polyline.isNotEmpty) {
        double minLat = _selectedRoute!.polyline.first.latitude;
        double maxLat = _selectedRoute!.polyline.first.latitude;
        double minLng = _selectedRoute!.polyline.first.longitude;
        double maxLng = _selectedRoute!.polyline.first.longitude;

        for (var point in _selectedRoute!.polyline) {
          if (point.latitude < minLat) minLat = point.latitude;
          if (point.latitude > maxLat) maxLat = point.latitude;
          if (point.longitude < minLng) minLng = point.longitude;
          if (point.longitude > maxLng) maxLng = point.longitude;
        }

        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            100, // padding
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to calculate routes. Please try again.')),
      );
    }
  }

  void _updatePolylines() {
    setState(() {
      _polylines = _availableRoutes.map((route) {
        bool isSelected = _selectedRoute?.type == route.type;
        return Polyline(
          polylineId: PolylineId(route.type),
          points: route.polyline,
          color: _getRouteColor(route.type, isSelected),
          width: isSelected ? 6 : 4,
          zIndex: isSelected ? 1 : 0,
          onTap: () {
            setState(() {
              _selectedRoute = route;
              _updatePolylines();
            });
          },
        );
      }).toSet();
    });
  }

  Color _getRouteColor(String type, bool isSelected) {
    if (!isSelected) return Colors.grey.withValues(alpha: 0.5);
    switch (type) {
      case 'Fastest': return Colors.red;
      case 'Shortest': return Colors.blue;
      case 'Safest': return Colors.green;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);

    // Combine custom user indicator with other map layers
    Set<Marker> allMarkers = Set.from(_markers);
    Set<Circle> allCircles = Set.from(_heatmapCircles);

    if (_currentLocation != null && _myLocationEnabled) {
      // 1. Accuracy/Ripple Circles
      double rippleRadius = _currentAccuracy > 0 ? _currentAccuracy * (1 + _rippleAnimation.value * 0.5) : 100 * (1 + _rippleAnimation.value * 0.5);
      
      allCircles.add(Circle(
        circleId: const CircleId('user_ripple'),
        center: _currentLocation!,
        radius: rippleRadius,
        fillColor: AppColors.primary.withValues(alpha: 0.15 * (1 - _rippleAnimation.value)),
        strokeWidth: 0,
      ));

      // 2. User Location Marker (Blue Dot + Arrow)
      allMarkers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: _currentLocation!,
        rotation: _currentHeading,
        anchor: const Offset(0.5, 0.5),
        flat: true, // Marker rotates with map tilt
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), 
        zIndexInt: 10,
      ));
    }

    // 3. Victim Marker (Blinking Red)
    if (_isRescueMode && _victimLocation != null) {
      allMarkers.add(Marker(
        markerId: const MarkerId('victim_location'),
        position: _victimLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'HELP: $_victimName'),
        zIndexInt: 20,
      ));

      allCircles.add(Circle(
        circleId: const CircleId('victim_pulse'),
        center: _victimLocation!,
        radius: 200 * (1 + _rippleAnimation.value),
        fillColor: Colors.red.withValues(alpha: 0.2 * (1 - _rippleAnimation.value)),
        strokeWidth: 0,
      ));
    }
    
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              // Check for initial rescue if app was opened from cold start
              _checkActiveRescues();
            },
            onCameraMove: (position) {
            },
            initialCameraPosition: _puneInitialPosition,
            myLocationEnabled: false, 
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            padding: EdgeInsets.only(bottom: _isRescueMode ? 200 : 120), 
            polylines: _polylines,
            circles: allCircles,
            markers: allMarkers,
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          
          // Header Overlay
          if (_isRescueMode)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emergency, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("RESCUE MODE ACTIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text("Tracking $_victimName's location LIVE", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _exitRescueMode,
                    )
                  ],
                ),
              ),
            ),
          
          // Search Bar Trigger
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: _isRoutingMode
              ? RidePlannerPanel(
                  onRouteSelected: (pickup, dest) {
                    setState(() => _isRoutingMode = false);
                    _handleRouteSelection(pickup, dest);
                  },
                  onCancel: () {
                    setState(() => _isRoutingMode = false);
                  },
                )
              : Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: () => setState(() => _isRoutingMode = true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                Icon(Icons.search, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Search safety-optimized route...',
                                    style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => themeProvider.toggleTheme(),
                      child: _buildCircularButton(themeProvider.isDarkMode ? Icons.dark_mode : Icons.wb_sunny_outlined, theme),
                    ),
                  ],
                ),
          ),

          // Floating Action Buttons
          Positioned(
            top: 140,
            right: 20,
            child: Column(
              children: [
                InkWell(
                  onTap: _goToCurrentLocation,
                  child: _buildMapActionButton(Icons.my_location),
                ),
              ],
            ),
          ),

          // Route Selection Panel (Ola/Uber Style)
          if (_selectedRoute != null && !_isRescueMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 16),
                    const Text("SELECT YOUR ROUTE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _availableRoutes.length,
                        itemBuilder: (context, index) {
                          final route = _availableRoutes[index];
                          final isSelected = _selectedRoute?.type == route.type;
                          final routeColor = _getRouteColor(route.type, true);
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedRoute = route;
                                _updatePolylines();
                              });
                            },
                            child: Container(
                              width: 150,
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected ? routeColor.withValues(alpha: 0.08) : theme.cardColor,
                                border: Border.all(color: isSelected ? routeColor : Colors.grey[300]!, width: 2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(route.type, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? routeColor : theme.textTheme.bodyLarge?.color)),
                                      if (route.type == 'Safest')
                                        const Icon(Icons.stars, color: Colors.green, size: 16),
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(route.durationText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  Text("${route.distanceText} • ${route.riskScore.toStringAsFixed(1)} Risk", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _getRouteColor(_selectedRoute!.type, true),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        onPressed: () {
                          // Start Navigation Flow
                          setState(() {
                            _selectedRoute = null; // Hide panel
                            _isFollowingUser = true;
                          });
                          _mapController?.animateCamera(
                            CameraUpdate.newCameraPosition(
                              CameraPosition(target: _currentLocation ?? _puneInitialPosition.target, zoom: 18, tilt: 45),
                            ),
                          );
                        },
                        child: const Text("Confirm & Navigate", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Rescue Mode Panel
          if (_isRescueMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                          child: const Icon(Icons.person, color: Colors.red),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_victimName ?? "User", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Text("Emergency Alert Triggered", style: TextStyle(color: Colors.red, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                          child: const Text("Live Tracking", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              icon: _isResponding 
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                : const Icon(Icons.directions_run, color: AppColors.primary),
                              label: const Text("Coming", style: TextStyle(color: AppColors.primary)),
                              onPressed: _isResponding ? null : _respondToEmergency,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primary),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.navigation, color: Colors.white),
                              label: const Text("Navigate", style: TextStyle(color: Colors.white)),
                              onPressed: _openNavigation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircularButton(IconData icon, ThemeData theme, {bool hasBadge = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? AppColors.borderDark : const Color(0xFFF1F5F9),
        shape: BoxShape.circle,
      ),
      child: Stack(
        children: [
          Icon(icon, color: theme.colorScheme.onSurface, size: 24),
          if (hasBadge)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: theme.cardColor, width: 2)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapActionButton(IconData icon, {bool isActive = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: Icon(icon, color: isActive ? Colors.white : AppColors.textPrimary),
    );
  }
}

