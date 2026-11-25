import 'dart:convert';

enum ItemType { bookmark, note, reminder }

enum PriorityLevel { low, medium, high }

class ChecklistItem {
  final String id;
  final String text;
  final bool isDone;

  ChecklistItem({
    required this.id,
    required this.text,
    this.isDone = false,
  });

  ChecklistItem copyWith({String? id, String? text, bool? isDone}) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'isDone': isDone,
      };

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      isDone: map['isDone'] == true,
    );
  }
}

class HubFolder {
  final String id;
  final String name;
  final String colorHex;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  HubFolder({
    required this.id,
    required this.name,
    this.colorHex = '#3B82F6',
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  HubFolder copyWith({
    String? id,
    String? name,
    String? colorHex,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return HubFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorHex': colorHex,
        'isPinned': isPinned,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory HubFolder.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return HubFolder(
      id: map['id']?.toString() ?? now.microsecondsSinceEpoch.toString(),
      name: map['name']?.toString() ?? 'Папка',
      colorHex: map['colorHex']?.toString() ?? '#3B82F6',
      isPinned: map['isPinned'] == true,
      createdAt: map['createdAt'] != null
          ? (DateTime.tryParse(map['createdAt'].toString()) ?? now)
          : now,
      updatedAt: map['updatedAt'] != null
          ? (DateTime.tryParse(map['updatedAt'].toString()) ?? now)
          : now,
      isDeleted: map['isDeleted'] == true,
    );
  }
}

class HubItem {
  final String id;
  final ItemType type;
  final String title;
  final String content;
  final String? url;
  final List<String> tags;
  final DateTime? reminderAt;
  final bool isCompleted;
  final bool isPinned;
  final PriorityLevel priority;
  final String colorHex;
  final List<ChecklistItem> checklist;
  final List<String> images;
  final String? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  HubItem({
    required this.id,
    required this.type,
    required this.title,
    this.content = '',
    this.url,
    this.tags = const [],
    this.reminderAt,
    this.isCompleted = false,
    this.isPinned = false,
    this.priority = PriorityLevel.medium,
    this.colorHex = '#3B82F6',
    this.checklist = const [],
    this.images = const [],
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  HubItem copyWith({
    String? id,
    ItemType? type,
    String? title,
    String? content,
    String? url,
    bool clearUrl = false,
    List<String>? tags,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    bool? isCompleted,
    bool? isPinned,
    PriorityLevel? priority,
    String? colorHex,
    List<ChecklistItem>? checklist,
    List<String>? images,
    String? folderId,
    bool clearFolderId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return HubItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      url: clearUrl ? null : (url ?? this.url),
      tags: tags ?? this.tags,
      reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
      isCompleted: isCompleted ?? this.isCompleted,
      isPinned: isPinned ?? this.isPinned,
      priority: priority ?? this.priority,
      colorHex: colorHex ?? this.colorHex,
      checklist: checklist ?? this.checklist,
      images: images ?? this.images,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'content': content,
      'url': url,
      'tags': tags,
      'reminderAt': reminderAt?.toIso8601String(),
      'isCompleted': isCompleted,
      'isPinned': isPinned,
      'priority': priority.name,
      'colorHex': colorHex,
      'checklist': checklist.map((e) => e.toMap()).toList(),
      'images': images,
      'folderId': folderId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  factory HubItem.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type']?.toString() ?? 'note';
    final itemType = ItemType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ItemType.note,
    );

    final priorityStr = map['priority']?.toString() ?? 'medium';
    final priorityLevel = PriorityLevel.values.firstWhere(
      (e) => e.name == priorityStr,
      orElse: () => PriorityLevel.medium,
    );

    final rawTags = map['tags'];
    final parsedTags = rawTags is List
        ? rawTags.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    final rawChecklist = map['checklist'];
    final parsedChecklist = rawChecklist is List
        ? rawChecklist
            .whereType<Map>()
            .map((e) => ChecklistItem.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <ChecklistItem>[];

    final rawImages = map['images'];
    final parsedImages = rawImages is List
        ? rawImages.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    final now = DateTime.now();

    return HubItem(
      id: map['id']?.toString() ?? now.microsecondsSinceEpoch.toString(),
      type: itemType,
      title: map['title']?.toString() ?? 'Без названия',
      content: map['content']?.toString() ?? '',
      url: map['url']?.toString(),
      tags: parsedTags,
      reminderAt: map['reminderAt'] != null
          ? DateTime.tryParse(map['reminderAt'].toString())
          : null,
      isCompleted: map['isCompleted'] == true,
      isPinned: map['isPinned'] == true,
      priority: priorityLevel,
      colorHex: map['colorHex']?.toString() ?? '#3B82F6',
      checklist: parsedChecklist,
      images: parsedImages,
      folderId: map['folderId']?.toString(),
      createdAt: map['createdAt'] != null
          ? (DateTime.tryParse(map['createdAt'].toString()) ?? now)
          : now,
      updatedAt: map['updatedAt'] != null
          ? (DateTime.tryParse(map['updatedAt'].toString()) ?? now)
          : now,
      isDeleted: map['isDeleted'] == true,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory HubItem.fromJson(String source) =>
      HubItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class SyncReport {
  final int added;
  final int updated;
  final int skipped;
  final int foldersAdded;
  final int foldersUpdated;
  final DateTime syncedAt;

  SyncReport({
    required this.added,
    required this.updated,
    required this.skipped,
    this.foldersAdded = 0,
    this.foldersUpdated = 0,
    required this.syncedAt,
  });
}
