import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/venue_location.dart';
import '../providers/user_location_provider.dart';
import '../providers/venue_favorites_provider.dart';
import '../utils/venue_actions.dart';

class VenueDetailScreen extends ConsumerWidget {
  const VenueDetailScreen({super.key, required this.venue});

  final VenueLocation venue;

  static const _bg = Color(0xFF0D1117);
  static const _card = Color(0xFF161B22);
  static const _border = Color(0xFF30363D);
  static const _accent = Color(0xFFFBBF24);
  static const _primary = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIds = ref.watch(venueFavoritesProvider);
    final favNotifier = ref.read(venueFavoritesProvider.notifier);
    final isFav = favIds.contains(venue.id);

    final userPos = ref.watch(userLocationProvider).position;
    final distanceText = userPos == null
        ? null
        : _formatDistance(
            venue.distanceMetersFrom(userPos.latitude, userPos.longitude),
          );

    final isMain = venue.type == VenueType.mainStadium;
    final typeColor = isMain ? _accent : _primary;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: _bg,
            pinned: true,
            expandedHeight: 200,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              '지사 정보',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                tooltip: isFav ? '즐겨찾기 해제' : '즐겨찾기 추가',
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFav ? _accent : Colors.white,
                ),
                onPressed: () => favNotifier.toggle(venue.id),
              ),
              IconButton(
                tooltip: '공유',
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                onPressed: () {
                  Share.share(
                    '${venue.name}\n${venue.address}\n전화 ${venue.phone}',
                    subject: '${venue.name} 위치 안내',
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHero(typeColor),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _badge(venue.type.label, typeColor),
                      const SizedBox(width: 6),
                      _badge(venue.region, Colors.white70,
                          filled: false),
                      const Spacer(),
                      if (distanceText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.near_me_rounded,
                                size: 12,
                                color: _accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '현위치에서 $distanceText',
                                style: const TextStyle(
                                  color: _accent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    venue.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _infoTile(
                    icon: Icons.location_on_rounded,
                    color: _accent,
                    title: '주소',
                    value: venue.address,
                  ),
                  if (venue.transport.isNotEmpty)
                    _infoTile(
                      icon: Icons.directions_transit_rounded,
                      color: const Color(0xFF3B82F6),
                      title: '교통편',
                      value: venue.transport,
                    ),
                  if (venue.raceDays.isNotEmpty)
                    _infoTile(
                      icon: Icons.event_available_rounded,
                      color: _primary,
                      title: '경주 요일',
                      value: venue.raceDays,
                    ),
                  _infoTile(
                    icon: Icons.phone_rounded,
                    color: const Color(0xFFA78BFA),
                    title: '전화',
                    value: venue.phone,
                    onTap: () => VenueActions.call(context, venue.phone),
                    trailing: const Icon(
                      Icons.call_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '길찾기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          VenueActions.openMapPicker(context, venue),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: const Color(0xFF1A1A1A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.directions_rounded, size: 20),
                      label: const Text(
                        '지도 앱으로 길찾기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              VenueActions.call(context, venue.phone),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.phone_rounded,
                            size: 18,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            '전화하기',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => favNotifier.toggle(venue.id),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(
                              color: isFav
                                  ? _accent
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: Icon(
                            isFav
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 18,
                            color: isFav ? _accent : Colors.white70,
                          ),
                          label: Text(
                            isFav ? '즐겨찾기 해제' : '즐겨찾기',
                            style: TextStyle(
                              color: isFav ? _accent : Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
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

  Widget _buildHero(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.35),
            const Color(0xFF0D47A1).withValues(alpha: 0.45),
            _bg,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          venue.type == VenueType.mainStadium
              ? Icons.stadium_rounded
              : Icons.storefront_rounded,
          size: 80,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, {bool filled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    final km = meters / 1000;
    if (km < 100) return '${km.toStringAsFixed(1)}km';
    return '${km.toStringAsFixed(0)}km';
  }
}
