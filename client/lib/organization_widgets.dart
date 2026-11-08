import 'package:flutter/material.dart';

import 'models.dart';
import 'organization.dart';
import 'pages.dart' show confirm;
import 'store.dart';
import 'dialogs.dart';
import 'ui.dart' show guard, label;

class GroupPicker extends StatelessWidget {
  const GroupPicker({
    super.key,
    required this.store,
    required this.type,
    required this.selected,
    required this.onChanged,
  });
  final Cookbook store;
  final String type;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  @override
  Widget build(BuildContext context) {
    final groups = recipeGroups(store, type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label(type == 'category' ? 'Categorías' : 'Mis catálogos'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final group in groups)
              FilterChip(
                label: Text(group.title),
                selected: selected.contains(group.id),
                onSelected: (v) {
                  final ids = {...selected};
                  if (v) {
                    ids.add(group.id);
                  } else {
                    ids.remove(group.id);
                  }
                  onChanged(ids);
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(
                type == 'category' ? 'Crear categoría' : 'Crear catálogo',
              ),
              onPressed: () async {
                final id = await groupDialog(context, store, type);
                if (context.mounted && id != null) onChanged({...selected, id});
              },
            ),
          ],
        ),
      ],
    );
  }
}

Future<String?> groupDialog(
  BuildContext context,
  Cookbook s,
  String type, {
  Entry? entry,
}) async {
  final text = TextEditingController(text: entry?.title ?? '');
  String? id, error;
  bool busy = false;
  await showDialog(
    context: context,
    builder: (c) => ManagedDialogBuilder(
      controllers: [text],
      builder: (c, set) => AlertDialog(
        title: Text(
          '${entry == null ? 'Crear' : 'Renombrar'} ${type == 'category' ? 'categoría' : 'catálogo'}',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                autofocus: true,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  hintText: type == 'category'
                      ? 'Por ejemplo: Cocina al horno'
                      : 'Por ejemplo: Recetas de la abuela',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    set(() => busy = true);
                    try {
                      final name = text.text.trim();
                      if (name.isEmpty) throw Exception('Escribe un nombre.');
                      if (recipeGroups(s, type).any(
                        (e) =>
                            e.id != entry?.id &&
                            searchKey(e.title) == searchKey(name),
                      )) {
                        throw Exception('Ya existe ese nombre.');
                      }
                      id = entry?.id ?? s.newId();
                      await s.save('collection', {
                        'title': name,
                        'type': type,
                      }, id: id);
                      if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                        Navigator.pop(c);
                      }
                    } catch (e) {
                      id = null;
                      if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                        set(() => error = '$e'.replaceFirst('Exception: ', ''));
                      }
                    } finally {
                      if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                        set(() => busy = false);
                      }
                    }
                  },
            child: Text(busy ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
    ),
  );
  return id;
}

Future<void> organizeDialog(BuildContext context, Cookbook s) => showDialog(
  context: context,
  builder: (c) => AnimatedBuilder(
    animation: s,
    builder: (c, _) => AlertDialog(
      title: const Text('Organizar mi recetario'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Una receta puede estar en varias categorías y catálogos. Se comparten con tu familia al sincronizar.',
            ),
            for (final type in ['catalog', 'category']) ...[
              label(type == 'catalog' ? 'Mis catálogos' : 'Categorías'),
              for (final group in recipeGroups(s, type))
                ListTile(
                  leading: Icon(
                    type == 'catalog'
                        ? Icons.collections_bookmark_outlined
                        : Icons.category_outlined,
                  ),
                  title: Text(group.title),
                  subtitle: Text(
                    '${s.of('recipe').where((e) => e.lines(groupField(type)).contains(group.id)).length} recetas${group.custom ? '' : ' · incluida'}',
                  ),
                  trailing: group.custom && s.editable
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Renombrar',
                              onPressed: () => groupDialog(
                                c,
                                s,
                                type,
                                entry: s.get(group.id),
                              ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Quitar grupo',
                              onPressed: () => guard(c, () async {
                                if (await confirm(
                                  c,
                                  '¿Quitar ${group.title}?',
                                  'Las recetas se conservan. Puedes recuperar el grupo desde la papelera.',
                                )) {
                                  await s.delete(s.get(group.id)!);
                                }
                              }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        )
                      : null,
                ),
              if (s.editable)
                TextButton.icon(
                  onPressed: () => groupDialog(c, s, type),
                  icon: const Icon(Icons.add),
                  label: Text(
                    type == 'catalog' ? 'Crear catálogo' : 'Crear categoría',
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  ),
);
