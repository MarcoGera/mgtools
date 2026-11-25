import 'package:flutter_test/flutter_test.dart';
import 'package:mgtools/models/hub_item.dart';

void main() {
  test('HubItem JSON round-trip', () {
    final now = DateTime.now();
    final item = HubItem(
      id: 'test-note-1',
      type: ItemType.note,
      title: 'Тестовая заметка',
      content: 'Проверка сериализации',
      tags: const ['тест', 'mgtools'],
      createdAt: now,
      updatedAt: now,
    );

    final restored = HubItem.fromJson(item.toJson());

    expect(restored.id, item.id);
    expect(restored.type, ItemType.note);
    expect(restored.title, item.title);
    expect(restored.content, item.content);
    expect(restored.tags, item.tags);
  });
}
