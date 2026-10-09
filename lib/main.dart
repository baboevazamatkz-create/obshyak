import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_gate.dart';
import 'firebase_options.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  // Connecting happens inside the app, not before it starts: if it fails
  // on a bad connection or a browser that blocks it, the app can say so
  // and offer a retry instead of sitting on the loading screen for good.
  runApp(const ExpenseTrackerApp());
}

/// Starts Firebase and signs this phone in. Gives up after [timeout] so a
/// stalled network turns into a message rather than an endless wait.
Future<void> connectToBudget({
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(timeout);
  }
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously().timeout(timeout);
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Общак',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Dark only: the flat's app has no light room to switch to.
      theme: buildAppTheme(Brightness.dark),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        // The app bar carries this style on the screens that have one;
        // this covers the ones that do not -- the gate screen and the
        // first-run budget screen -- so the status bar never keeps the
        // previous room's icons after a theme switch.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemOverlayStyleFor(Theme.of(context).brightness),
          child: MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: mediaQuery.textScaler
                  .clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25),
            ),
            child: child!,
          ),
        );
      },
      home: const AppGate(connect: connectToBudget),
    );
  }
}
