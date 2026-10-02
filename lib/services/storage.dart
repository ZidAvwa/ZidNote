import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

late SharedPreferences _prefs;

Future<void> initStorage() async => _prefs = await SharedPreferences.getInstance();

// ---- Notes ----

List<Note> loadNotes() => (_prefs.getStringList('notes') ?? [])
    .map((s) => Note.fromJson(jsonDecode(s)))
    .toList();

void _writeNotes(List<Note> all) =>
    _prefs.setStringList('notes', all.map((x) => jsonEncode(x.toJson())).toList());

void saveNote(Note n) {
  final all = loadNotes();
  final i = all.indexWhere((x) => x.id == n.id);
  i >= 0 ? all[i] = n : all.insert(0, n);
  _writeNotes(all);
}

void deleteNote(String id) => _writeNotes(loadNotes()..removeWhere((x) => x.id == id));

// ---- Color palette (persists after the app is closed) ----

List<int> loadPalette() =>
    (_prefs.getStringList('palette') ?? ['4278190080', '4294198070', '4280391411', '4283215696'])
        .map(int.parse)
        .toList();

void savePalette(List<int> p) =>
    _prefs.setStringList('palette', p.map((e) => e.toString()).toList());
