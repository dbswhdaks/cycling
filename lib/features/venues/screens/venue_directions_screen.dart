import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/venue_locations_data.dart';
import '../../../models/venue_location.dart';
import '../providers/user_location_provider.dart';
import '../providers/venue_favorites_provider.dart';
import '../utils/venue_actions.dart';

enum _SortMode { distance, name }

class VenueDirectionsScreen extends ConsumerStatefulWidget {
  const VenueDirectionsScreen({super.key});

  @override
  ConsumerState<VenueDirectionsScreen> createState() =>
      _VenueDirectionsScreenState();
}

class _VenueDirectionsScreenState
    extends ConsumerState<VenueDirectionsScreen> {
  static const _bg = Color(0xFF0D1117);
  static const _card = Color(0xFF161B22);
  static const _border = Color(0xFF30363D);
  static const _accent = Color(0xFFFBBF24);
  static const _primary = Color(0xFF22C55E);

  String _selectedRegion = '전체';
  _SortMode _sortMode = _SortMode.distance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userLocationProvider.notifier).refresh();
    });
  }

  List<VenueLocation> _applyFilters(List<VenueLocation> source) {
    Iterable<VenueLocation> venues = source;

    if (_selectedRegion != '전체') {
      venues = venues.where((v) => v.region == _selectedRegion);
    }
    return venues.toList();
  }

  void _sortVenues(List<VenueLocation> list, {required bool hasPosition}) {
    if (_sortMode == _SortMode.distance && hasPosition) {
      final pos = ref.read(userLocationProvider).position!;
      list.sort((a, b) => a
          .distanceMetersFrom(pos.latitude, pos.longitude)
          .compareTo(b.distanceMetersFrom(pos.latitude, pos.longitude)));
    } else {
      list.sort((a, b) {
        if (a.type != b.type) {
          return a.type == VenueType.mainStadium ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locState = ref.watch(userLocationProvider);
    final favIds = ref.watch(venueFavoritesProvider);
    final userPos = locState.position;

    final filtered = _applyFilters(VenueLocationsData.all);
    _sortVenues(filtered, hasPosition: userPos != null);

    final favorites = filtered.where((v) => favIds.contains(v.id)).toList();
    final nonFavorites =
        filtered.where((v) => !favIds.contains(v.id)).toList();

    final totalCount = VenueLocationsData.all.length;
    final mainCount = VenueLocationsData.all
        .where((v) => v.type == VenueType.mainStadium)
        .length;
    final branchCount = totalCount - mainCount;

    final closest = userPos == null
        ? null
        : (List<VenueLocation>.from(VenueLocationsData.all)
              ..sort((a, b) => a
                  .distanceMetersFrom(userPos.latitude, userPos.longitude)
                  .compareTo(b.distanceMetersFrom(
                      userPos.latitude, userPos.longitude))))
            .first;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _accent,
          backgroundColor: _card,
          onRefresh: () async {
            await ref.read(userLocationProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeader(
                  mainCount: mainCount,
                  branchCount: branchCount,
                  favoritesCount: favIds.length,
                  closest: closest,
                  userPos: userPos,
                ),
              ),
              SliverToBoxAdapter(child: _buildLocationBanner(locState)),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(child: _buildRegionFilter()),
              SliverToBoxAdapter(child: _buildSortRow(filtered.length)),
              const SliverToBoxAdapter(
                child: Divider(color: _border, height: 1),
              ),
              if (favorites.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    icon: Icons.star_rounded,
                    color: _accent,
                    title: '즐겨찾기',
                    count: favorites.length,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.separated(
                    itemCount: favorites.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _venueCard(favorites[i]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    icon: Icons.list_rounded,
                    color: _primary,
                    title: '전체 지사',
                    count: nonFavorites.length,
                  ),
                ),
              ],
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyView(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: favorites.isEmpty
                        ? filtered.length
                        : nonFavorites.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _venueCard(
                      favorites.isEmpty ? filtered[i] : nonFavorites[i],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 상단 헤더 (히어로 + 통계) ───
  Widget _buildHeader({
    required int mainCount,
    required int branchCount,
    required int favoritesCount,
    required VenueLocation? closest,
    required dynamic userPos,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D47A1),
            Color(0xFF1565C0),
            Color(0xFFB45309),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.directions_rounded,
                color: _accent,
                size: 22,
              ),
              const SizedBox(width: 6),
              const Text(
                '경륜장 가는길',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '현위치 새로고침',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: Colors.white,
                ),
                onPressed: () =>
                    ref.read(userLocationProvider.notifier).refresh(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '전국 경륜장·지사 안내',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statTile('본장', '$mainCount', _accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statTile('지사', '$branchCount', Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statTile(
                  '즐겨찾기',
                  '$favoritesCount',
                  const Color(0xFFF87171),
                ),
              ),
            ],
          ),
          if (closest != null && userPos != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _goDetail(closest),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.near_me_rounded,
                      color: _accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '가장 가까운 지사',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${closest.name} · '
                            '${_formatDistance(closest.distanceMetersFrom(userPos.latitude, userPos.longitude))}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 위치 상태 배너 ───
  Widget _buildLocationBanner(UserLocationState state) {
    if (state.status == UserLocationStatus.granted) {
      return const SizedBox.shrink();
    }

    late final IconData icon;
    late final Color color;
    late final String label;
    late final String actionLabel;
    late final VoidCallback onAction;

    switch (state.status) {
      case UserLocationStatus.loading:
        icon = Icons.location_searching_rounded;
        color = _accent;
        label = '현재 위치를 확인하고 있어요…';
        actionLabel = '';
        onAction = () {};
        break;
      case UserLocationStatus.denied:
        icon = Icons.location_off_rounded;
        color = const Color(0xFFF87171);
        label = '위치 권한이 없어 거리순 정렬을 사용할 수 없습니다.';
        actionLabel = '권한 설정';
        onAction = () =>
            ref.read(userLocationProvider.notifier).openAppSettings();
        break;
      case UserLocationStatus.serviceDisabled:
        icon = Icons.gps_off_rounded;
        color = const Color(0xFFF87171);
        label = '위치 서비스가 꺼져 있습니다.';
        actionLabel = '설정 열기';
        onAction = () =>
            ref.read(userLocationProvider.notifier).openLocationSettings();
        break;
      case UserLocationStatus.error:
        icon = Icons.error_outline_rounded;
        color = const Color(0xFFF87171);
        label = '위치를 가져오지 못했습니다.';
        actionLabel = '재시도';
        onAction = () => ref.read(userLocationProvider.notifier).refresh();
        break;
      case UserLocationStatus.initial:
      case UserLocationStatus.granted:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (actionLabel.isNotEmpty) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: color.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRegionFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: VenueLocationsData.regions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final region = VenueLocationsData.regions[i];
            final selected = _selectedRegion == region;
            final regionCount = region == '전체'
                ? VenueLocationsData.all.length
                : VenueLocationsData.all
                    .where((v) => v.region == region)
                    .length;
            return GestureDetector(
              onTap: () => setState(() => _selectedRegion = region),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? _accent : _border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      region,
                      style: TextStyle(
                        color:
                            selected ? const Color(0xFF1A1A1A) : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$regionCount',
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF1A1A1A).withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSortRow(int resultCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Text(
            '총 $resultCount개소',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _sortChip('거리순', _SortMode.distance, Icons.near_me_rounded),
          const SizedBox(width: 6),
          _sortChip('이름순', _SortMode.name, Icons.sort_by_alpha_rounded),
        ],
      ),
    );
  }

  Widget _sortChip(String label, _SortMode mode, IconData icon) {
    final selected = _sortMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _sortMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.18) : _card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? _accent : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: selected ? _accent : Colors.white54),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? _accent : Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required Color color,
    required String title,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 지사 카드 ───
  Widget _venueCard(VenueLocation venue) {
    final userPos = ref.watch(userLocationProvider).position;
    final favIds = ref.watch(venueFavoritesProvider);
    final favNotifier = ref.read(venueFavoritesProvider.notifier);
    final isFav = favIds.contains(venue.id);
    final distanceMeters = userPos == null
        ? null
        : venue.distanceMetersFrom(userPos.latitude, userPos.longitude);
    final isMain = venue.type == VenueType.mainStadium;
    final typeColor = isMain ? _accent : _primary;

    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _goDetail(venue),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: typeColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      isMain
                          ? Icons.stadium_rounded
                          : Icons.storefront_rounded,
                      color: typeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                venue.type.label,
                                style: TextStyle(
                                  color: typeColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                venue.region,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          venue.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        tooltip: isFav ? '즐겨찾기 해제' : '즐겨찾기 추가',
                        icon: Icon(
                          isFav
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 22,
                          color: isFav ? _accent : Colors.white54,
                        ),
                        onPressed: () => favNotifier.toggle(venue.id),
                      ),
                      if (distanceMeters != null)
                        Text(
                          _formatDistance(distanceMeters),
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _iconLine(
                icon: Icons.location_on_outlined,
                text: venue.address,
              ),
              if (venue.transport.isNotEmpty)
                _iconLine(
                  icon: Icons.directions_transit_rounded,
                  text: venue.transport,
                  faded: true,
                ),
              if (venue.raceDays.isNotEmpty)
                _iconLine(
                  icon: Icons.event_available_rounded,
                  text: venue.raceDays,
                  faded: true,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => VenueActions.call(context, venue.phone),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.phone_rounded,
                        size: 15,
                        color: Colors.white70,
                      ),
                      label: Text(
                        venue.phone,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          VenueActions.openMapPicker(context, venue),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: const Color(0xFF1A1A1A),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.directions_rounded, size: 17),
                      label: const Text(
                        '길찾기',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
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
    );
  }

  Widget _iconLine({
    required IconData icon,
    required String text,
    bool faded = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 13,
            color: Colors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: faded ? 0.55 : 0.75),
                fontSize: faded ? 11.5 : 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    final km = meters / 1000;
    if (km < 100) return '${km.toStringAsFixed(1)}km';
    return '${km.toStringAsFixed(0)}km';
  }

  void _goDetail(VenueLocation venue) {
    context.push('/venues/detail', extra: venue);
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          Text(
            '조건에 맞는 지사가 없습니다',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
