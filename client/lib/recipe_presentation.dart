import 'package:flutter/material.dart';

import 'measurements.dart';
import 'models.dart';
import 'translation.dart';

class RecipeTranslationAction extends StatefulWidget {
  const RecipeTranslationAction({
    super.key,
    required this.data,
    required this.translate,
    required this.apply,
  });
  final Map<String, dynamic> data;
  final Future<Map<String, dynamic>> Function() translate;
  final Future<void> Function(Map<String, dynamic>) apply;
  @override
  State<RecipeTranslationAction> createState() =>
      _RecipeTranslationActionState();
}

class _RecipeTranslationActionState extends State<RecipeTranslationAction> {
  bool busy = false, reviewing = false;
  Future<void> run() async {
    setState(() => busy = true);
    try {
      final value = await widget.translate();
      if (!mounted) return;
      setState(() => reviewing = true);
      final use = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Revisar traducción'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comprueba el resultado antes de aplicarlo. Se conservará el texto original.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '${value['title']}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ingredientes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...List<String>.from(value['ingredients'] ?? []).map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(t),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Preparación',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...List<String>.from(value['steps'] ?? []).map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(t),
                    ),
                  ),
                  if ('${value['notes'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SelectableText('${value['notes']}'),
                  ],
                  OriginalRecipeText(data: value),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Descartar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Aplicar traducción'),
            ),
          ],
        ),
      );
      if (use == true) await widget.apply(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          reviewing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canTranslateRecipe(widget.data)) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: busy ? null : run,
      icon: busy && !reviewing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.translate),
      label: Text(
        busy && !reviewing
            ? 'Traduciendo…'
            : widget.data['original'] is Map
            ? 'Volver a traducir'
            : 'Traducir al español',
      ),
    );
  }
}

List<String> presentedIngredients(
  Map<String, dynamic> data,
  double ratio, {
  bool originalMeasures = false,
}) => List<String>.from(data['ingredients'] ?? []).map((line) {
  final scaled = scaleIngredient(line, ratio);
  return originalMeasures
      ? scaled
      : practicalMetric(
          scaled,
          language:
              '${data['original']?['language'] ?? data['origin']?['language'] ?? data['language'] ?? 'es'}',
          source: '${data['source'] ?? ''}',
        );
}).toList();

class OriginalRecipeText extends StatelessWidget {
  const OriginalRecipeText({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final original = data['original'];
    if (original is! Map) return const SizedBox.shrink();
    return ExpansionTile(
      title: const Text('Texto y medidas originales'),
      subtitle: Text(
        '${'${data['translation']?['engine'] ?? ''}'.startsWith('ML Kit') ? 'Traducción en el teléfono · conecta el ordenador y vuelve a traducir para mejorarla' : 'Traducción automática · revisa el resultado'}${(data['translation']?['revision'] as num? ?? 0) < translationRevision ? ' · versión anterior' : ''}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            [
              '${original['title'] ?? ''}',
              ...List<String>.from(original['ingredients'] ?? []),
              '',
              ...List<String>.from(original['steps'] ?? []),
              '${original['notes'] ?? ''}',
            ].join('\n'),
            style: const TextStyle(height: 1.6),
          ),
        ),
      ],
    );
  }
}

/// Secondary reading controls stay available without interrupting ingredients and steps.
class RecipeOptions extends StatelessWidget {
  const RecipeOptions({
    super.key,
    required this.data,
    required this.originalMeasures,
    required this.onMeasuresChanged,
    this.translationAction,
  });
  final Map<String, dynamic> data;
  final bool originalMeasures;
  final ValueChanged<bool> onMeasuresChanged;
  final Widget? translationAction;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Original, medidas y fuente'),
    children: [
      SwitchListTile(
        title: const Text('Medidas originales'),
        subtitle: const Text(
          'Por defecto: equivalencias prácticas en g, ml y °C',
        ),
        value: originalMeasures,
        onChanged: onMeasuresChanged,
      ),
      OriginalRecipeText(data: data),
      ?translationAction,
      if ('${data['notes'] ?? ''}'.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('${data['notes']}'),
        ),
      if (data['origin'] is Map)
        Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            [
              '${data['origin']['attribution'] ?? ''}',
              '${data['origin']['license'] ?? ''}',
              '${data['origin']['license_url'] ?? ''}',
              '${data['origin']['url'] ?? data['source'] ?? ''}',
              if (data['origin']['modified'] == true) 'Formato adaptado para Mesa. Las equivalencias y traducciones se identifican; el original permanece disponible.',
            ].where((s) => s.isNotEmpty).join('\n'),
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        )
      else if ('${data['source'] ?? ''}'.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('${data['source']}'),
        ),
    ],
  );
}
