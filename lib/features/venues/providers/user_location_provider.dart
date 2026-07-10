import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

enum UserLocationStatus {
  initial,
  loading,
  granted,
  denied,
  serviceDisabled,
  error,
}

class UserLocationState {
  const UserLocationState({
    required this.status,
    this.position,
    this.errorMessage,
  });

  final UserLocationStatus status;
  final Position? position;
  final String? errorMessage;

  UserLocationState copyWith({
    UserLocationStatus? status,
    Position? position,
    String? errorMessage,
  }) {
    return UserLocationState(
      status: status ?? this.status,
      position: position ?? this.position,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  static const initial = UserLocationState(status: UserLocationStatus.initial);
}

/// 위치 상태 관리자.
///
/// - lastKnownPosition을 즉시 사용해 첫 화면 렌더링을 지연시키지 않는다.
/// - 이후 getCurrentPosition으로 정확한 위치를 백그라운드에서 갱신한다.
/// - 권한 거부/서비스 꺼짐/타임아웃 등을 명확히 구분해 UI에 노출한다.
class UserLocationNotifier extends StateNotifier<UserLocationState> {
  UserLocationNotifier() : super(UserLocationState.initial);

  Future<void> refresh() async {
    state = state.copyWith(status: UserLocationStatus.loading);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = const UserLocationState(
          status: UserLocationStatus.serviceDisabled,
          errorMessage: '기기 위치 서비스가 꺼져 있습니다.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = const UserLocationState(
          status: UserLocationStatus.denied,
          errorMessage: '위치 권한이 필요합니다.',
        );
        return;
      }

      // 1) 마지막으로 알려진 위치를 즉시 노출해 체감 속도를 높인다.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        state = UserLocationState(
          status: UserLocationStatus.granted,
          position: last,
        );
      }

      // 2) 정확한 최신 좌표를 백그라운드에서 획득한다.
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      state = UserLocationState(
        status: UserLocationStatus.granted,
        position: fresh,
      );
    } catch (e) {
      if (state.position != null) {
        return;
      }
      state = UserLocationState(
        status: UserLocationStatus.error,
        errorMessage: '위치를 가져오지 못했습니다.',
      );
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}

final userLocationProvider =
    StateNotifierProvider<UserLocationNotifier, UserLocationState>(
  (ref) => UserLocationNotifier(),
);
