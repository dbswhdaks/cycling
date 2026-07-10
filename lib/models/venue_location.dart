import 'dart:math' as math;

enum VenueType {
  mainStadium,
  branch,
}

extension VenueTypeX on VenueType {
  String get label {
    switch (this) {
      case VenueType.mainStadium:
        return '본장';
      case VenueType.branch:
        return '지사';
    }
  }
}

class VenueLocation {
  const VenueLocation({
    required this.id,
    required this.name,
    required this.type,
    required this.region,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
    this.transport = '',
    this.raceDays = '',
  });

  final String id;
  final String name;
  final VenueType type;
  final String region;
  final String address;
  final double latitude;
  final double longitude;
  final String phone;
  final String transport;
  final String raceDays;

  /// Haversine 공식을 이용한 두 좌표 사이의 거리 (단위: 미터).
  /// geolocator 미사용시에도 정렬 가능하도록 자체 계산 로직 제공.
  double distanceMetersFrom(double lat, double lng) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat - latitude);
    final dLng = _toRadians(lng - longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(latitude)) *
            math.cos(_toRadians(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180.0;
}
