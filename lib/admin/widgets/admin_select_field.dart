import 'package:flutter/material.dart';

/// One option in [AdminSelectField]. [id] is the stored value (document id).
class AdminSelectItem {
  const AdminSelectItem({required this.id, required this.label});

  final String id;
  final String label;
}

/// Keeps the first occurrence of each non-empty id.
List<AdminSelectItem> uniqueAdminSelectItems(List<AdminSelectItem> items) {
  final seen = <String>{};
  final out = <AdminSelectItem>[];
  for (final item in items) {
    if (item.id.isEmpty || !seen.add(item.id)) continue;
    out.add(item);
  }
  return out;
}

/// Returns [selectedId] only when it exists in [itemIds]. Never substitutes
/// another item (that made Exam appear stuck on the first exam).
String? committedSelectId(String selectedId, Iterable<String> itemIds) {
  if (selectedId.isEmpty) return null;
  for (final id in itemIds) {
    if (id == selectedId) return selectedId;
  }
  return null;
}

/// Index dropdown that commits via [MenuItemButton.onPressed].
///
/// [DropdownButtonFormField] on Flutter web often fails to fire `onChanged`
/// because the menu overlay sits under a full-screen semantics layer.
class AdminSelectField extends StatelessWidget {
  const AdminSelectField({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
    this.enabled = true,
  });

  final String label;
  final String? value;
  final List<AdminSelectItem> items;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final unique = uniqueAdminSelectItems(items);
    final selectedId = committedSelectId(value ?? '', unique.map((e) => e.id));
    var display = '';
    if (selectedId != null) {
      for (final item in unique) {
        if (item.id == selectedId) {
          display = item.label;
          break;
        }
      }
    }

    return MenuAnchor(
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(MediaQuery.sizeOf(context).width.clamp(280, 640), 360),
        ),
      ),
      builder: (context, controller, child) {
        return InkWell(
          onTap: !enabled || unique.isEmpty
              ? null
              : () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
          child: InputDecorator(
            isEmpty: selectedId == null,
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
              enabled: enabled && unique.isNotEmpty,
            ),
            child: Text(
              display.isEmpty ? '' : display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
      menuChildren: [
        for (final item in unique)
          MenuItemButton(
            onPressed: () => onChanged(item.id),
            trailingIcon: item.id == selectedId
                ? const Icon(Icons.check, size: 18)
                : null,
            child: Text(item.label),
          ),
      ],
    );
  }
}
