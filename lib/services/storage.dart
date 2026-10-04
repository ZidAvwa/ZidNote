import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

late SharedPreferences _prefs;

Future<void> initStorage() async => _prefs = await SharedPreferences.getInstance();

const trashDays = 30;
int _now() => DateTime.now().millisecondsSinceEpoch;

// ---- Notes (active + trash share one list; trash = deletedAt != 0) ----

List<Note> _readAll() => (_prefs.getStringList('notes') ?? [])
    .map((s) => Note.fromJson(jsonDecode(s)))
    .toList();

void _writeAll(List<Note> all) =>
    _prefs.setStringList('notes', all.map((x) => jsonEncode(x.toJson())).toList());

List<Note> loadNotes() => _readAll().where((n) => n.deletedAt == 0).toList();
List<Note> loadTrash() => _readAll().where((n) => n.deletedAt != 0).toList();

/// Inserts or replaces notes by id, in one write.
void saveMany(List<Note> ns) {
  final all = _readAll();
  for (final n in ns) {
    final i = all.indexWhere((x) => x.id == n.id);
    i >= 0 ? all[i] = n : all.insert(0, n);
  }
  _writeAll(all);
}

void saveNote(Note n) => saveMany([n]);

void trashNote(String id) {
  final all = _readAll();
  for (final n in all) {
    if (n.id == id) {
      n.deletedAt = _now();
      n.pinned = false;
    }
  }
  _writeAll(all);
}

void restoreNote(String id) {
  final all = _readAll();
  for (final n in all) {
    if (n.id == id) n.deletedAt = 0;
  }
  _writeAll(all);
}

void purgeNote(String id) => _writeAll(_readAll()..removeWhere((x) => x.id == id));

void emptyTrash() => _writeAll(_readAll().where((n) => n.deletedAt == 0).toList());

/// Permanently removes notes that have been in the trash longer than [trashDays].
void purgeOldTrash() {
  final cut = _now() - trashDays * 86400000;
  _writeAll(_readAll().where((n) => n.deletedAt == 0 || n.deletedAt > cut).toList());
}

// ---- Groups (folders) ----

List<String> loadGroups() => _prefs.getStringList('groups') ?? [];
void saveGroups(List<String> g) => _prefs.setStringList('groups', g);

// ---- Color palette presets (persist after the app is closed) ----

Map<String, List<int>> loadPresets() {
  final raw = _prefs.getString('presets');
  if (raw != null) {
    return (jsonDecode(raw) as Map)
        .map((k, v) => MapEntry(k as String, (v as List).cast<int>()));
  }
  final old = _prefs.getStringList('palette'); // from version 1.0
  return {
    'Basic': [
      0xFF000000, 0xFFF44336, 0xFF2196F3, 0xFF4CAF50,
      0xFFFF9800, 0xFF9C27B0, 0xFF795548, 0xFF9E9E9E,
    ],
    'Pastel': [
      0xFFFFADAD, 0xFFFFD6A5, 0xFFFDFFB6, 0xFFCAFFBF,
      0xFF9BF6FF, 0xFFA0C4FF, 0xFFBDB2FF, 0xFFFFC6FF,
    ],
    if (old != null) 'My colors': old.map(int.parse).toList(),
  };
}

void savePresets(Map<String, List<int>> p) => _prefs.setString('presets', jsonEncode(p));

String loadActivePreset() => _prefs.getString('activePreset') ?? 'Basic';
void saveActivePreset(String n) => _prefs.setString('activePreset', n);

// ---- Sort ----

String loadSort() => _prefs.getString('sort') ?? 'modified';
void saveSort(String s) => _prefs.setString('sort', s);

// ---- Group colors (the color-coded group button) ----

const groupPalette = [
  0xFFE53935, 0xFFFB8C00, 0xFFFDD835, 0xFF43A047,
  0xFF00ACC1, 0xFF1E88E5, 0xFF8E24AA, 0xFFD81B60,
];

Map<String, int> loadGroupColors() {
  final raw = _prefs.getString('groupColors');
  final m = raw == null
      ? <String, int>{}
      : (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as int));
  final gs = loadGroups();
  var changed = false;
  for (int i = 0; i < gs.length; i++) {
    if (!m.containsKey(gs[i])) {
      m[gs[i]] = groupPalette[i % groupPalette.length];
      changed = true;
    }
  }
  if (changed) saveGroupColors(m);
  return m;
}

void saveGroupColors(Map<String, int> m) => _prefs.setString('groupColors', jsonEncode(m));

// ---- Misc ----

bool noteExists(String id) => _readAll().any((n) => n.id == id);

/// 'system', 'light' or 'dark'
String loadTheme() => _prefs.getString('theme') ?? 'system';
void saveTheme(String t) => _prefs.setString('theme', t);
