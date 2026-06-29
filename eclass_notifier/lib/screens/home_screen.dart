import 'package:flutter/material.dart';
import '../services/eclass_service.dart';
import '../services/storage_service.dart';
import '../services/poller_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'course_screen.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class HomeScreen extends StatefulWidget {
  final Course course;
  final Category category;
  const HomeScreen({super.key, required this.course, required this.category});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<GroupSlot> _slots = [];
  bool _loading = true;
  bool _polling = false;
  String? _error;
  String? _lastUpdated;
  int _intervalMinutes = 10;

  @override
  void initState() {
    super.initState();
    _loadSlots();
    _checkPollerStatus();
    _loadInterval();
  }

  Future<void> _checkPollerStatus() async {
    final running = await isPollerRunning();
    if (mounted) setState(() => _polling = running);
  }

  Future<void> _loadInterval() async {
    final saved = await StorageService.getPollInterval();
    if (mounted) setState(() => _intervalMinutes = saved);
  }

  Future<void> _changeInterval(int minutes) async {
    setState(() => _intervalMinutes = minutes);
    await StorageService.savePollInterval(minutes);
    initForegroundTask(intervalMinutes: minutes);
    if (_polling) {
      await stopPoller();
      await startPoller();
    }
  }

  Future<void> _loadSlots() async {
    setState(() { _loading = true; _error = null; });
    final slots = await EclassService.fetchSlots(
      widget.course.code,
      widget.category.urlview,
    );
    if (!mounted) return;
    if (slots.isEmpty) {
      setState(() { _loading = false; _error = 'No groups found'; });
    } else {
      setState(() {
        _loading     = false;
        _slots       = slots;
        _lastUpdated = TimeOfDay.now().format(context);
      });
    }
  }

  Future<void> _togglePoller() async {
    if (_polling) {
      await stopPoller();
      setState(() => _polling = false);
    } else {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      final ok = await startPoller();
      setState(() => _polling = ok);
    }
  }

  Future<void> _changeSelection() async {
    if (_polling) {
      await stopPoller();
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CourseScreen()),
    );
  }

  Future<void> _logout() async {
    await stopPoller();
    await StorageService.clearAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _testChangeDetection() async {
    // Seed a fake baseline that won't match real data
    final fakeSlots = [
      GroupSlot(name: '__TEST_SLOT__', current: '0', maximum: '99'),
    ];
    await StorageService.savePreviousSlots(fakeSlots);

    // Fetch real current slots
    final realSlots = await EclassService.fetchSlots(
      widget.course.code,
      widget.category.urlview,
    );

    // Run the same diff logic the poller uses
    final changes = EclassService.diffSlots(fakeSlots, realSlots);

    if (changes.isNotEmpty) {
      await showNotification('eClass Group Change (TEST)', changes.join('\n'));
    }

    // Reseed with the real baseline so the next real poll isn't confused
    await StorageService.savePreviousSlots(realSlots);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Test complete: ${changes.length} changes detected, baseline reset')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('eClass Notifier'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Check session',
              onPressed: () async {
                final valid = await AuthService.isSessionValid();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(valid ? 'Session is valid' : 'Session expired')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Change course/category',
              onPressed: _changeSelection,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: _logout,
            ),
          ],
        ),
        body: Column(
          children: [
            // Status card
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _polling ? Colors.green[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _polling ? Colors.green : Colors.grey,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _polling ? Icons.sensors : Icons.sensors_off,
                        color: _polling ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _polling ? 'Polling active' : 'Polling stopped',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _polling ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Course: ${widget.course.code}',
                      style: const TextStyle(fontSize: 12)),
                  Text('Category: ${widget.category.name}',
                      style: const TextStyle(fontSize: 12)),
                  if (_lastUpdated != null)
                    Text('Last manual fetch: $_lastUpdated',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Check every: ', style: TextStyle(fontSize: 12)),
                      DropdownButton<int>(
                        value: _intervalMinutes,
                        isDense: true,
                        items: const [1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120]
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text('$m min'),
                                ))
                            .toList(),
                        onChanged: (m) {
                          if (m != null) _changeInterval(m);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Groups list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red)))
                      : ListView.builder(
                          itemCount: _slots.length,
                          itemBuilder: (context, i) {
                            final slot = _slots[i];
                            final full = slot.current == slot.maximum &&
                                slot.maximum != '-' &&
                                slot.maximum != '0';
                            return ListTile(
                              leading: Icon(
                                Icons.group,
                                color: full ? Colors.red : Colors.green,
                              ),
                              title: Text(slot.name,
                                  style: const TextStyle(fontSize: 13)),
                              trailing: Text(
                                '${slot.current}/${slot.maximum}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: full ? Colors.red : Colors.green,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'test',
              onPressed: _testChangeDetection,
              backgroundColor: Colors.orange,
              child: const Icon(Icons.science),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'refresh',
              onPressed: _loadSlots,
              child: const Icon(Icons.refresh),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.extended(
              heroTag: 'poll',
              onPressed: _togglePoller,
              backgroundColor: _polling ? Colors.red : Colors.green,
              icon: Icon(_polling ? Icons.stop : Icons.play_arrow),
              label: Text(_polling ? 'Stop' : 'Start Polling'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> isPollerRunning() async {
  return await FlutterForegroundTask.isRunningService;
}