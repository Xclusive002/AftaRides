import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.description});

  final String placeId;
  final String description;
}

class RidePlace {
  const RidePlace({
    required this.address,
    required this.location,
    this.placeId,
  });

  final String address;
  final LatLng location;
  final String? placeId;
}

class RideRoute {
  const RideRoute({required this.points, required this.distanceMeters});

  final List<LatLng> points;
  final int distanceMeters;

  double get distanceKm => distanceMeters / 1000;
}

class MapsService {
  MapsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _apiKey {
    final key = dotenv.env['GOOGLE_MAPS_API_KEY']?.trim() ?? '';
    if (key.isEmpty) {
      throw const MapsServiceException(
        'Add GOOGLE_MAPS_API_KEY to ride_app/.env and enable Maps, Places, and Directions APIs.',
      );
    }
    return key;
  }

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    if (input.trim().length < 2) return const [];

    final response = await _get('/place/autocomplete/json', {
      'input': input.trim(),
      'components': 'country:ng',
      'key': _apiKey,
    });
    _ensureOk(response);
    final predictions = response['predictions'] as List<dynamic>? ?? const [];
    return predictions
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => PlaceSuggestion(
            placeId: item['place_id'] as String,
            description: item['description'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<RidePlace> placeDetails(PlaceSuggestion suggestion) async {
    final response = await _get('/place/details/json', {
      'place_id': suggestion.placeId,
      'fields': 'formatted_address,geometry/location',
      'key': _apiKey,
    });
    _ensureOk(response);
    final result = response['result'] as Map<String, dynamic>;
    final geometry = result['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;
    return RidePlace(
      address: result['formatted_address'] as String? ?? suggestion.description,
      location: LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      ),
      placeId: suggestion.placeId,
    );
  }

  Future<RideRoute> directions({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final response = await _get('/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'key': _apiKey,
    });
    _ensureOk(response);
    final routes = response['routes'] as List<dynamic>? ?? const [];
    if (routes.isEmpty) {
      throw const MapsServiceException('No driving route was found.');
    }

    final route = routes.first as Map<String, dynamic>;
    final overview = route['overview_polyline'] as Map<String, dynamic>;
    final legs = route['legs'] as List<dynamic>;
    final leg = legs.first as Map<String, dynamic>;
    final distance = leg['distance'] as Map<String, dynamic>;

    return RideRoute(
      points: _decodePolyline(overview['points'] as String),
      distanceMeters: (distance['value'] as num).toInt(),
    );
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> queryParameters,
  ) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api$path',
      queryParameters,
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const MapsServiceException('Maps service request failed.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _ensureOk(Map<String, dynamic> response) {
    if (response['status'] == 'OK') return;
    final status = response['status'] as String? ?? 'UNKNOWN_ERROR';
    if (status == 'ZERO_RESULTS') {
      throw const MapsServiceException(
        'No matching location or route was found.',
      );
    }
    throw MapsServiceException(
      response['error_message'] as String? ?? 'Google Maps returned $status.',
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      final latitudeDelta = _decodeComponent(encoded, index);
      latitude += latitudeDelta.value;
      index = latitudeDelta.nextIndex;

      final longitudeDelta = _decodeComponent(encoded, index);
      longitude += longitudeDelta.value;
      index = longitudeDelta.nextIndex;

      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }
    return points;
  }

  ({int value, int nextIndex}) _decodeComponent(String encoded, int index) {
    var result = 0;
    var shift = 0;
    var byte = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final value = result.isOdd ? ~(result >> 1) : result >> 1;
    return (value: value, nextIndex: index);
  }
}

class MapsServiceException implements Exception {
  const MapsServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
