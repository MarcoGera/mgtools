import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hub_item.dart';
import 'notification_service.dart';

class StorageSyncService {
  static const String _storageKey = 'mgtools_items_v1';
  static const String _foldersKey = 'mgtools_folders_v1';
  static const String _cloudFilePathKey = 'mgtools_cloud_file_path_v1';
  static const String _lastSyncTimeKey = 'mgtools_last_sync_v1';
  static const String defaultSyncFileName = 'mgtools_sync.json';

  static const String _legacyItemsKey = 's25u_hub_items_v1';
  static const String _legacyCloudKey = 's25u_hub_cloud_file_path_v1';
  static const String _legacySyncKey = 's25u_hub_last_sync_v1';

  Future<List<HubItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      raw = prefs.getString(_legacyItemsKey);
      if (raw != null && raw.isNotEmpty) {
        await prefs.setString(_storageKey, raw);
      }
    }
    if (raw == null || raw.isEmpty) {
      final seed = _createInitialSampleData();
      await saveItems(seed, syncToCloudFile: false);
      return seed;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => HubItem.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading items: $e');
    }
    return [];
  }

  Future<List<HubFolder>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_foldersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => HubFolder.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading folders: $e');
    }
    return [];
  }

  Future<void> saveItems(List<HubItem> items,
      {bool syncToCloudFile = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, jsonEncode(items.map((e) => e.toMap()).toList()));

    if (syncToCloudFile) {
      final cloudPath = await getLinkedCloudFilePath();
      if (cloudPath != null && cloudPath.isNotEmpty && !kIsWeb) {
        final folders = await loadFolders();
        await _writeSyncEnvelopeToFile(File(cloudPath), items, folders);
        await prefs.setString(
            _lastSyncTimeKey, DateTime.now().toIso8601String());
      }
    }
  }

  Future<void> saveAll(List<HubItem> items, List<HubFolder> folders,
      {bool syncToCloudFile = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, jsonEncode(items.map((e) => e.toMap()).toList()));
    await prefs.setString(
        _foldersKey, jsonEncode(folders.map((e) => e.toMap()).toList()));

    if (syncToCloudFile) {
      final cloudPath = await getLinkedCloudFilePath();
      if (cloudPath != null && cloudPath.isNotEmpty && !kIsWeb) {
        await _writeSyncEnvelopeToFile(File(cloudPath), items, folders);
        await prefs.setString(
            _lastSyncTimeKey, DateTime.now().toIso8601String());
      }
    }
  }

  Future<String?> getLinkedCloudFilePath() async {
    final prefs = await SharedPreferences.getInstance();
    String? path = prefs.getString(_cloudFilePathKey);
    if (path == null || path.isEmpty) {
      path = prefs.getString(_legacyCloudKey);
      if (path != null && path.isNotEmpty) {
        await prefs.setString(_cloudFilePathKey, path);
      }
    }
    return path;
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    String? str = prefs.getString(_lastSyncTimeKey);
    str ??= prefs.getString(_legacySyncKey);
    return str != null ? DateTime.tryParse(str) : null;
  }

  Future<void> setLinkedCloudFilePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_cloudFilePathKey);
    } else {
      await prefs.setString(_cloudFilePathKey, path);
    }
  }

  String buildExportJson(List<HubItem> items, [List<HubFolder>? folders]) {
    final envelope = {
      'app': 'MGtools',
      'schemaVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'device': kIsWeb ? 'Web' : Platform.operatingSystem,
      'items': items.map((e) => e.toMap()).toList(),
      'folders': (folders ?? const <HubFolder>[])
          .map((e) => e.toMap())
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  Future<void> _writeSyncEnvelopeToFile(
      File file, List<HubItem> items, List<HubFolder> folders) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(buildExportJson(items, folders), flush: true);
    } catch (e) {
      debugPrint('Failed writing cloud sync file: $e');
    }
  }

  Future<SyncReport> mergeFromJsonString(String jsonStr,
      List<HubItem> currentItems, List<HubFolder> currentFolders) async {
    final decoded = jsonDecode(jsonStr);
    List<dynamic> rawItems;
    List<dynamic> rawFolders = const [];

    if (decoded is Map && decoded['items'] is List) {
      rawItems = decoded['items'] as List<dynamic>;
      if (decoded['folders'] is List) {
        rawFolders = decoded['folders'] as List<dynamic>;
      }
    } else if (decoded is List) {
      rawItems = decoded;
    } else {
      throw const FormatException(
          'Некорректный формат файла синхронизации JSON');
    }

    final incomingItems = rawItems
        .whereType<Map>()
        .map((e) => HubItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final incomingFolders = rawFolders
        .whereType<Map>()
        .map((e) => HubFolder.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    final Map<String, HubItem> byId = {
      for (final item in currentItems) item.id: item,
    };
    final Map<String, HubFolder> foldersById = {
      for (final f in currentFolders) f.id: f,
    };

    int added = 0, updated = 0, skipped = 0;
    int fAdded = 0, fUpdated = 0;

    for (final inc in incomingFolders) {
      final ex = foldersById[inc.id];
      if (ex == null) {
        foldersById[inc.id] = inc;
        fAdded++;
      } else if (inc.updatedAt.isAfter(ex.updatedAt)) {
        foldersById[inc.id] = inc;
        fUpdated++;
      }
    }

    for (final inc in incomingItems) {
      final existing = byId[inc.id];
      if (existing == null) {
        byId[inc.id] = inc;
        added++;
        await NotificationService.instance.scheduleReminder(inc);
      } else if (inc.updatedAt.isAfter(existing.updatedAt)) {
        byId[inc.id] = inc;
        updated++;
        await NotificationService.instance.scheduleReminder(inc);
      } else {
        skipped++;
      }
    }

    final mergedItems = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final mergedFolders = foldersById.values.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    await saveAll(mergedItems, mergedFolders, syncToCloudFile: true);
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_lastSyncTimeKey, now.toIso8601String());

    return SyncReport(
      added: added,
      updated: updated,
      skipped: skipped,
      foldersAdded: fAdded,
      foldersUpdated: fUpdated,
      syncedAt: now,
    );
  }

  Future<String?> exportToFileOrShare(
      List<HubItem> items, List<HubFolder> folders,
      {bool useShareSheet = false}) async {
    final jsonContent = buildExportJson(items, folders);

    if (!kIsWeb &&
        !useShareSheet &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить файл синхронизации MGtools',
        fileName: defaultSyncFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (outputPath == null) return null;
      final file = File(outputPath);
      await file.writeAsString(jsonContent, flush: true);
      await setLinkedCloudFilePath(outputPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncTimeKey, DateTime.now().toIso8601String());
      return outputPath;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$defaultSyncFileName');
    await file.writeAsString(jsonContent, flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'MGtools Sync (${DateTime.now().toLocal()})',
      text: 'Файл синхронизации закладок, заметок и напоминаний MGtools',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncTimeKey, DateTime.now().toIso8601String());
    return file.path;
  }

  Future<SyncReport?> pickAndMergeFile(
      List<HubItem> currentItems, List<HubFolder> currentFolders) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите файл синхронизации mgtools_sync.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;

    String content;
    if (picked.bytes != null) {
      content = utf8.decode(picked.bytes!);
    } else if (picked.path != null) {
      content = await File(picked.path!).readAsString();
    } else {
      return null;
    }

    if (picked.path != null && !kIsWeb) {
      await setLinkedCloudFilePath(picked.path!);
    }

    return mergeFromJsonString(content, currentItems, currentFolders);
  }

  Future<SyncReport?> syncWithLinkedCloudFile(
      List<HubItem> currentItems, List<HubFolder> currentFolders) async {
    if (kIsWeb) return null;
    final path = await getLinkedCloudFilePath();
    if (path == null || path.isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) {
      await _writeSyncEnvelopeToFile(file, currentItems, currentFolders);
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncTimeKey, now.toIso8601String());
      return SyncReport(
        added: 0,
        updated: currentItems.length,
        skipped: 0,
        foldersAdded: 0,
        foldersUpdated: currentFolders.length,
        syncedAt: now,
      );
    }

    final content = await file.readAsString();
    return mergeFromJsonString(content, currentItems, currentFolders);
  }

  // --- Экспорт/импорт отдельной заметки ---

  String buildSingleItemJson(HubItem item, {HubFolder? folder}) {
    final envelope = {
      'app': 'MGtools',
      'schemaVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'singleItem': true,
      'item': item.toMap(),
      if (folder != null) 'folder': folder.toMap(),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  Future<String?> exportSingleItem(HubItem item, {HubFolder? folder}) async {
    final safeTitle = item.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim();
    final name = 'mgtools_${safeTitle.isEmpty ? item.id : safeTitle}.json';
    final jsonContent = buildSingleItemJson(item, folder: folder);

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить заметку (Сохранить как...)',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (outputPath == null) return null;
      await File(outputPath).writeAsString(jsonContent, flush: true);
      return outputPath;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(jsonContent, flush: true);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'MGtools — ${item.title}',
      text: 'Отдельный файл записи MGtools',
    );
    return file.path;
  }

  Future<HubItem?> pickAndImportSingleItem(
      List<HubItem> currentItems, List<HubFolder> currentFolders) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Загрузить запись из отдельного файла MGtools',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;

    String content;
    if (picked.bytes != null) {
      content = utf8.decode(picked.bytes!);
    } else if (picked.path != null) {
      content = await File(picked.path!).readAsString();
    } else {
      return null;
    }

    final decoded = jsonDecode(content);
    HubItem? item;
    HubFolder? folder;

    if (decoded is Map && decoded['item'] is Map) {
      item = HubItem.fromMap(Map<String, dynamic>.from(decoded['item'] as Map));
      if (decoded['folder'] is Map) {
        folder = HubFolder.fromMap(
            Map<String, dynamic>.from(decoded['folder'] as Map));
      }
    } else if (decoded is Map &&
        decoded['id'] != null &&
        decoded['type'] != null) {
      item = HubItem.fromMap(Map<String, dynamic>.from(decoded));
    } else {
      throw const FormatException('Файл не содержит отдельную запись MGtools');
    }

    final byId = {for (final i in currentItems) i.id: i};
    final existing = byId[item.id];
    if (existing == null || item.updatedAt.isAfter(existing.updatedAt)) {
      byId[item.id] = item;
      await NotificationService.instance.scheduleReminder(item);
    }

    final fById = {for (final f in currentFolders) f.id: f};
    if (folder != null) {
      final exF = fById[folder.id];
      if (exF == null || folder.updatedAt.isAfter(exF.updatedAt)) {
        fById[folder.id] = folder;
      }
    }

    final mergedItems = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final mergedFolders = fById.values.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    await saveAll(mergedItems, mergedFolders, syncToCloudFile: true);
    return item;
  }

  List<HubItem> _createInitialSampleData() {
    final now = DateTime.now();
    return [
      HubItem(
        id: 'sample-bookmark-1',
        type: ItemType.bookmark,
        title: 'Документация Flutter & Multiplatform',
        content: 'Официальное руководство по сборке под Android и Windows ПК.',
        url: 'https://docs.flutter.dev',
        tags: ['разработка', 'flutter', 'важное'],
        isPinned: true,
        priority: PriorityLevel.high,
        colorHex: '#3B82F6',
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
      ),
      HubItem(
        id: 'sample-reminder-1',
        type: ItemType.reminder,
        title: 'Синхронизировать MGtools с ПК',
        content: 'Экспортировать JSON на Google Drive / OneDrive.',
        tags: ['синхронизация', 'пк', 's25plus'],
        reminderAt: now.add(const Duration(hours: 2)),
        isPinned: true,
        priority: PriorityLevel.high,
        colorHex: '#EF4444',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      HubItem(
        id: 'sample-note-1',
        type: ItemType.note,
        title: 'Идеи и быстрые заметки (S Pen)',
        content: 'Поддержка папок, изображений, тегов и отдельного сохранения заметок.',
        tags: ['s-pen', 'заметки', 'идеи'],
        priority: PriorityLevel.medium,
        colorHex: '#10B981',
        checklist: [
          ChecklistItem(id: 'c1', text: 'Закладки с тегами', isDone: true),
          ChecklistItem(id: 'c2', text: 'Напоминания на телефоне и ПК', isDone: true),
          ChecklistItem(id: 'c3', text: 'Папки и изображения', isDone: true),
        ],
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
    ];
  }
}
