import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../auth/application/auth_providers.dart';
import '../../ride/data/maps_service.dart';
import '../../ride/presentation/ride_tracking_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _defaultCamera = LatLng(6.5244, 3.3792);
  static const _baseFare = 500;
  static const _farePerKm = 120;

  final _mapsService = MapsService();
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();
  final _pickupFocus = FocusNode();
  final _destinationFocus = FocusNode();

  GoogleMapController? _mapController;
  RidePlace? _pickup;
  RidePlace? _destination;
  RideRoute? _route;
  List<PlaceSuggestion> _suggestions = const [];
  Timer? _searchTimer;
  int _searchRequest = 0;
  bool _searchPickup = false;
  bool _showSuggestions = false;
  bool _loadingLocation = true;
  bool _loadingRoute = false;
  bool _requestingRide = false;
  String? _locationError;
  String? _mapsError;

  @override
  void initState() {
    super.initState();
    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus) _activateSearch(pickup: true);
    });
    _destinationFocus.addListener(() {
      if (_destinationFocus.hasFocus) _activateSearch(pickup: false);
    });
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _pickupController.dispose();
    _destinationController.dispose();
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on location services to set your pickup.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission is needed to set your pickup.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Enable location permission in your device settings.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final location = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _pickup = RidePlace(address: 'Current location', location: location);
        _pickupController.text = 'Current location';
        _loadingLocation = false;
        _locationError = null;
      });
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(location, 15),
      );
      await _updateRoute();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _locationError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _activateSearch({required bool pickup}) {
    setState(() {
      _searchPickup = pickup;
      _showSuggestions = true;
      _suggestions = const [];
    });
  }

  void _searchPlaces(String query) {
    _searchTimer?.cancel();
    setState(() {
      if (_searchPickup) {
        _pickup = null;
      } else {
        _destination = null;
      }
      _route = null;
      _mapsError = null;
      _suggestions = const [];
    });
    if (query.trim().length < 2) {
      return;
    }

    final request = ++_searchRequest;
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final suggestions = await _mapsService.autocomplete(query);
        if (!mounted || request != _searchRequest) return;
        setState(() {
          _suggestions = suggestions;
          _mapsError = suggestions.isEmpty ? 'No places found.' : null;
        });
      } catch (error) {
        if (!mounted || request != _searchRequest) return;
        setState(() {
          _suggestions = const [];
          _mapsError = error.toString();
        });
      }
    });
  }

  Future<void> _choosePlace(PlaceSuggestion suggestion) async {
    final selectingPickup = _searchPickup;
    _searchTimer?.cancel();
    ++_searchRequest;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _showSuggestions = false;
      _suggestions = const [];
      _mapsError = null;
      _loadingRoute = true;
    });
    try {
      final place = await _mapsService.placeDetails(suggestion);
      if (!mounted) return;
      setState(() {
        if (selectingPickup) {
          _pickup = place;
          _pickupController.text = place.address;
        } else {
          _destination = place;
          _destinationController.text = place.address;
        }
        _loadingRoute = false;
      });
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(place.location, 13),
      );
      await _updateRoute();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRoute = false;
        _mapsError = error.toString();
      });
    }
  }

  Future<void> _updateRoute() async {
    final pickup = _pickup;
    final destination = _destination;
    if (pickup == null || destination == null) return;

    setState(() {
      _loadingRoute = true;
      _route = null;
      _mapsError = null;
    });
    try {
      final route = await _mapsService.directions(
        origin: pickup.location,
        destination: destination.location,
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _loadingRoute = false;
      });
      await _fitRoute(route.points);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRoute = false;
        _mapsError = error.toString();
      });
    }
  }

  Future<void> _fitRoute(List<LatLng> points) async {
    final controller = _mapController;
    if (controller == null || points.isEmpty) return;
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final point in points.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }
    if (minLat == maxLat && minLng == maxLng) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  int get _fare => _route == null
      ? _baseFare
      : _baseFare + (_route!.distanceKm * _farePerKm).round();

  Future<void> _requestRide() async {
    final user = ref.read(authStateProvider).valueOrNull;
    final pickup = _pickup;
    final destination = _destination;
    final route = _route;
    if (user == null ||
        pickup == null ||
        destination == null ||
        route == null) {
      return;
    }

    setState(() => _requestingRide = true);
    try {
      final ride = await FirebaseFirestore.instance.collection('rides').add({
        'riderId': user.uid,
        'driverId': null,
        'pickup': {
          'address': pickup.address,
          'lat': pickup.location.latitude,
          'lng': pickup.location.longitude,
        },
        'dropoff': {
          'address': destination.address,
          'lat': destination.location.latitude,
          'lng': destination.location.longitude,
        },
        'status': 'requested',
        'fare': _fare,
        'distanceKm': route.distanceKm,
        'paid': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _requestingRide = false;
        _destination = null;
        _destinationController.clear();
        _route = null;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RideTrackingScreen(rideId: ride.id),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _requestingRide = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not request ride: $error')));
    }
  }

  Set<Marker> get _markers => {
    if (_pickup != null)
      Marker(
        markerId: const MarkerId('pickup'),
        position: _pickup!.location,
        infoWindow: InfoWindow(title: 'Pickup', snippet: _pickup!.address),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    if (_destination != null)
      Marker(
        markerId: const MarkerId('destination'),
        position: _destination!.location,
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: _destination!.address,
        ),
      ),
  };

  Set<Polyline> get _polylines => {
    if (_route != null)
      Polyline(
        polylineId: const PolylineId('ride-route'),
        points: _route!.points,
        color: Theme.of(context).colorScheme.primary,
        width: 6,
      ),
  };

  @override
  Widget build(BuildContext context) {
    final canRequest =
        ref.watch(authStateProvider).valueOrNull != null &&
        _pickup != null &&
        _destination != null &&
        _route != null &&
        !_loadingRoute &&
        !_requestingRide;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Where to?'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _defaultCamera,
              zoom: 12,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              if (_pickup != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(_pickup!.location, 15),
                );
              }
            },
            myLocationEnabled: !_loadingLocation && _locationError == null,
            myLocationButtonEnabled: true,
            markers: _markers,
            polylines: _polylines,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
          ),
          Positioned(top: 12, left: 12, right: 12, child: _searchCard()),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _fareCard(canRequest),
          ),
        ],
      ),
    );
  }

  Widget _searchCard() {
    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_locationError != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _locationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _getCurrentLocation,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            if (_loadingLocation) const LinearProgressIndicator(minHeight: 2),
            _searchField(
              pickup: true,
              controller: _pickupController,
              focusNode: _pickupFocus,
              label: 'Pickup location',
              icon: Icons.trip_origin,
              color: Colors.green.shade700,
            ),
            const Divider(height: 1, indent: 42),
            _searchField(
              pickup: false,
              controller: _destinationController,
              focusNode: _destinationFocus,
              label: 'Where are you going?',
              icon: Icons.location_on,
              color: Theme.of(context).colorScheme.error,
            ),
            if (_showSuggestions && _suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        suggestion.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _choosePlace(suggestion),
                    );
                  },
                ),
              ),
            if (_showSuggestions && _mapsError != null) _errorText(_mapsError!),
            if (_loadingRoute)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchField({
    required bool pickup,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            readOnly: pickup && _loadingLocation,
            textInputAction: TextInputAction.search,
            onTap: () => _activateSearch(pickup: pickup),
            onChanged: _searchPlaces,
            decoration: InputDecoration(
              hintText: label,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        controller.clear();
                        _searchPlaces('');
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorText(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );

  Widget _fareCard(bool canRequest) {
    final route = _route;
    return Material(
      elevation: 7,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.route_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    route == null
                        ? 'Choose pickup and destination'
                        : '${route.distanceKm.toStringAsFixed(1)} km trip',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '₦$_fare',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '₦$_baseFare base + ₦$_farePerKm/km',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_mapsError != null && !_showSuggestions && route == null)
              _errorText(_mapsError!),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: canRequest ? _requestRide : null,
              icon: _requestingRide
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_taxi_outlined),
              label: Text(_requestingRide ? 'Requesting…' : 'Request Ride'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
