import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/models/service_request_result.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth_service.dart';
import 'eclass_service.dart';
import 'storage_service.dart';

// --------------------------------------------------
// Notification setup
// --------------------------------------------------
final _notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  await _notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
}

Future<void> showNotification(String title, String body) async {
  const details = AndroidNotificationDetails(
    'eclass_changes',
    'eClass Group Changes',
    channelDescription: 'Notifications for group changes',
    importance: Importance.high,
    priority: Priority.high,
  );
  await _notifications.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: details),
  );
}

// --------------------------------------------------
// Foreground task setup
// --------------------------------------------------
void initForegroundTask({int intervalMinutes = 10}) {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'eclass_poller',
      channelName: 'eClass Poller',
      channelDescription: 'Polling eClass for group changes',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(intervalMinutes * 60 * 1000),
      autoRunOnBoot: false,
    ),
  );
}

Future<bool> startPoller() async {
  // Request permissions
  final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
  if (notifPerm != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  if (await FlutterForegroundTask.isRunningService) {
    final result = await FlutterForegroundTask.restartService();
    return result is ServiceRequestSuccess;
  }

  final result = await FlutterForegroundTask.startService(
    serviceId: 1,
    notificationTitle: 'eClass Poller',
    notificationText: 'Watching for group changes...',
    callback: startPollCallback,
  );
  if (result is ServiceRequestFailure) {
    print('[poller] ERROR: ${result.error}');
  }
  return result is ServiceRequestSuccess;
}

Future<void> stopPoller() async {
  await FlutterForegroundTask.stopService();
}

// --------------------------------------------------
// Task handler
// --------------------------------------------------
@pragma('vm:entry-point')
void startPollCallback() {
  FlutterForegroundTask.setTaskHandler(PollTaskHandler());
}

class PollTaskHandler extends TaskHandler {
  List<GroupSlot> _previousSlots = [];
  bool _isPolling = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await AuthService.loadSession();
    await _loadPreviousSlots();
  }

  Future<void> _loadPreviousSlots() async {
      _previousSlots = await StorageService.getPreviousSlots();
    }

  Future<void> _savePreviousSlots() async {
    await StorageService.savePreviousSlots(_previousSlots);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_isPolling) return;
    _isPolling = true;
    _doPoll().whenComplete(() => _isPolling = false);
  }

  Future<void> _doPoll() async {
    try {
      final creds    = await StorageService.getCredentials();
      final username = creds['username'];
      final password = creds['password'];
      if (username == null || password == null) return;

      final selection = await StorageService.getCategory();
      final course    = await StorageService.getCourse();
      final urlview   = selection['urlview'];
      final code      = course['code'];
      if (urlview == null || code == null) return;

      final loggedIn = await AuthService.ensureLoggedIn(username, password);
      if (!loggedIn) return;

      final slots = await EclassService.fetchSlots(code, urlview);

      if (_previousSlots.isEmpty) {
        _previousSlots = slots;
        await _savePreviousSlots();
        return;
      }

      final changes = EclassService.diffSlots(_previousSlots, slots);
      if (changes.isNotEmpty) {
        await showNotification('eClass Group Change', changes.join('\n'));
        FlutterForegroundTask.updateService(
          notificationText: 'Last change: ${changes.first}',
        );
      }

      _previousSlots = slots;
      await _savePreviousSlots();
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationDismissed() {}
}