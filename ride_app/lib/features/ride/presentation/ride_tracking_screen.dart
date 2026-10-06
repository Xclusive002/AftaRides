import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../payment/presentation/paystack_payment_screen.dart';

class RideTrackingScreen extends ConsumerStatefulWidget {
  const RideTrackingScreen({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rideSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _driverSubscription;
  late final AnimationController _markerAnimation;

  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _driver;
  String? _subscribedDriverId;
  String? _error;
  bool _loading = true;
  bool _paymentScreenOpened = false;
  LatLng? _animatedDriverPosition;
  LatLng? _animationStart;
  LatLng? _animationEnd;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _markerAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(_tickMarkerAnimation);
    _listenToRide();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    _driverSubscription?.cancel();
    _markerAnimation
      ..removeListener(_tickMarkerAnimation)
      ..dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _listenToRide() {
    _rideSubscription = FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.rideId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists) {
              setState(() {
                _loading = false;
                _error = 'This ride could not be found.';
              });
              return;
            }
            final ride = snapshot.data()!;
            final driverId = ride['driverId'] as String?;
            setState(() {
              _ride = ride;
              _loading = false;
              _error = null;
            });
            _listenToDriver(driverId);
            if (ride['status'] == 'completed' && ride['paid'] != true) {
              _openPaymentOnce(ride);
            }
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = 'Unable to load ride updates: $error';
            });
          },
        );
  }

  void _openPaymentOnce(Map<String, dynamic> ride) {
    if (_paymentScreenOpened) return;
    _paymentScreenOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _status != 'completed' || _ride?['paid'] == true) return;
      _openPayment(ride);
    });
  }

  Future<void> _openPayment(Map<String, dynamic> ride) async {
    final fareValue = ride['fare'];
    if (fareValue is! num) {
      setState(() => _error = 'This ride has no valid fare to pay.');
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaystackPaymentScreen(
          rideId: widget.rideId,
          fareNaira: fareValue.round(),
          email: FirebaseAuth.instance.currentUser?.email ?? '',
        ),
      ),
    );
  }

  void _listenToDriver(String? driverId) {
    if (driverId == _subscribedDriverId) return;
    _driverSubscription?.cancel();
    _subscribedDriverId = driverId;
    _driver = null;
    _animatedDriverPosition = null;
    if (driverId == null || driverId.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    _driverSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final driver = snapshot.data();
            setState(() => _driver = driver);
            final location = _readLocation(driver);
            if (location != null) {
              _animateDriverTo(location);
            } else if (driver == null && mounted) {
              setState(() => _animatedDriverPosition = null);
            }
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _error = 'Unable to load driver location: $error');
          },
        );
  }

  LatLng? _readLocation(Map<String, dynamic>? data) {
    if (data == null) return null;
    final location = data['location'];
    if (location is GeoPoint) {
      return LatLng(location.latitude, location.longitude);
    }
    if (location is Map) {
      final lat = location['lat'] ?? location['latitude'];
      final lng = location['lng'] ?? location['longitude'];
      if (lat is num && lng is num) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    final lat = data['lat'] ?? data['latitude'];
    final lng = data['lng'] ?? data['longitude'];
    if (lat is num && lng is num) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  void _animateDriverTo(LatLng next) {
    _animationStart = _animatedDriverPosition ?? next;
    _animationEnd = next;
    _markerAnimation.forward(from: 0);
    if (_animatedDriverPosition == null) {
      setState(() => _animatedDriverPosition = next);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(next, 15));
    }
  }

  void _tickMarkerAnimation() {
    final start = _animationStart;
    final end = _animationEnd;
    if (start == null || end == null || !mounted) return;
    final t = Curves.easeInOut.transform(_markerAnimation.value);
    setState(() {
      _animatedDriverPosition = LatLng(
        start.latitude + (end.latitude - start.latitude) * t,
        start.longitude + (end.longitude - start.longitude) * t,
      );
    });
  }

  LatLng? _pointFromRide(String field) {
    final value = _ride?[field];
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    if (value is Map) {
      final lat = value['lat'] ?? value['latitude'];
      final lng = value['lng'] ?? value['longitude'];
      if (lat is num && lng is num) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  String _addressFromRide(String field) {
    final value = _ride?[field];
    if (value is Map) return value['address'] as String? ?? '';
    return '';
  }

  String get _status =>
      (_ride?['status'] as String? ?? 'requested').toLowerCase();

  String get _statusLabel => switch (_status) {
    'requested' => 'Finding your driver',
    'accepted' => 'Driver assigned',
    'arriving' => 'Driver is on the way',
    'ongoing' => 'Ride in progress',
    'completed' => 'Ride completed',
    'cancelled' => 'Ride cancelled',
    _ => 'Ride update',
  };

  String? get _etaText {
    if (_status == 'requested') return 'ETA pending';
    if (_status == 'completed' || _status == 'cancelled') {
      return null;
    }
    final rawEta =
        _ride?['etaMinutes'] ?? _ride?['eta_min'] ?? _driver?['etaMinutes'];
    if (rawEta is num) return 'ETA ${rawEta.round()} min';

    final etaTimestamp = _ride?['eta'] ?? _driver?['eta'];
    if (etaTimestamp is Timestamp) {
      final remaining = etaTimestamp
          .toDate()
          .difference(DateTime.now())
          .inMinutes;
      return 'ETA ${remaining < 1 ? 1 : remaining} min';
    }

    final driver = _animatedDriverPosition;
    final target = _status == 'ongoing'
        ? _pointFromRide('dropoff')
        : _pointFromRide('pickup');
    if (driver == null || target == null) return 'Calculating ETA…';
    final distanceMeters = Geolocator.distanceBetween(
      driver.latitude,
      driver.longitude,
      target.latitude,
      target.longitude,
    );
    final minutes = (distanceMeters / 8.3 / 60).ceil();
    return 'ETA ~${minutes < 1 ? 1 : minutes} min';
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final pickup = _pointFromRide('pickup');
    final dropoff = _pointFromRide('dropoff');
    final driver = _animatedDriverPosition;
    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('ride-pickup'),
          position: pickup,
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: _addressFromRide('pickup'),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }
    if (dropoff != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('ride-dropoff'),
          position: dropoff,
          infoWindow: InfoWindow(
            title: 'Destination',
            snippet: _addressFromRide('dropoff'),
          ),
        ),
      );
    }
    if (driver != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('live-driver'),
          position: driver,
          infoWindow: InfoWindow(
            title: _driver?['name'] as String? ?? 'Your driver',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          zIndexInt: 2,
        ),
      );
    }
    return markers;
  }

  Set<Polyline> get _polylines {
    final driver = _animatedDriverPosition;
    final target = _status == 'ongoing'
        ? _pointFromRide('dropoff')
        : _pointFromRide('pickup');
    if (driver == null || target == null || _status == 'requested') {
      return const {};
    }
    return {
      Polyline(
        polylineId: const PolylineId('driver-to-ride'),
        points: [driver, target],
        color: Theme.of(context).colorScheme.primary,
        width: 5,
        patterns: [PatternItem.dot, PatternItem.gap(8)],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride tracking')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ride tracking')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pointFromRide('pickup') ?? const LatLng(6.5244, 3.3792),
              zoom: 14,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              final driver = _animatedDriverPosition;
              if (driver != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(driver, 15),
                );
              }
            },
            markers: _markers,
            polylines: _polylines,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
          ),
          Positioned(top: 12, left: 12, right: 12, child: _statusBanner()),
          if (_error != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    final colors = Theme.of(context).colorScheme;
    final hasDriver = _subscribedDriverId != null;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  _status == 'completed'
                      ? Icons.check_circle
                      : Icons.local_taxi,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusLabel,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_etaText != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_etaText!),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hasDriver
                  ? (_driver?['name'] as String? ?? 'Your driver is assigned')
                  : 'We’ll update this map when a driver accepts your ride.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_addressFromRide('pickup').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Pickup: ${_addressFromRide('pickup')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_status == 'completed') ...[
              const SizedBox(height: 14),
              if (_ride?['paid'] == true)
                Row(
                  children: [
                    Icon(Icons.check_circle, color: colors.primary),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Payment received')),
                    if (_ride?['paystackReference'] is String)
                      Text(
                        (_ride!['paystackReference'] as String),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _ride == null
                        ? null
                        : () => _openPayment(_ride!),
                    icon: const Icon(Icons.payment),
                    label: Text('Pay ₦${_ride?['fare'] ?? ''}'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
