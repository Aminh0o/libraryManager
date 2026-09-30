import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/library_provider.dart';
import 'providers/appearance_controller.dart';
import 'services/feature_flags.dart';
import 'services/app_logger.dart';
import 'services/onboarding_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize FFI for Windows
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Persist diagnostics to a rotating log file so release builds stay
  // diagnosable (REL/logging). Best-effort: a logging failure must never stop
  // the app from starting.
  try {
    final docs = await getApplicationDocumentsDirectory();
    initAppLogging(docsDir: docs);
    appLog.info(
        'app', 'Library Manager starting (release=${kReleaseMode ? "yes" : "no"})');
  } catch (e) {
    debugPrint('logging init skipped: $e');
  }

  final bool setupComplete = await OnboardingService.isSetupComplete();

  // Phase 14/17: per-device appearance + feature flags, resolved once before
  // the first frame so the very first paint already uses the saved theme.
  final appearance = await AppearanceController.load();
  final flags = await FeatureFlags.load();

  runApp(MyApp(
    initialRoute: setupComplete ? '/' : '/onboarding',
    appearance: appearance,
    flags: flags,
  ));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final String initialRoute;
  final AppearanceController appearance;
  final FeatureFlags flags;
  const MyApp({
    super.key,
    required this.initialRoute,
    required this.appearance,
    required this.flags,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        // Phase 14/17: per-device visual identity + operator feature toggles.
        ChangeNotifierProvider.value(value: appearance),
        ChangeNotifierProvider.value(value: flags),
      ],
      child: _AppRoot(initialRoute: initialRoute),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot({required this.initialRoute});
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceController>();
    return Selector<LibraryProvider, Locale>(
      selector: (_, provider) => provider.locale,
      builder: (context, locale, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: appearance.brandName,
          debugShowCheckedModeBanner: false,
          theme: appearance.themeFor(Brightness.light),
          darkTheme: appearance.themeFor(Brightness.dark),
          themeMode: appearance.themeMode,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('fr'),
            Locale('ar'),
          ],
          initialRoute: initialRoute,
          routes: {
            '/': (context) => const HomeScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
          },
        );
      },
    );
  }
}
