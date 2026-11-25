import 'dart:typed_data';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'models/hub_item.dart';
import 'services/notification_service.dart';
import 'services/storage_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const MGToolsApp());
}

class MGToolsApp extends StatelessWidget {
  const MGToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MGtools — Закладки • Заметки • Напоминания',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F17),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
          surface: const Color(0xFF151C28),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF151C28),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF263147), width: 1),
          ),
        ),
      ),
      home: const HubHomeScreen(),
    );
  }
}

class HubHomeScreen extends StatefulWidget {
  const HubHomeScreen({super.key});

  @override
  State<HubHomeScreen> createState() => _HubHomeScreenState();
}

class _HubHomeScreenState extends State<HubHomeScreen> {
  static const String _noFolderFilter = '__NO_FOLDER__';

  final StorageSyncService _storage = StorageSyncService();
  final TextEditingController _searchCtrl = TextEditingController();
  final _uuid = const Uuid();

  List<HubItem> _items = [];
  List<HubFolder> _folders = [];
  bool _loading = true;
  int _navIndex = 0;
  String _searchQuery = '';
  String? _selectedTag;
  bool _onlyPinned = false;
  String? _selectedFolderId;
  String? _linkedCloudPath;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _initData();
    NotificationService.instance.onInAppReminderTriggered = (item) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Row(
            children: [
              Icon(Icons.notifications_active, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Expanded(child: Text('Напоминание MGtools')),
            ],
          ),
          content: Text(
            '${item.title}\n\n${item.content.isNotEmpty ? item.content : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _toggleComplete(item, forceValue: true);
              },
              child: const Text('Выполнено'),
            ),
          ],
        ),
      );
    };
    NotificationService.instance.startForegroundWatcher(
      () => _items.where((e) => !e.isDeleted).toList(),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    NotificationService.instance.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final loaded = await _storage.loadItems();
    final folders = await _storage.loadFolders();
    final cloudPath = await _storage.getLinkedCloudFilePath();
    final lastSync = await _storage.getLastSyncTime();
    if (!mounted) return;
    setState(() {
      _items = loaded;
      _folders = folders;
      _linkedCloudPath = cloudPath;
      _lastSyncTime = lastSync;
      _loading = false;
    });
  }

  List<String> get _allTags {
    final set = <String>{};
    for (final item in _items) {
      if (!item.isDeleted) set.addAll(item.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<HubFolder> get _visibleFolders {
    final list = _folders.where((f) => !f.isDeleted).toList();
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  HubFolder? _folderById(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f.id == id && !f.isDeleted) return f;
    }
    return null;
  }

  List<HubItem> get _filteredItems {
    return _items.where((item) {
      if (item.isDeleted) return false;
      if (_navIndex == 1 && item.type != ItemType.bookmark) return false;
      if (_navIndex == 2 && item.type != ItemType.note) return false;
      if (_navIndex == 3 && item.type != ItemType.reminder) return false;
      if (_onlyPinned && !item.isPinned) return false;
      if (_selectedTag != null && !item.tags.contains(_selectedTag)) {
        return false;
      }

      if (_selectedFolderId == _noFolderFilter) {
        if (item.folderId != null && _folderById(item.folderId) != null) {
          return false;
        }
      } else if (_selectedFolderId != null) {
        if (item.folderId != _selectedFolderId) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final folderName = _folderById(item.folderId)?.name.toLowerCase() ?? '';
        final inTitle = item.title.toLowerCase().contains(q);
        final inContent = item.content.toLowerCase().contains(q);
        final inUrl = (item.url ?? '').toLowerCase().contains(q);
        final inTags = item.tags.any((t) => t.toLowerCase().contains(q));
        final inFolder = folderName.contains(q);
        return inTitle || inContent || inUrl || inTags || inFolder;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  Future<void> _upsertItem(HubItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    setState(() {
      if (idx >= 0) {
        _items[idx] = item;
      } else {
        _items.insert(0, item);
      }
    });
    await _storage.saveAll(_items, _folders);
    await NotificationService.instance.scheduleReminder(item);
    final syncTime = await _storage.getLastSyncTime();
    if (mounted) setState(() => _lastSyncTime = syncTime);
  }

  Future<void> _saveFoldersState() async {
    await _storage.saveAll(_items, _folders);
    final syncTime = await _storage.getLastSyncTime();
    if (mounted) setState(() => _lastSyncTime = syncTime);
  }

  Future<void> _toggleComplete(HubItem item, {bool? forceValue}) async {
    final updated = item.copyWith(
      isCompleted: forceValue ?? !item.isCompleted,
      updatedAt: DateTime.now(),
    );
    await _upsertItem(updated);
  }

  Future<void> _togglePin(HubItem item) async {
    final updated = item.copyWith(
      isPinned: !item.isPinned,
      updatedAt: DateTime.now(),
    );
    await _upsertItem(updated);
  }

  Future<void> _deleteItem(HubItem item) async {
    final updated = item.copyWith(isDeleted: true, updatedAt: DateTime.now());
    await NotificationService.instance.cancelReminder(item.id);
    await _upsertItem(updated);
  }

  Future<void> _openUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) return;
    var formatted = rawUrl.trim();
    if (!formatted.startsWith('http://') && !formatted.startsWith('https://')) {
      formatted = 'https://$formatted';
    }
    final uri = Uri.tryParse(formatted);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFF3B82F6);
    }
  }

  Uint8List? _decodeImageData(String data) {
    try {
      final base64Part =
          data.contains(',') ? data.substring(data.indexOf(',') + 1) : data;
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final items = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.build_circle, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MGtools — S25 Plus & ПК',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _lastSyncTime != null
                        ? 'Синхр.: ${DateFormat('dd.MM HH:mm').format(_lastSyncTime!)}'
                        : 'Закладки • Заметки • Напоминания • Папки',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Только закрепленные',
            icon: Icon(
              _onlyPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: _onlyPinned ? const Color(0xFFF59E0B) : Colors.white70,
            ),
            onPressed: () => setState(() => _onlyPinned = !_onlyPinned),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: _showSyncCenterSheet,
              icon: const Icon(Icons.cloud_sync_rounded, size: 18),
              label: const Text('Синхр.'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                if (isWide)
                  NavigationRail(
                    backgroundColor: const Color(0xFF0B0F17),
                    selectedIndex: _navIndex,
                    onDestinationSelected: (idx) => setState(() {
                      _navIndex = idx;
                      _selectedFolderId = null;
                    }),
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: FloatingActionButton.extended(
                        onPressed: () => _openItemEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Создать'),
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard),
                        label: Text('Все'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.bookmark_border),
                        selectedIcon: Icon(Icons.bookmark),
                        label: Text('Закладки'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.sticky_note_2_outlined),
                        selectedIcon: Icon(Icons.sticky_note_2),
                        label: Text('Заметки'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.alarm_outlined),
                        selectedIcon: Icon(Icons.alarm),
                        label: Text('Напоминания'),
                      ),
                    ],
                  ),
                if (isWide)
                  const VerticalDivider(width: 1, color: Color(0xFF1F2937)),
                Expanded(
                  child: Column(
                    children: [
                      _buildSearchAndTagsBar(),
                      if (_navIndex == 2) _buildFoldersBar(),
                      Expanded(
                        child: items.isEmpty
                            ? _buildEmptyState()
                            : GridView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 110),
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: isWide ? 430 : 640,
                                  mainAxisExtent: 310,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                ),
                                itemCount: items.length,
                                itemBuilder: (ctx, i) =>
                                    _buildItemCard(items[i]),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              backgroundColor: const Color(0xFF111827),
              selectedIndex: _navIndex,
              onDestinationSelected: (idx) => setState(() {
                _navIndex = idx;
                _selectedFolderId = null;
              }),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: 'Все'),
                NavigationDestination(
                    icon: Icon(Icons.bookmark_border),
                    selectedIcon: Icon(Icons.bookmark),
                    label: 'Закладки'),
                NavigationDestination(
                    icon: Icon(Icons.sticky_note_2_outlined),
                    selectedIcon: Icon(Icons.sticky_note_2),
                    label: 'Заметки'),
                NavigationDestination(
                    icon: Icon(Icons.alarm_outlined),
                    selectedIcon: Icon(Icons.alarm),
                    label: 'Напоминания'),
              ],
            ),
      floatingActionButton: isWide
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openItemEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
    );
  }

  Widget _buildSearchAndTagsBar() {
    final tags = _allTags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            decoration: InputDecoration(
              hintText: 'Поиск по заголовку, ссылкам, тексту, папкам или #тегам...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF151C28),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF263147)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF263147)),
              ),
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Все теги'),
                    selected: _selectedTag == null,
                    onSelected: (_) => setState(() => _selectedTag = null),
                  ),
                  const SizedBox(width: 8),
                  ...tags.map(
                    (tag) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('#$tag'),
                        selected: _selectedTag == tag,
                        onSelected: (sel) =>
                            setState(() => _selectedTag = sel ? tag : null),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFoldersBar() {
    final folders = _visibleFolders;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_copy_outlined,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text('Папки / группы заметок',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.white70)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openFolderEditor(),
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('Новая папка'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Все'),
                    selected: _selectedFolderId == null,
                    onSelected: (_) => setState(() => _selectedFolderId = null),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Без папки'),
                    selected: _selectedFolderId == _noFolderFilter,
                    onSelected: (_) =>
                        setState(() => _selectedFolderId = _noFolderFilter),
                  ),
                ),
                ...folders.map((f) {
                  final color = _parseColor(f.colorHex);
                  final selected = _selectedFolderId == f.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      avatar: Icon(
                        f.isPinned ? Icons.push_pin : Icons.folder,
                        size: 16,
                        color: color,
                      ),
                      label: Text(f.name),
                      selected: selected,
                      selectedColor: color.withOpacity(0.25),
                      side: BorderSide(color: color.withOpacity(0.6)),
                      onPressed: () => setState(
                          () => _selectedFolderId = selected ? null : f.id),
                      onDeleted: () => _openFolderEditor(existing: f),
                      deleteIcon: const Icon(Icons.edit, size: 16),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 12),
          const Text(
            'Нет записей по выбранному фильтру',
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _openItemEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Создать запись'),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(HubItem item) {
    final accent = _parseColor(item.colorHex);
    final folder = _folderById(item.folderId);
    final isOverdue = item.reminderAt != null &&
        !item.isCompleted &&
        item.reminderAt!.isBefore(DateTime.now());

    IconData typeIcon;
    String typeLabel;
    switch (item.type) {
      case ItemType.bookmark:
        typeIcon = Icons.bookmark_rounded;
        typeLabel = 'Закладка';
        break;
      case ItemType.note:
        typeIcon = Icons.sticky_note_2_rounded;
        typeLabel = 'Заметка';
        break;
      case ItemType.reminder:
        typeIcon = Icons.alarm_rounded;
        typeLabel = 'Напоминание';
        break;
    }

    final borderColor = item.isCompleted
        ? const Color(0xFF10B981)
        : const Color(0xFF263147);
    final bgColor = item.isCompleted
        ? const Color(0xFF10B981).withOpacity(0.08)
        : const Color(0xFF151C28);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor, width: item.isCompleted ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: () => _openItemEditor(existing: item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(typeIcon, size: 14, color: accent),
                        const SizedBox(width: 6),
                        Text(typeLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accent)),
                      ],
                    ),
                  ),
                  if (folder != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _parseColor(folder.colorHex).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              folder.isPinned ? Icons.push_pin : Icons.folder,
                              size: 12,
                              color: _parseColor(folder.colorHex),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                folder.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _parseColor(folder.colorHex),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Закрепить',
                    icon: Icon(
                      item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 18,
                      color: item.isPinned
                          ? const Color(0xFFF59E0B)
                          : Colors.white38,
                    ),
                    onPressed: () => _togglePin(item),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Сохранить в файл',
                    icon: const Icon(Icons.save_alt, size: 18, color: Colors.white38),
                    onPressed: () => _exportSingleItem(item),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.white38),
                    onPressed: () => _deleteItem(item),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (item.isCompleted)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '✓ ВЫПОЛНЕНО',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF34D399),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  decoration:
                      item.isCompleted ? TextDecoration.lineThrough : null,
                  color: item.isCompleted ? Colors.white54 : Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              if (item.url != null && item.url!.isNotEmpty)
                InkWell(
                  onTap: () => _openUrl(item.url),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.open_in_new,
                            size: 13, color: Color(0xFF60A5FA)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.url!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF60A5FA),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (item.images.isNotEmpty)
                SizedBox(
                  height: 54,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: item.images.length > 4 ? 4 : item.images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) {
                      final bytes = _decodeImageData(item.images[i]);
                      if (bytes == null) return const SizedBox.shrink();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes,
                            width: 54, height: 54, fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  item.content.isNotEmpty
                      ? item.content
                      : (item.checklist.isNotEmpty
                          ? 'Чек-лист: ${item.checklist.where((c) => c.isDone).length}/${item.checklist.length}'
                          : (item.images.isNotEmpty
                              ? 'Изображений: ${item.images.length}'
                              : 'Без описания')),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: item.isCompleted ? Colors.white38 : Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (item.reminderAt != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isOverdue
                            ? const Color(0xFFEF4444).withOpacity(0.2)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_active_outlined,
                              size: 12,
                              color: isOverdue
                                  ? const Color(0xFFF87171)
                                  : Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd.MM HH:mm').format(item.reminderAt!),
                            style: TextStyle(
                                fontSize: 11,
                                color: isOverdue
                                    ? const Color(0xFFF87171)
                                    : Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: item.tags
                            .map((t) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text('#$t',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF93C5FD))),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _toggleComplete(item),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: item.isCompleted
                        ? const Color(0xFF10B981).withOpacity(0.18)
                        : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: item.isCompleted
                          ? const Color(0xFF10B981)
                          : const Color(0xFF334155),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.isCompleted
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: item.isCompleted
                            ? const Color(0xFF10B981)
                            : Colors.white54,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.isCompleted
                              ? 'Выполнено (нажмите, чтобы снять)'
                              : 'Отметить как выполненное',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: item.isCompleted
                                ? const Color(0xFF34D399)
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportSingleItem(HubItem item) async {
    final folder = _folderById(item.folderId);
    final path = await _storage.exportSingleItem(item, folder: folder);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заметка сохранена в файл')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранение отменено')),
      );
    }
  }

  Future<void> _openFolderEditor({HubFolder? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String colorHex = existing?.colorHex ?? '#3B82F6';
    bool isPinned = existing?.isPinned ?? false;
    const palette = [
      '#3B82F6',
      '#10B981',
      '#F59E0B',
      '#EF4444',
      '#8B5CF6',
      '#EC4899',
      '#14B8A6',
      '#F97316'
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151C28),
          title: Text(existing == null
              ? 'Новая папка / группа'
              : 'Редактировать папку'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Название папки (например: Работа)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Закрепить папку'),
                  value: isPinned,
                  onChanged: (v) => setD(() => isPinned = v),
                ),
                const SizedBox(height: 8),
                const Text('Цвет папки:', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: palette.map((hex) {
                    final selected = colorHex == hex;
                    return GestureDetector(
                      onTap: () => setD(() => colorHex = hex),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _parseColor(hex),
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final updated = existing.copyWith(
                    isDeleted: true,
                    updatedAt: DateTime.now(),
                  );
                  setState(() {
                    final i = _folders.indexWhere((f) => f.id == existing.id);
                    if (i >= 0) _folders[i] = updated;
                    if (_selectedFolderId == existing.id) {
                      _selectedFolderId = null;
                    }
                  });
                  await _saveFoldersState();
                },
                child: const Text('Удалить',
                    style: TextStyle(color: Color(0xFFEF4444))),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final now = DateTime.now();
                final folder = HubFolder(
                  id: existing?.id ?? _uuid.v4(),
                  name: name,
                  colorHex: colorHex,
                  isPinned: isPinned,
                  createdAt: existing?.createdAt ?? now,
                  updatedAt: now,
                  isDeleted: false,
                );
                setState(() {
                  final i = _folders.indexWhere((f) => f.id == folder.id);
                  if (i >= 0) {
                    _folders[i] = folder;
                  } else {
                    _folders.add(folder);
                  }
                });
                Navigator.pop(ctx);
                await _saveFoldersState();
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showSyncCenterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151C28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_sync_rounded,
                      color: Color(0xFF3B82F6), size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Синхронизация MGtools — S25 Plus ↔ ПК',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Используйте общий файл mgtools_sync.json в папке Google Drive / OneDrive / Яндекс.Диск или передавайте через Quick Share. Умное слияние объединяет записи и папки без потерь.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (_linkedCloudPath != null && _linkedCloudPath!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_special,
                          color: Color(0xFF10B981), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Привязанный файл:\n$_linkedCloudPath',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_linkedCloudPath != null && _linkedCloudPath!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final report = await _storage
                            .syncWithLinkedCloudFile(_items, _folders);
                        await _initData();
                        if (report != null && mounted) {
                          _showSyncReportSnack(report);
                        }
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('Синхронизировать с привязанным файлом'),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _storage.exportToFileOrShare(_items, _folders);
                        await _initData();
                      },
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Экспорт JSON'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final report =
                            await _storage.pickAndMergeFile(_items, _folders);
                        await _initData();
                        if (report != null && mounted) {
                          _showSyncReportSnack(report);
                        }
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Импорт и слияние'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _storage.exportToFileOrShare(_items, _folders,
                        useShareSheet: true);
                    await _initData();
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Отправить через Quick Share / Облако'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final imported = await _storage.pickAndImportSingleItem(
                        _items, _folders);
                    await _initData();
                    if (imported != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('Загружена запись: ${imported.title}')),
                      );
                    }
                  },
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Загрузить одну заметку из файла'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showSyncReportSnack(SyncReport report) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Синхронизация: +${report.added} записей, обновлено ${report.updated}, пропущено ${report.skipped}; папок +${report.foldersAdded}/${report.foldersUpdated} обн.',
        ),
      ),
    );
  }

  Future<void> _openItemEditor({HubItem? existing}) async {
    ItemType type = existing?.type ??
        (_navIndex == 1
            ? ItemType.bookmark
            : _navIndex == 2
                ? ItemType.note
                : _navIndex == 3
                    ? ItemType.reminder
                    : ItemType.bookmark);

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    final tagsCtrl =
        TextEditingController(text: existing?.tags.join(', ') ?? '');
    DateTime? reminderAt = existing?.reminderAt;
    PriorityLevel priority = existing?.priority ?? PriorityLevel.medium;
    String colorHex = existing?.colorHex ?? '#3B82F6';
    bool isPinned = existing?.isPinned ?? false;
    String? folderId = existing?.folderId;
    List<String> images = List<String>.from(existing?.images ?? const []);

    const palette = [
      '#3B82F6',
      '#10B981',
      '#F59E0B',
      '#EF4444',
      '#8B5CF6',
      '#EC4899',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151C28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final folderOptions = _visibleFolders;
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            existing == null
                                ? 'Новая запись MGtools'
                                : 'Редактировать запись',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрепить',
                          onPressed: () =>
                              setModalState(() => isPinned = !isPinned),
                          icon: Icon(
                            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            color: isPinned
                                ? const Color(0xFFF59E0B)
                                : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ItemType>(
                      segments: const [
                        ButtonSegment(
                            value: ItemType.bookmark,
                            icon: Icon(Icons.bookmark_border),
                            label: Text('Закладка')),
                        ButtonSegment(
                            value: ItemType.note,
                            icon: Icon(Icons.sticky_note_2_outlined),
                            label: Text('Заметка')),
                        ButtonSegment(
                            value: ItemType.reminder,
                            icon: Icon(Icons.alarm),
                            label: Text('Напоминание')),
                      ],
                      selected: {type},
                      onSelectionChanged: (s) =>
                          setModalState(() => type = s.first),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Заголовок *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (type == ItemType.bookmark) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'URL ссылка (https://...)',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Описание / Заметка (поддержка S Pen)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tagsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Теги через запятую (работа, важное, чтение)',
                        prefixIcon: Icon(Icons.tag),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: folderOptions.any((f) => f.id == folderId)
                          ? folderId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Папка / группа (для заметок и др.)',
                        prefixIcon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Без папки'),
                        ),
                        ...folderOptions.map((f) => DropdownMenuItem<String?>(
                              value: f.id,
                              child: Row(
                                children: [
                                  Icon(
                                    f.isPinned ? Icons.push_pin : Icons.folder,
                                    size: 16,
                                    color: _parseColor(f.colorHex),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(f.name),
                                ],
                              ),
                            )),
                      ],
                      onChanged: (v) => setModalState(() => folderId = v),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          await _openFolderEditor();
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 18),
                        label: const Text('Создать/изменить папки'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Изображения:',
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              allowMultiple: true,
                              withData: true,
                            );
                            if (result == null) return;
                            final newImgs = <String>[];
                            for (final f in result.files) {
                              if (f.bytes == null) continue;
                              final ext = (f.extension ?? 'png').toLowerCase();
                              final mime = ext == 'jpg' ? 'jpeg' : ext;
                              newImgs.add(
                                  'data:image/$mime;base64,${base64Encode(f.bytes!)}');
                            }
                            if (newImgs.isNotEmpty) {
                              setModalState(
                                  () => images = [...images, ...newImgs]);
                            }
                          },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Добавить'),
                        ),
                      ],
                    ),
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 84,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (c, i) {
                            final bytes = _decodeImageData(images[i]);
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: bytes != null
                                      ? Image.memory(bytes,
                                          width: 84,
                                          height: 84,
                                          fit: BoxFit.cover)
                                      : Container(
                                          width: 84,
                                          height: 84,
                                          color: Colors.white10,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => setModalState(() =>
                                        images = List.of(images)..removeAt(i)),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: const Icon(Icons.close,
                                          size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final now = DateTime.now();
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: reminderAt ?? now,
                                firstDate:
                                    now.subtract(const Duration(days: 1)),
                                lastDate: now.add(const Duration(days: 3650)),
                              );
                              if (date == null) return;
                              final time = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.fromDateTime(
                                  reminderAt ??
                                      now.add(const Duration(hours: 1)),
                                ),
                              );
                              if (time == null) return;
                              setModalState(() {
                                reminderAt = DateTime(date.year, date.month,
                                    date.day, time.hour, time.minute);
                              });
                            },
                            icon: const Icon(Icons.notifications_active_outlined),
                            label: Text(
                              reminderAt == null
                                  ? 'Задать напоминание (телефон + Windows)'
                                  : DateFormat('dd.MM.yyyy HH:mm')
                                      .format(reminderAt!),
                            ),
                          ),
                        ),
                        if (reminderAt != null)
                          IconButton(
                            onPressed: () =>
                                setModalState(() => reminderAt = null),
                            icon: const Icon(Icons.clear),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Цвет:',
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(width: 12),
                        ...palette.map(
                          (hex) => GestureDetector(
                            onTap: () => setModalState(() => colorHex = hex),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: _parseColor(hex),
                                shape: BoxShape.circle,
                                border: colorHex == hex
                                    ? Border.all(color: Colors.white, width: 2.5)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (existing != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final folder = _folderById(folderId);
                                  await _storage.exportSingleItem(
                                    existing.copyWith(
                                      title: titleCtrl.text.trim().isEmpty
                                          ? existing.title
                                          : titleCtrl.text.trim(),
                                      content: contentCtrl.text.trim(),
                                      url: urlCtrl.text.trim().isEmpty
                                          ? null
                                          : urlCtrl.text.trim(),
                                      tags: tagsCtrl.text
                                          .split(',')
                                          .map((e) => e.trim().replaceAll('#', ''))
                                          .where((e) => e.isNotEmpty)
                                          .toList(),
                                      folderId: folderId,
                                      clearFolderId: folderId == null,
                                      images: images,
                                      reminderAt: reminderAt,
                                      clearReminderAt: reminderAt == null,
                                      isPinned: isPinned,
                                      colorHex: colorHex,
                                      updatedAt: DateTime.now(),
                                    ),
                                    folder: folder,
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Заметка сохранена в отдельный файл')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.save_alt),
                                label: const Text('Сохранить в файл'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) return;

                          final tags = tagsCtrl.text
                              .split(',')
                              .map((e) => e.trim().replaceAll('#', ''))
                              .where((e) => e.isNotEmpty)
                              .toList();

                          final now = DateTime.now();
                          final saved = HubItem(
                            id: existing?.id ?? _uuid.v4(),
                            type: type,
                            title: title,
                            content: contentCtrl.text.trim(),
                            url: urlCtrl.text.trim().isEmpty
                                ? null
                                : urlCtrl.text.trim(),
                            tags: tags,
                            reminderAt: reminderAt,
                            isCompleted: existing?.isCompleted ?? false,
                            isPinned: isPinned,
                            priority: priority,
                            colorHex: colorHex,
                            checklist: existing?.checklist ?? const [],
                            images: images,
                            folderId: folderId,
                            createdAt: existing?.createdAt ?? now,
                            updatedAt: now,
                          );

                          Navigator.pop(ctx);
                          await _upsertItem(saved);
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Сохранить'),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
