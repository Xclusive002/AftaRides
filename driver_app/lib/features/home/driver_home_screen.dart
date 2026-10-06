import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({required this.user, super.key});

  final User user;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  static const _activeStatuses = ['accepted', 'arriving', 'ongoing'];

  final _firestore = FirebaseFirestore.instance;
  final _shownRideIds = <String>{};
  final _pendingRideRequests = <DocumentSnapshot<Map<String, dynamic>>>[];
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rideSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeSubscription;
  Timer? _locationPublisher;
  Position? _latestPosition;
  QueryDocumentSnapshot<Map<String, dynamic>>? _activeRide;
  bool _isOnline = false;
  bool _isChangingStatus = false;
  bool _dialogOpen = false;
  String? _error;

  DocumentReference<Map<String, dynamic>> get _driverRef =>
      _firestore.collection('drivers').doc(widget.user.uid);

  @override
  void initState() {
    super.initState();
    _loadExistingDriverState();
    _listenForActiveRide();
  }

  @override
  void dispose() {
    _stopLocationPublishing();
    _rideSubscription?.cancel();
    _activeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadExistingDriverState() async {
    try {
      final snapshot = await _driverRef.get();
      if (!mounted) return;
      final isOnline = snapshot.data()?['online'] == true;
      setState(() => _isOnline = isOnline);
      if (isOnline) {
        await _startLocationPublishing();
        _listenForRequestedRides();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load driver status: $error');
      }
    }
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showError('Turn on location services before going online.');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showError('Location permission is required to go online.');
      return false;
    }
    return true;
  }

  Future<void> _setOnline(bool online) async {
    if (online) {
      final permitted = await _ensureLocationPermission();
      if (!permitted || !mounted) return;
    }
    setState(() {
      _isChangingStatus = true;
      _error = null;
    });
    try {
      await _driverRef.set({
        'online': online,
        'uid': widget.user.uid,
        'name': widget.user.displayName ?? '',
        'email': widget.user.email ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
        if (!online) 'lastOnlineAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _isOnline = online);
      if (online) {
        await _startLocationPublishing();
        _listenForRequestedRides();
      } else {
        _stopLocationPublishing();
        await _rideSubscription?.cancel();
        _rideSubscription = null;
      }
    } catch (error) {
      _showError('Could not change availability: $error');
    } finally {
      if (mounted) setState(() => _isChangingStatus = false);
    }
  }

  Future<void> _startLocationPublishing() async {
    if (_positionSubscription != null) return;
    final permitted = await _ensureLocationPermission();
    if (!permitted) return;
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          ),
        ).listen(
          (position) {
            _latestPosition = position;
          },
          onError: (Object error) {
            if (mounted) _showError('Location updates stopped: $error');
          },
        );

    try {
      _latestPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _publishLocation(_latestPosition!);
    } catch (error) {
      if (mounted) _showError('Could not read current location: $error');
    }

    _locationPublisher?.cancel();
    _locationPublisher = Timer.periodic(const Duration(seconds: 3), (_) {
      final position = _latestPosition;
      if (position != null && _isOnline) _publishLocation(position);
    });
  }

  Future<void> _publishLocation(Position position) async {
    if (!_isOnline && !_isChangingStatus) return;
    try {
      await _driverRef.set({
        'online': true,
        'uid': widget.user.uid,
        'lat': position.latitude,
        'lng': position.longitude,
        'heading': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
        'location': GeoPoint(position.latitude, position.longitude),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to publish location: $error');
      }
    }
  }

  void _stopLocationPublishing() {
    _locationPublisher?.cancel();
    _locationPublisher = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _listenForRequestedRides() {
    if (_rideSubscription != null) return;
    _rideSubscription = _firestore
        .collection('rides')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added &&
                  !_shownRideIds.contains(change.doc.id)) {
                _shownRideIds.add(change.doc.id);
                _pendingRideRequests.add(change.doc);
              }
            }
            _showNextRideRequest();
          },
          onError: (Object error) {
            if (mounted) {
              _showError('Unable to listen for ride requests: $error');
            }
          },
        );
  }

  void _listenForActiveRide() {
    _activeSubscription = _firestore
        .collection('rides')
        .where('driverId', isEqualTo: widget.user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            QueryDocumentSnapshot<Map<String, dynamic>>? active;
            for (final document in snapshot.docs) {
              if (_activeStatuses.contains(document.data()['status'])) {
                active = document;
                break;
              }
            }
            if (mounted) {
              setState(() => _activeRide = active);
              if (active == null) _showNextRideRequest();
            }
          },
          onError: (Object error) {
            if (mounted) _showError('Unable to load your active ride: $error');
          },
        );
  }

  Future<void> _showNextRideRequest() async {
    if (!mounted ||
        !_isOnline ||
        _dialogOpen ||
        _activeRide != null ||
        _pendingRideRequests.isEmpty) {
      return;
    }
    final ride = _pendingRideRequests.removeAt(0);
    _dialogOpen = true;
    final data = ride.data() ?? <String, dynamic>{};
    final pickup = _address(data['pickup']);
    final dropoff = _address(data['dropoff']);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New ride request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rideAddress('Pickup', pickup),
            const SizedBox(height: 12),
            _rideAddress('Destination', dropoff),
            if (data['fare'] is num) ...[
              const SizedBox(height: 12),
              Text('Fare: ₦${(data['fare'] as num).round()}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Accept ride'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    var claimed = false;
    if (accepted == true && mounted) {
      claimed = await _acceptRide(ride.reference);
    }
    if (mounted && !claimed && _activeRide == null) {
      _showNextRideRequest();
    }
  }

  Widget _rideAddress(String title, String address) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(address.isEmpty ? 'Address not provided' : address),
    ],
  );

  String _address(Object? value) {
    if (value is Map) return value['address'] as String? ?? '';
    return value?.toString() ?? '';
  }

  Future<bool> _acceptRide(
    DocumentReference<Map<String, dynamic>> rideRef,
  ) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(rideRef);
        final data = snapshot.data();
        if (!snapshot.exists ||
            data?['status'] != 'requested' ||
            data?['driverId'] != null) {
          throw StateError('This ride was just accepted by another driver.');
        }
        transaction.update(rideRef, {
          'driverId': widget.user.uid,
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
      return true;
    } catch (error) {
      _showError(error.toString().replaceFirst('Bad state: ', ''));
      return false;
    }
  }

  Future<void> _advanceRide() async {
    final ride = _activeRide;
    if (ride == null) return;
    final currentStatus = ride.data()['status'] as String?;
    final nextStatus = switch (currentStatus) {
      'accepted' => 'arriving',
      'arriving' => 'ongoing',
      'ongoing' => 'completed',
      _ => null,
    };
    if (nextStatus == null) return;

    setState(() => _isChangingStatus = true);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ride.reference);
        if (!snapshot.exists ||
            snapshot.data()?['driverId'] != widget.user.uid ||
            snapshot.data()?['status'] != currentStatus) {
          throw StateError('Ride status changed. Refresh and try again.');
        }
        transaction.update(ride.reference, {
          'status': nextStatus,
          '${nextStatus}At': FieldValue.serverTimestamp(),
        });
      });
      if (nextStatus == 'completed') {
        await _driverRef.set({
          'online': _isOnline,
          'lastRideCompletedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      _showError(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _isChangingStatus = false);
    }
  }

  String _nextAction(String? status) => switch (status) {
    'accepted' => 'I’m arriving',
    'arriving' => 'Start ride',
    'ongoing' => 'Complete ride',
    _ => 'Update ride',
  };

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ride = _activeRide;
    final rideData = ride?.data();
    final status = rideData?['status'] as String?;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await _setOnline(false);
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    _isOnline ? Icons.circle : Icons.circle_outlined,
                    color: _isOnline ? Colors.green : colors.outline,
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOnline ? 'You’re online' : 'You’re offline',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isOnline
                              ? 'Your location is shared every 3 seconds.'
                              : 'Go online to receive ride requests.',
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _isOnline,
                    onChanged: _isChangingStatus || _activeRide != null
                        ? null
                        : _setOnline,
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (ride != null && rideData != null)
            _activeRideCard(rideData, status)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Icon(Icons.route_outlined, size: 44, color: colors.primary),
                    const SizedBox(height: 12),
                    Text(
                      _isOnline
                          ? 'Waiting for ride requests'
                          : 'No active ride',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isOnline
                          ? 'New ride requests will appear here.'
                          : 'Go online when you’re ready to drive.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          if (_latestPosition != null) ...[
            const SizedBox(height: 16),
            Text(
              'Location: ${_latestPosition!.latitude.toStringAsFixed(5)}, ${_latestPosition!.longitude.toStringAsFixed(5)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _activeRideCard(Map<String, dynamic> ride, String? status) {
    final pickup = _address(ride['pickup']);
    final dropoff = _address(ride['dropoff']);
    final statusColor = switch (status) {
      'accepted' => Colors.blue,
      'arriving' => Colors.orange,
      'ongoing' => Colors.green,
      _ => Theme.of(context).colorScheme.primary,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.local_taxi),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Active ride',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  label: Text((status ?? 'unknown').toUpperCase()),
                  side: BorderSide(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _rideAddress('Pickup', pickup),
            const SizedBox(height: 14),
            _rideAddress('Destination', dropoff),
            if (ride['fare'] is num) ...[
              const SizedBox(height: 14),
              Text('Fare: ₦${(ride['fare'] as num).round()}'),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _isChangingStatus ? null : _advanceRide,
              icon: _isChangingStatus
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(_nextAction(status)),
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
