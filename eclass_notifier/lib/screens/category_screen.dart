import 'package:flutter/material.dart';
import '../services/eclass_service.dart';
import '../services/storage_service.dart';
import 'home_screen.dart';

class CategoryScreen extends StatefulWidget {
  final Course course;
  const CategoryScreen({super.key, required this.course});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Category> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final categories = await EclassService.fetchCategories(widget.course.code);
    if (!mounted) return;
    if (categories.isEmpty) {
      setState(() { _loading = false; _error = 'No categories found'; });
    } else {
      setState(() { _loading = false; _categories = categories; });
    }
  }

  void _select(Category category) async {
    await StorageService.saveCategory(category.name, category.urlview);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(
        course: widget.course,
        category: category,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.code),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView.builder(
                  itemCount: _categories.length,
                  itemBuilder: (context, i) {
                    final c = _categories[i];
                    return ListTile(
                      leading: const Icon(Icons.group),
                      title: Text(c.name),
                      subtitle: const Text('Tap to poll this category'),
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