import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'auth_service.dart';

const _eclassUrl = 'https://eclass.upatras.gr';

class Course {
  final String code;
  final String name;
  const Course({required this.code, required this.name});
}

class Category {
  final String name;
  final String urlview;
  const Category({required this.name, required this.urlview});
}

class GroupSlot {
  final String name;
  final String current;
  final String maximum;
  const GroupSlot({required this.name, required this.current, required this.maximum});

  @override
  bool operator ==(Object other) =>
      other is GroupSlot &&
      name == other.name &&
      current == other.current &&
      maximum == other.maximum;

  @override
  int get hashCode => Object.hash(name, current, maximum);

  @override
  String toString() => '$name ($current/$maximum)';
}

class EclassService {
  // --------------------------------------------------
  // Fetch enrolled courses
  // --------------------------------------------------
  static Future<List<Course>> fetchCourses() async {
    final html = await AuthService.getPage('$_eclassUrl/main/portfolio.php');
    if (html == null) return [];

    final soup    = BeautifulSoup(html);
    final courses = <Course>[];

    for (final row in soup.findAll('tr', attrs: {'class': 'row-course'})) {
      final link = row.find('a', attrs: {'class': 'TextBold'});
      if (link == null) continue;
      final name = link.text.trim();
      final href = link.attributes['href'] ?? '';
      final match = RegExp(r'/courses/([^/]+)/').firstMatch(href);
      if (match == null) continue;
      final code = match.group(1)!;
      courses.add(Course(code: code, name: name));
    }

    return courses;
  }

  // --------------------------------------------------
  // Fetch group categories for a course
  // --------------------------------------------------
  static Future<List<Category>> fetchCategories(String courseCode) async {
    final url  = '$_eclassUrl/modules/group/index.php?course=$courseCode&show=list';
    final html = await AuthService.getPage(url);
    if (html == null) return [];

    final soup       = BeautifulSoup(html);
    final catTable   = soup.find('table', attrs: {'class': 'category-links'});
    if (catTable == null) return [];

    final categories = <Category>[];

    for (final th in catTable.findAll('th', attrs: {'class': 'category-link'})) {
      final link = th.find('a');
      if (link == null) continue;
      final name = link.text.trim();
      final href = link.attributes['href'] ?? '';
      final match = RegExp(r'urlview=([01]+)').firstMatch(href);
      if (match == null) continue;
      categories.add(Category(name: name, urlview: match.group(1)!));
    }

    return categories;
  }

  // --------------------------------------------------
  // Fetch group slots for a category
  // --------------------------------------------------
  static Future<List<GroupSlot>> fetchSlots(
      String courseCode, String urlview) async {
    final url  =
        '$_eclassUrl/modules/group/index.php?course=$courseCode&show=list&urlview=$urlview';
    final html = await AuthService.getPage(url);
    if (html == null) return [];

    final soup     = BeautifulSoup(html);
    final catTable = soup.find('table', attrs: {'class': 'category-links'});
    if (catTable == null) return [];

    final slots = <GroupSlot>[];

    for (final row in catTable.findAll('tr')) {
      if (row.find('th', attrs: {'class': 'category-link'}) != null) continue;
      final tds = row.findAll('td');
      if (tds.length < 4) continue;
      final name    = tds[0].text.trim();
      final current = tds[2].text.trim();
      final maximum = tds[3].text.trim();
      if (name.isEmpty) continue;
      slots.add(GroupSlot(name: name, current: current, maximum: maximum));
    }

    return slots;
  }

  // --------------------------------------------------
  // Diff two slot lists — returns human readable changes
  // --------------------------------------------------
  static List<String> diffSlots(
      List<GroupSlot> oldSlots, List<GroupSlot> newSlots) {
    final changes = <String>[];
    final oldMap  = {for (final s in oldSlots) s.name: s};
    final newMap  = {for (final s in newSlots) s.name: s};

    for (final s in newSlots) {
      if (!oldMap.containsKey(s.name)) {
        changes.add('New group: ${s.name} (${s.current}/${s.maximum})');
      } else if (oldMap[s.name] != s) {
        changes.add(
            '${s.name}: ${oldMap[s.name]!.current}/${oldMap[s.name]!.maximum} -> ${s.current}/${s.maximum}');
      }
    }

    for (final s in oldSlots) {
      if (!newMap.containsKey(s.name)) {
        changes.add('Removed: ${s.name}');
      }
    }

    return changes;
  }
}