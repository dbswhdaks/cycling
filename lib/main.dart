import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/api_constants.dart';
import 'core/constants/supabase_constants.dart';
import 'core/theme/app_theme.dart';
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConstants.loadServiceKey();
  await Supabase.initialize(
    url: SupabaseConstants.url,
    anonKey: SupabaseConstants.anonKey,
  );
  runApp(
    const ProviderScope(
      child: CyclingApp(),
    ),
  );
}

class CyclingApp extends StatelessWidget {
  const CyclingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '경륜 Plus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
