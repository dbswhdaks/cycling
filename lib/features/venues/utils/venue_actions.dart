import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/venue_location.dart';

/// 전화 걸기 · 지도 앱 열기 등 지사 관련 외부 인텐트를 처리하는 유틸.
class VenueActions {
  static Future<void> call(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: phone.replaceAll('-', ''));
    try {
      final ok = await launchUrl(uri);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(content: Text('전화 앱을 열 수 없습니다: $phone')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('전화 앱을 열 수 없습니다: $phone')),
      );
    }
  }

  static void openMapPicker(BuildContext context, VenueLocation venue) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _MapPickerSheet(venue: venue),
    );
  }

  static Future<void> _tryLaunch(
    BuildContext context,
    Uri app,
    Uri fallback,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(app, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    try {
      final ok =
          await launchUrl(fallback, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('지도 앱을 열 수 없습니다.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('지도 앱을 열 수 없습니다.')),
      );
    }
  }

  static Future<void> openNaverMap(
    BuildContext context,
    VenueLocation v,
  ) async {
    final app = Uri.parse(
      'nmap://route/car?dlat=${v.latitude}&dlng=${v.longitude}'
      '&dname=${Uri.encodeComponent(v.name)}&appname=com.example.cycling',
    );
    final web = Uri.parse(
      'https://map.naver.com/v5/directions/-/-/-/car?'
      'destination=${Uri.encodeComponent(v.address)}',
    );
    await _tryLaunch(context, app, web);
  }

  static Future<void> openKakaoMap(
    BuildContext context,
    VenueLocation v,
  ) async {
    final app = Uri.parse(
      'kakaomap://route?ep=${v.latitude},${v.longitude}&by=CAR',
    );
    final web = Uri.parse(
      'https://map.kakao.com/link/to/${Uri.encodeComponent(v.name)},'
      '${v.latitude},${v.longitude}',
    );
    await _tryLaunch(context, app, web);
  }

  static Future<void> openTMap(BuildContext context, VenueLocation v) async {
    final app = Uri.parse(
      'tmap://route?goalname=${Uri.encodeComponent(v.name)}'
      '&goalx=${v.longitude}&goaly=${v.latitude}',
    );
    final web = Uri.parse('https://tmap.life');
    await _tryLaunch(context, app, web);
  }

  static Future<void> openGoogleMap(
    BuildContext context,
    VenueLocation v,
  ) async {
    final web = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${v.latitude},${v.longitude}'
      '&travelmode=driving',
    );
    await _tryLaunch(context, web, web);
  }
}

class _MapPickerSheet extends StatelessWidget {
  const _MapPickerSheet({required this.venue});

  final VenueLocation venue;

  static const _bg = Color(0xFF0D1117);
  static const _border = Color(0xFF30363D);
  static const _accent = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(
                  venue.type == VenueType.mainStadium
                      ? Icons.stadium_rounded
                      : Icons.storefront_rounded,
                  color: _accent,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    venue.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              venue.address,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            _row(
              context,
              label: '주소 복사',
              icon: Icons.copy_rounded,
              color: Colors.white70,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                await Clipboard.setData(ClipboardData(text: venue.address));
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('주소가 복사되었습니다.')),
                );
              },
            ),
            _row(
              context,
              label: '네이버 지도로 길찾기',
              icon: Icons.map_rounded,
              color: const Color(0xFF03C75A),
              onTap: () {
                Navigator.pop(context);
                VenueActions.openNaverMap(context, venue);
              },
            ),
            _row(
              context,
              label: '카카오맵으로 길찾기',
              icon: Icons.map_rounded,
              color: const Color(0xFFFEE500),
              onTap: () {
                Navigator.pop(context);
                VenueActions.openKakaoMap(context, venue);
              },
            ),
            _row(
              context,
              label: '티맵으로 길찾기',
              icon: Icons.directions_car_rounded,
              color: const Color(0xFFE60013),
              onTap: () {
                Navigator.pop(context);
                VenueActions.openTMap(context, venue);
              },
            ),
            _row(
              context,
              label: '구글 지도로 길찾기',
              icon: Icons.public_rounded,
              color: const Color(0xFF4285F4),
              onTap: () {
                Navigator.pop(context);
                VenueActions.openGoogleMap(context, venue);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
