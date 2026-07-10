import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 지사 즐겨찾기 상태 (id 집합).
/// SharedPreferences에 CSV 문자열로 저장한다.
class VenueFavoritesNotifier extends StateNotifier<Set<String>> {
  VenueFavoritesNotifier() : super(<String>{}) {
    _load();
  }

  static const _prefsKey = 'venue_favorites_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const <String>[];
    state = raw.toSet();
  }

  Future<void> toggle(String id) async {
    final next = Set<String>.from(state);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, next.toList());
  }

  bool isFavorite(String id) => state.contains(id);
}

final venueFavoritesProvider =
    StateNotifierProvider<VenueFavoritesNotifier, Set<String>>(
  (ref) => VenueFavoritesNotifier(),
);
