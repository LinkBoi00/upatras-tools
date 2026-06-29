import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:logger/logger.dart';
import 'services/storage_service.dart';
import 'services/auth_service.dart';
import 'services/poller_service.dart';
import 'services/eclass_service.dart';
import 'screens/login_screen.dart';
import 'screens/course_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  final savedInterval = await StorageService.getPollInterval();
  initForegroundTask(intervalMinutes: savedInterval);
  await initNotifications();
  Logger.level = kDebugMode ? Level.debug : Level.off;
  runApp(const EClassNotifierApp());
}

class EClassNotifierApp extends StatelessWidget {
  const EClassNotifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eClass Notifier',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final hasCreds = await StorageService.hasCredentials();
    if (!hasCreds) { _go(const LoginScreen()); return; }

    await AuthService.loadSession();
    final valid = await AuthService.isSessionValid();

    if (!valid) {
      final creds    = await StorageService.getCredentials();
      final username = creds['username']!;
      final password = creds['password']!;
      final ok       = await AuthService.login(username, password);
      if (!ok) { _go(const LoginScreen()); return; }
    }

    final hasSelection = await StorageService.hasSelection();
    if (!hasSelection) { _go(const CourseScreen()); return; }

    final course   = await StorageService.getCourse();
    final category = await StorageService.getCategory();

    _go(HomeScreen(
      course:   Course(code: course['code']!,       name: course['name']!),
      category: Category(name: category['name']!, urlview: category['urlview']!),
    ));
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}