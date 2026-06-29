import 'package:flutter/material.dart';
import '../services/poller_service.dart';
import '../services/eclass_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import 'category_screen.dart';
import 'login_screen.dart';

class CourseScreen extends StatefulWidget {
  const CourseScreen({super.key});

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  List<Course> _courses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final courses = await EclassService.fetchCourses();
    if (!mounted) return;
    if (courses.isEmpty) {
      setState(() { _loading = false; _error = 'No courses found or session expired'; });
    } else {
      setState(() { _loading = false; _courses = courses; });
    }
  }

  void _select(Course course) async {
    await StorageService.saveCourse(course.code, course.name);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CategoryScreen(course: course)),
    );
  }

  Future<void> _checkSession() async {
    final valid = await AuthService.isSessionValid();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(valid ? 'Session is valid' : 'Session expired')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Course'),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: 'Check session',
            onPressed: _checkSession,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView.builder(
                  itemCount: _courses.length,
                  itemBuilder: (context, i) {
                    final c = _courses[i];
                    return ListTile(
                      leading: const Icon(Icons.book),
                      title: Text(c.name),
                      subtitle: Text(c.code),
                      onTap: () => _select(c),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}