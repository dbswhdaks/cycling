import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/screens/home_screen.dart';
import '../features/race/screens/race_detail_screen.dart';
import '../features/race/screens/race_result_screen.dart';
import '../features/rider/screens/rider_detail_screen.dart';
import '../features/settings/screens/api_settings_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/race/:venue/:date/:raceNo',
      builder: (context, state) {
        final venue = state.pathParameters['venue'] ?? '1';
        final date = state.pathParameters['date'] ?? '';
        final raceNo = state.pathParameters['raceNo'] ?? '1';
        return RaceDetailScreen(
          venueCode: int.tryParse(venue) ?? 1,
          date: date,
          raceNo: int.tryParse(raceNo) ?? 1,
        );
      },
    ),
    GoRoute(
      path: '/result/:venue/:date/:raceNo',
      builder: (context, state) {
        final venue = state.pathParameters['venue'] ?? '1';
        final date = state.pathParameters['date'] ?? '';
        final raceNo = state.pathParameters['raceNo'] ?? '1';
        return RaceResultScreen(
          venueCode: int.tryParse(venue) ?? 1,
          date: date,
          raceNo: int.tryParse(raceNo) ?? 1,
        );
      },
    ),
    GoRoute(
      path: '/rider/:riderId',
      builder: (context, state) {
        final riderId = state.pathParameters['riderId'] ?? '';
        final venue = state.uri.queryParameters['venue'];
        return RiderDetailScreen(
          riderId: riderId,
          venueCode: venue != null ? int.tryParse(venue) : null,
        );
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const ApiSettingsScreen(),
    ),
  ],
);
