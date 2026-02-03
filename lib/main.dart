import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'l10n/app_localizations.dart';
import 'providers/library_provider.dart';
import 'services/onboarding_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize FFI for Windows
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final bool setupComplete = await OnboardingService.isSetupComplete();

  runApp(MyApp(initialRoute: setupComplete ? '/' : '/onboarding'));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LibraryProvider(),
      child: Selector<LibraryProvider, Locale>(
        selector: (_, provider) => provider.locale,
        builder: (context, locale, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Library Manager',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
              textTheme: GoogleFonts.outfitTextTheme(),
            ),
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
      ),
    );
  }
}
