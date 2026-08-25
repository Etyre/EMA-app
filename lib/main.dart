import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/survey_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState.instance;
  runApp(const EmaApp());
  await app.settingsStore.migrateIfNeeded();
  await app.notifications.init();
  app.notifications.tapped.stream.listen(openSurvey);
  final launchId = await app.notifications.launchPromptId();
  await app.housekeeping();
  // Startup diagnostics (visible in `flutter run` console).
  final s = await app.settingsStore.loadSettings();
  debugPrint('[EMA] sound setting=${s.sound}; ${await app.notifications.diagnostics(s.sound)}');
  if (launchId != null) openSurvey(launchId);
}

void openSurvey(int promptId) {
  final nav = navigatorKey.currentState;
  if (nav == null) {
    // Cold launch: the first frame may not have built the navigator yet.
    WidgetsBinding.instance.addPostFrameCallback((_) => openSurvey(promptId));
    return;
  }
  nav.push(MaterialPageRoute(builder: (_) => SurveyScreen(promptId: promptId)));
}

class EmaApp extends StatefulWidget {
  const EmaApp({super.key});
  @override
  State<EmaApp> createState() => _EmaAppState();
}

class _EmaAppState extends State<EmaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppState.instance.housekeeping();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EMA',
        navigatorKey: navigatorKey,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
        home: const HomeScreen(),
      );
}
