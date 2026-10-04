import 'package:flutter/material.dart';
import 'pages/notes_page.dart';
import 'services/app_theme.dart';
import 'services/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStorage();
  purgeOldTrash(); // trash older than 30 days is removed
  initTheme();
  runApp(ValueListenableBuilder<ThemeMode>(
    valueListenable: themeMode,
    builder: (_, mode, __) => MaterialApp(
      title: 'ColorNote',
      themeMode: mode,
      theme: ThemeData(colorSchemeSeed: Colors.amber, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.amber, brightness: Brightness.dark, useMaterial3: true),
      home: const NotesPage(),
    ),
  ));
}
