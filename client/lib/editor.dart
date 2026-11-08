import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'input_files.dart';
import 'photos.dart';
import 'catalogs.dart';
import 'library.dart';
import 'store.dart';
import 'dialogs.dart';
import 'organization_widgets.dart';
import 'ui.dart' show label, guard, message;

class RecipeEditor extends StatefulWidget {
  const RecipeEditor({
    super.key,
    required this.store,
    this.entry,
    this.initial,
  });
  final Cookbook store;
  final Entry? entry;
  final Map<String, dynamic>? initial;
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  final fields = <String, TextEditingController>{};
  final form = GlobalKey<FormState>();
  String image = '';
  List<Map<String, dynamic>> photos = [];
  bool loadingPhotos = false;
  Map<String, dynamic> extra = {};
  Set<String> categories = {}, catalogs = {};
  int rating = 0;
  bool busy = false, saved = false;
  bool readingPhoto = false;
  Timer? debounce;
  String get draftKey => 'draft:${widget.entry?.id ?? 'new'}';
  @override
  void initState() {
    super.initState();
    var value = widget.initial ?? widget.entry?.data ?? <String, dynamic>{};
    final draft = widget.store.prefs[draftKey];
    if (widget.initial == null && draft != null && draft.isNotEmpty) {
      try {
        value = jsonDecode(draft);
      } catch (_) {}
    }
    value = onlineRecipeData(Map<String, dynamic>.from(value));
    image = coverImage(value);
    photos = recipePhotos(value);
    extra = Map<String, dynamic>.from(value);
    categories = Set<String>.from(value['category_ids'] ?? []);
    catalogs = Set<String>.from(value['catalog_ids'] ?? []);
    rating = value['rating'] as int? ?? 0;
    for (final key in [
      'title',
      'ingredients',
      'steps',
      'servings',
      'minutes',
      'tags',
      'notes',
      'source',
    ]) {
      final raw = value[key];
      fields[key] = TextEditingController(
        text: raw is List
            ? raw.join(key == 'tags' ? ', ' : '\n')
            : '${raw ?? (key == 'servings'
                      ? 4
                      : key == 'minutes'
                      ? ''
                      : '')}',
      );
      fields[key]!.addListener(persistDraft);
    }
    fields['ingredients']!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Map<String, dynamic> data() => {
    ...extra,
    'title': fields['title']!.text.trim(),
    'ingredients': fields['ingredients']!.text
        .split('\n')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList(),
    'steps': fields['steps']!.text
        .split('\n')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList(),
    'servings': draftServings(),
    'minutes': int.tryParse(fields['minutes']!.text) ?? 0,
    'tags': fields['tags']!.text
        .split(',')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList(),
    'notes': fields['notes']!.text.trim(),
    'source': fields['source']!.text.trim(),
    'image_url': image,
    'photos': photos,
    'category_ids': categories.toList(),
    'catalog_ids': catalogs.toList(),
    'rating': rating,
  };
  double draftServings() {
    final value = double.tryParse(
      fields['servings']!.text.replaceAll(',', '.'),
    );
    return value != null && value.isFinite ? value : 4;
  }

  Future<void> writeDraft() async {
    if (saved) return;
    try {
      await widget.store.preference(draftKey, jsonEncode(data()));
    } catch (_) {
      if (mounted) {
        message(
          context,
          'No se pudo guardar el borrador. Revisa el espacio disponible e intenta Guardar.',
        );
      }
    }
  }

  void persistDraft() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 450), () {
      if (!saved) {
        unawaited(writeDraft());
      }
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    if (!saved) {
      unawaited(writeDraft());
    }
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget input(String key, String title, {int lines = 1, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: fields[key],
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 6,
          keyboardType: ['servings', 'minutes'].contains(key)
              ? TextInputType.number
              : TextInputType.multiline,
          validator: (text) {
            if (key == 'title' && (text == null || text.trim().isEmpty)) {
              return 'Ponle un nombre a tu receta.';
            }
            if (key == 'title' && text!.length > 250) {
              return 'Usa un título más corto.';
            }
            if (key == 'servings') {
              final n = double.tryParse((text ?? '').replaceAll(',', '.'));
              if (n == null || !n.isFinite || n <= 0 || n > 10000) {
                return 'Introduce raciones entre 1 y 10.000.';
              }
            }
            if (key == 'minutes' && (text ?? '').trim().isNotEmpty) {
              final n = int.tryParse(text!);
              if (n == null || n < 0 || n > 100000) {
                return 'Introduce minutos entre 0 y 100.000.';
              }
            }
            return null;
          },
          decoration: InputDecoration(
            labelText: title,
            hintText: hint,
            alignLabelWithHint: true,
          ),
        ),
      );
  Future<void> photo() => guard(context, () async {
    final field = TextEditingController();
    String? error;
    final url = await showDialog<String>(
      context: context,
      builder: (c) => ManagedDialogBuilder(
        controllers: [field],
        builder: (c, update) => AlertDialog(
          title: const Text('Añadir foto por enlace'),
          content: TextField(
            controller: field,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'URL de la foto (https://)',
              helperText: 'Se consulta en línea; no se guarda una copia.',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value = field.text.trim();
                if (!onlinePhotoUrl(value)) {
                  update(
                    () => error = 'Usa un enlace HTTPS público a una imagen.',
                  );
                } else {
                  Navigator.pop(c, value);
                }
              },
              child: const Text('Añadir'),
            ),
          ],
        ),
      ),
    );
    if (url == null || !mounted) return;
    setState(() {
      if (!photos.any((p) => p['url'] == url)) {
        photos.add({'url': url, 'caption': 'Foto de la receta'});
      }
      if (image.isEmpty) image = url;
    });
    persistDraft();
  });

  Future<void> reloadPhotos() => guard(context, () async {
    setState(() => loadingPhotos = true);
    try {
      Map<String, dynamic> source;
      final origin = extra['origin'];
      if (origin is Map &&
          catalogSources.any((s) => s.id == origin['provider'])) {
        source =
            await CatalogApi(
              widget.store.client,
              externalDetail:
                  widget.store.url.isEmpty || widget.store.token.isEmpty
                  ? null
                  : (provider, url) async => Map<String, dynamic>.from(
                      await widget.store.request(
                        'POST',
                        '/v1/import-url',
                        body: {'provider': provider, 'url': url},
                      ),
                    ),
            ).detail(
              CatalogItem(
                id: origin['id'],
                title: fields['title']!.text,
                provider: origin['provider'],
              ),
            );
      } else {
        if (widget.store.url.isEmpty) {
          throw Exception(
            'Conecta el servidor familiar para recuperar fotos de este enlace.',
          );
        }
        source = Map<String, dynamic>.from(
          await widget.store.request(
            'POST',
            '/v1/import-url',
            body: {'url': fields['source']!.text},
          ),
        );
      }
      if (!mounted) {
        return;
      }
      final additions = recipePhotos(source);
      setState(() {
        for (final photo in additions) {
          final index = photos.indexWhere(
            (p) =>
                (photo['source'] ?? '').isNotEmpty &&
                p['source'] == photo['source'] &&
                (p['url'] == photo['url'] && p['caption'] == photo['caption'] ||
                    (origin is Map && origin['provider'] == 'wiki-es')),
          );
          if (index < 0) {
            photos.add(photo);
          } else {
            photos[index] = photo;
          }
        }
      });
      persistDraft();
      message(
        context,
        additions.isEmpty
            ? 'Esta fuente no incluye fotos del plato.'
            : 'Enlaces actualizados. Guarda para conservar los cambios.',
      );
    } finally {
      if (mounted) {
        setState(() => loadingPhotos = false);
      }
    }
  });
  Future<void> findQuantities() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 760,
          height: 650,
          child: DiscoverRecipes(
            store: widget.store,
            initialQuery: fields['title']!.text,
            saveLabel: 'Usar ingredientes y raciones',
            onEdit: ({entry, initial}) async {
              if (initial == null || !mounted) {
                return;
              }
              fields['ingredients']!.text = (initial['ingredients'] as List)
                  .join('\n');
              fields['servings']!.text = '${initial['servings']}';
              fields['notes']!.text =
                  '${fields['notes']!.text}\n\nIngredientes y raciones adaptados desde: ${initial['source']}\n${initial['origin']['attribution']} · ${initial['origin']['license']}\n${initial['origin']['license_url']}\nRevisa que estas cantidades sean compatibles con los pasos de esta receta.'
                      .trim();
              setState(() {
                extra['ingredient_origin'] = initial['origin'];
              });
              persistDraft();
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> ocr(bool camera) => guard(context, () async {
    if (readingPhoto) return;
    if (widget.store.url.isEmpty || widget.store.token.isEmpty) {
      throw Exception(
        'Conecta con el ordenador de Mesa para leer fotos con Indra OCR.',
      );
    }
    setState(() => readingPhoto = true);
    Uint8List? bytes;
    XFile? capture;
    String? text;
    try {
      if (camera) {
        capture = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 85,
        );
        if (capture != null) {
          if (await capture.length() > 10000000) {
            throw Exception('La foto supera 10 MB.');
          }
          bytes = await readLimitedBytes(
            capture.openRead(),
            maxBytes: 10000000,
          );
        }
      } else {
        final value = await FilePicker.pickFile(type: FileType.image);
        if (value != null) {
          if ((value.lengthSync() ?? 0) > 10000000) {
            throw Exception('La foto supera 10 MB.');
          }
          bytes = await readLimitedBytes(
            value.readAsByteStream(),
            maxBytes: 10000000,
          );
        }
      }
      if (bytes == null) return;
      if (bytes.length > 10000000) throw Exception('La foto supera 10 MB.');
      text = await widget.store.recognizeImage(bytes);
    } finally {
      bytes = null;
      if (mounted) setState(() => readingPhoto = false);
      if (capture != null) {
        final directory = await getTemporaryDirectory();
        final file = File(capture.path);
        // ImagePicker camera creates a temporary copy; never delete a user's
        // original image selected from files or an image outside app cache.
        if (path.isWithin(directory.path, file.path) && await file.exists()) {
          await file.delete();
        }
      }
    }
    if (!mounted) return;
    if (text.isNotEmpty) {
      fields['notes']!.text = '${fields['notes']!.text}\n$text'.trim();
      message(context, 'Texto añadido a las notas. La foto no se guarda.');
    } else {
      message(context, 'No se reconoció texto. Prueba una foto más nítida.');
    }
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.entry == null ? 'Nueva receta' : 'Editar receta'),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FilledButton(
            onPressed: busy
                ? null
                : () => guard(context, () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    try {
                      await widget.store.save(
                        'recipe',
                        data(),
                        id: widget.entry?.id,
                      );
                      saved = true;
                      debounce?.cancel();
                      await widget.store.preference(draftKey, '');
                      if (context.mounted) Navigator.pop(context);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }),
            child: Text(busy ? 'Guardando…' : 'Guardar'),
          ),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              input(
                'title',
                'Nombre de la receta',
                hint: 'Por ejemplo: la sopa de la abuela',
              ),
              PhotoGallery(
                photos: photos,
                onCover: (i) {
                  setState(() => image = photos[i]['url'] ?? '');
                  persistDraft();
                },
                onRemove: (i) {
                  setState(() {
                    final removed = photos.removeAt(i);
                    if (removed['url'] == image) {
                      image = '';
                    }
                  });
                  persistDraft();
                },
              ),
              if (missingQuantities(data()).isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cantidades por revisar: ${missingQuantities(data()).join(', ')}',
                        ),
                        TextButton.icon(
                          onPressed: findQuantities,
                          icon: const Icon(Icons.search),
                          label: const Text('Buscar receta con cantidades'),
                        ),
                      ],
                    ),
                  ),
                ),
              input(
                'ingredients',
                'Ingredientes · uno por línea',
                lines: 4,
                hint: '200 g de arroz\n2 huevos\nSal al gusto',
              ),
              input(
                'steps',
                'Pasos · uno por línea',
                lines: 5,
                hint: 'Prepara los ingredientes.\nCocina a fuego suave.',
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: input(
                      'servings',
                      extra['servings_declared'] == false
                          ? 'Base de cantidades (revisar)'
                          : recipeYieldUnit(extra) == 'unidades'
                          ? 'Unidades'
                          : 'Raciones',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: input('minutes', 'Minutos')),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Fotos y lectura de texto'),
                children: [
                  const Text(
                    'Indra OCR lee la foto en tu ordenador de Mesa. Necesita conexión; '
                    'no guarda la imagen. Revisa el texto y las cantidades antes de usarlos.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: photo,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Añadir enlace de foto'),
                      ),
                      if (Platform.isAndroid)
                        OutlinedButton.icon(
                          onPressed: readingPhoto ? null : () => ocr(true),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Leer texto con cámara'),
                        ),
                      OutlinedButton.icon(
                        onPressed: readingPhoto ? null : () => ocr(false),
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: Text(
                          readingPhoto
                              ? 'Leyendo foto…'
                              : 'Leer texto de una foto',
                        ),
                      ),
                      if (extra['origin'] is Map ||
                          fields['source']!.text.startsWith('https://'))
                        OutlinedButton.icon(
                          onPressed: loadingPhotos ? null : reloadPhotos,
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            loadingPhotos
                                ? 'Consultando enlaces…'
                                : 'Actualizar enlaces de fotos',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Organizar y valorar'),
                children: [
                  input(
                    'tags',
                    'Etiquetas separadas por comas',
                    hint: 'Rápidas, En familia',
                  ),
                  GroupPicker(
                    store: widget.store,
                    type: 'category',
                    selected: categories,
                    onChanged: (v) {
                      setState(() => categories = v);
                      persistDraft();
                    },
                  ),
                  GroupPicker(
                    store: widget.store,
                    type: 'catalog',
                    selected: catalogs,
                    onChanged: (v) {
                      setState(() => catalogs = v);
                      persistDraft();
                    },
                  ),
                  label('Valoración familiar'),
                  Wrap(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          tooltip: '$i estrellas',
                          onPressed: () {
                            setState(() => rating = rating == i ? 0 : i);
                            persistDraft();
                          },
                          icon: Icon(
                            i <= rating ? Icons.star : Icons.star_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (extra['origin'] is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '${extra['origin']['attribution']} · ${extra['origin']['license']}\nAdaptación del texto original. La atribución se conserva al guardar.',
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Notas y origen'),
                maintainState: true,
                children: [
                  input('notes', 'Notas y texto original', lines: 3),
                  input('source', 'Origen o enlace'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Text(
                      '¿Tienes la receta en un mensaje? Pega el texto en las notas y ordénala cuando quieras.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> importRecipeDialog(
  BuildContext context,
  Cookbook s,
  Future<void> Function(Map<String, dynamic>) edit,
) async {
  final text = TextEditingController();
  String? error;
  bool busy = false;
  Map<String, dynamic>? result;
  bool manual = false;
  await showDialog(
    context: context,
    builder: (context) => ManagedDialogBuilder(
      controllers: [text],
      builder: (context, set) => AlertDialog(
        title: const Text('Importar receta'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pega un enlace, texto o datos de una receta. Podrás revisarlo antes de guardar.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Enlace o contenido',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (text.text.trim().isEmpty) return;
                    set(() => busy = true);
                    final value = text.text.trim();
                    try {
                      if (value.startsWith('https://')) {
                        try {
                          result = await CatalogApi(s.client).importUrl(value);
                        } catch (_) {
                          result = null;
                        }
                      }
                      if (result == null && s.url.isNotEmpty) {
                        try {
                          result = Map<String, dynamic>.from(
                            await s.request(
                              'POST',
                              value.startsWith('https://') ||
                                      value.startsWith('http://')
                                  ? '/v1/import-url'
                                  : '/v1/import',
                              body:
                                  value.startsWith('https://') ||
                                      value.startsWith('http://')
                                  ? {'url': value}
                                  : {'text': value},
                            ),
                          );
                        } catch (_) {
                          result = null;
                        }
                      }
                      if (result != null) {
                        try {
                          result = await s.translateImportedRecipe(result!);
                        } catch (_) {
                          if (context.mounted) {
                            message(
                              context,
                              'Se conserva el original. Puedes reintentar la traducción desde la receta.',
                            );
                          }
                        }
                      }
                      manual = result == null;
                      result ??= {
                        'title': value.startsWith('http')
                            ? 'Receta de un enlace'
                            : value
                                  .split('\n')
                                  .first
                                  .substring(
                                    0,
                                    value
                                        .split('\n')
                                        .first
                                        .length
                                        .clamp(0, 100),
                                  ),
                        'ingredients': <String>[],
                        'steps': <String>[],
                        'tags': <String>[],
                        'servings': 4,
                        'minutes': 0,
                        'source': value.startsWith('http') ? value : '',
                        'notes': value,
                        'image': '',
                      };
                      if (context.mounted &&
                          ModalRoute.of(context)?.isCurrent == true) {
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        set(() {
                          error = '$e';
                          busy = false;
                        });
                      }
                    }
                  },
            child: Text(busy ? 'Preparando…' : 'Revisar receta'),
          ),
        ],
      ),
    ),
  );
  if (result != null && context.mounted) {
    if (manual) {
      message(
        context,
        'Contenido conservado como borrador. Revisa y completa ingredientes y pasos.',
      );
    }
    await edit(result!);
  }
}
