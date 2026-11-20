// Pocket Notes - CC105 lab activity
// Packages: flutter pub add shared_preferences sqflite path

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// ============================================================
// 1) CHANGE THIS BLOCK to match the last digit of your class number
//    (Part 1 table). Currently set to: 7 = Books (title, author).
//    Example for 3 = Plants:
//      kTable = 'plants', kField1 = 'plant_name', kField2 = 'watering_notes'
// ============================================================
const String kTable = 'books';
const String kField1 = 'title';
const String kField2 = 'author';
const String kLabel1 = 'Title';
const String kLabel2 = 'Author';
const String kRecordName = 'Book';

// ============================================================
// 2) EXPERIMENT 1 SWITCH
//    false = normal app (theme is read BEFORE runApp, no flash).
//    true  = broken version: runApp first, theme loads later with a
//            2 second delay so you can screenshot the wrong-theme frame.
//    Set it back to false when you are done (step 4 of the experiment).
// ============================================================
const bool kBreakTheme = false;

// ---------------- MODEL ----------------
class Record {
  final int? id; // auto-increment, set by the database
  final String field1;
  final String field2;

  const Record({this.id, required this.field1, required this.field2});

  Map<String, Object?> toMap() => {kField1: field1, kField2: field2};

  factory Record.fromMap(Map<String, Object?> m) => Record(
        id: m['id'] as int,
        field1: m[kField1] as String,
        field2: m[kField2] as String,
      );
}

// ---------------- DATABASE (opened ONCE, reused everywhere) ----------------
class AppDatabase {
  static Future<Database>? _opening;

  // The first call opens the database; every later call gets the same instance.
  static Future<Database> get() => _opening ??= _open();

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'pocket_notes.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE $kTable ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        '$kField1 TEXT NOT NULL, '
        '$kField2 TEXT NOT NULL)',
      ),
    );
  }

  static Future<List<Record>> all() async {
    final db = await get();
    final rows = await db.query(kTable, orderBy: 'id ASC');
    // Console proof for capture #7 (compare with the app's list).
    debugPrint('DB ROWS: $rows');
    return rows.map(Record.fromMap).toList();
  }

  static Future<void> insert(Record r) async {
    final db = await get();
    await db.insert(kTable, r.toMap());
  }

  // where + whereArgs: values are never glued into the SQL string.
  static Future<void> update(Record r) async {
    final db = await get();
    await db.update(
      kTable,
      r.toMap(),
      where: 'id = ?',
      whereArgs: [r.id],
    );
  }

  static Future<void> delete(int id) async {
    final db = await get();
    await db.delete(
      kTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

// ---------------- MAIN ----------------
const String _themeKey = 'isDark';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.get(); // open the one database instance

  if (kBreakTheme) {
    // BROKEN on purpose (Experiment 1): draw first, read theme later.
    runApp(const PocketNotesApp(initialDark: false));
  } else {
    // FIX: read the saved theme BEFORE the first frame is drawn.
    final isDark = await SharedPreferencesAsync().getBool(_themeKey) ?? false;
    runApp(PocketNotesApp(initialDark: isDark));
  }
}

class PocketNotesApp extends StatefulWidget {
  final bool initialDark;
  const PocketNotesApp({super.key, required this.initialDark});

  @override
  State<PocketNotesApp> createState() => _PocketNotesAppState();
}

class _PocketNotesAppState extends State<PocketNotesApp> {
  final _prefs = SharedPreferencesAsync();
  late bool _dark;

  @override
  void initState() {
    super.initState();
    _dark = widget.initialDark;
    if (kBreakTheme) _loadThemeLate();
  }

  // Only used by the broken Experiment 1 version.
  Future<void> _loadThemeLate() async {
    await Future.delayed(const Duration(seconds: 2));
    final saved = await _prefs.getBool(_themeKey) ?? false;
    setState(() => _dark = saved);
  }

  Future<void> _setDark(bool value) async {
    setState(() => _dark = value);
    await _prefs.setBool(_themeKey, value); // saved with SharedPreferencesAsync
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: HomePage(isDark: _dark, onThemeChanged: _setDark),
    );
  }
}

// ---------------- HOME PAGE ----------------
class HomePage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  const HomePage({super.key, required this.isDark, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Record> _records = [];

  // Experiment 2: this lives only in a plain State variable (NOT saved).
  String _search = '';

  @override
  void initState() {
    super.initState();
    _reload(); // list is loaded from sqflite when the app launches
  }

  Future<void> _reload() async {
    final rows = await AppDatabase.all();
    if (mounted) setState(() => _records = rows);
  }

  Future<void> _openDialog({Record? existing}) async {
    final result = await showDialog<Record>(
      context: context,
      builder: (_) => _RecordDialog(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await AppDatabase.insert(result);
    } else {
      await AppDatabase.update(result);
    }
    await _reload();
  }

  Future<void> _delete(Record r) async {
    await AppDatabase.delete(r.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _records.where((r) {
      final q = _search.toLowerCase();
      return r.field1.toLowerCase().contains(q) ||
          r.field2.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Notes'),
        actions: [
          Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
          Switch(value: widget.isDark, onChanged: widget.onThemeChanged),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search (not saved)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No records yet. Tap + to add one.'))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final r = shown[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${r.id}')),
                        title: Text(r.field1),
                        subtitle: Text(r.field2),
                        onTap: () => _openDialog(existing: r), // edit
                        trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: const Icon(Icons.edit),
      onPressed: () => _openDialog(existing: r),
    ),
    IconButton(
      icon: const Icon(Icons.delete),
      onPressed: () => _delete(r),
    ),
  ],
),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------- ADD / EDIT DIALOG ----------------
class _RecordDialog extends StatefulWidget {
  final Record? existing;
  const _RecordDialog({this.existing});

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  late final TextEditingController _c1 =
      TextEditingController(text: widget.existing?.field1 ?? '');
  late final TextEditingController _c2 =
      TextEditingController(text: widget.existing?.field2 ?? '');

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit $kRecordName' : 'Add $kRecordName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _c1,
            decoration: InputDecoration(labelText: kLabel1),
          ),
          TextField(
            controller: _c2,
            decoration: InputDecoration(labelText: kLabel2),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_c1.text.trim().isEmpty || _c2.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              Record(
                id: widget.existing?.id,
                field1: _c1.text.trim(),
                field2: _c2.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}