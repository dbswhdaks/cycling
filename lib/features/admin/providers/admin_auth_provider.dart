import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/admin_constants.dart';

/// 관리자 로그인 상태 관리 — true 이면 모든 구독 잠금이 자동 해제된다.
class AdminAuthNotifier extends StateNotifier<bool> {
  AdminAuthNotifier() : super(false) {
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(AdminConstants.storageKey) ?? false;
      if (saved) state = true;
    } catch (_) {
      // 저장소 접근 실패 시 비로그인으로 유지
    }
  }

  /// 비밀번호가 일치하면 true 저장 및 반환. 그렇지 않으면 false.
  Future<bool> login(String password) async {
    if (password.trim() != AdminConstants.adminPassword) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AdminConstants.storageKey, true);
    } catch (_) {
      // 저장소 실패해도 메모리 상태는 true 로 유지
    }
    state = true;
    return true;
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AdminConstants.storageKey, false);
    } catch (_) {}
    state = false;
  }
}

final adminAuthProvider = StateNotifierProvider<AdminAuthNotifier, bool>(
  (ref) => AdminAuthNotifier(),
);
