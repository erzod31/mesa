import 'models.dart';
import 'store.dart';

class RecipeGroup {
  const RecipeGroup(this.id, this.title, this.symbol, {this.custom = false});
  final String id, title, symbol;
  final bool custom;
}

const defaultCategories = [
  RecipeGroup('category:desayunos', 'Desayunos', '☀'),
  RecipeGroup('category:entrantes', 'Entrantes', '◇'),
  RecipeGroup('category:ensaladas', 'Ensaladas', '❋'),
  RecipeGroup('category:sopas', 'Sopas y cremas', '≈'),
  RecipeGroup('category:arroz-pasta', 'Arroces y pasta', '◌'),
  RecipeGroup('category:carnes', 'Carnes', '♨'),
  RecipeGroup('category:pescados', 'Pescados', '≋'),
  RecipeGroup('category:legumbres', 'Legumbres', '∴'),
  RecipeGroup('category:verduras', 'Verduras', '✽'),
  RecipeGroup('category:postres', 'Postres', '♡'),
  RecipeGroup('category:panes', 'Panes y masas', '▱'),
  RecipeGroup('category:salsas', 'Salsas', '◒'),
  RecipeGroup('category:bebidas', 'Bebidas', '◉'),
];

List<RecipeGroup> recipeGroups(Cookbook store, String type) => [
  if (type == 'category') ...defaultCategories,
  ...store
      .of('collection')
      .where((e) => e.data['type'] == type)
      .map(
        (e) => RecipeGroup(
          e.id,
          e.title,
          type == 'category' ? '✽' : '▤',
          custom: true,
        ),
      ),
];

String groupField(String type) =>
    type == 'category' ? 'category_ids' : 'catalog_ids';

bool inGroup(Entry recipe, String field, String? id) =>
    id == null || recipe.lines(field).contains(id);

bool matchesRecipe(
  Entry e,
  Cookbook s, {
  String query = '',
  String? category,
  String? catalog,
  String? tag,
  bool favorites = false,
  int? maxMinutes,
  String exclude = '',
}) {
  final haystack = searchKey(
    '${e.title} ${e.lines('ingredients').join(' ')} ${e.lines('tags').join(' ')} ${e.data['notes'] ?? ''}',
  );
  final words = searchKey(query)
      .trim()
      .split(RegExp(r'\s+'))
      .where((x) => x.isNotEmpty);
  final excluded = searchKey(exclude)
      .split(',')
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty);
  final ingredients = searchKey(e.lines('ingredients').join(' '));
  final minutes = e.data['minutes'] as int? ?? 0;
  return words.every(haystack.contains) &&
      excluded.every((x) => !ingredients.contains(x)) &&
      inGroup(e, 'category_ids', category) &&
      inGroup(e, 'catalog_ids', catalog) &&
      (tag == null || e.lines('tags').contains(tag)) &&
      (!favorites || s.favorite(e.id)) &&
      (maxMinutes == null || minutes > 0 && minutes <= maxMinutes);
}

List<Entry> similarRecipes(Cookbook s, Map<String, dynamic> data) =>
    s.of('recipe').where((e) {
      final origin = data['origin'];
      final previous = e.data['origin'];
      return (origin is Map &&
              previous is Map &&
              origin['provider'] == previous['provider'] &&
              origin['id'] == previous['id']) ||
          searchKey(e.title).trim() == searchKey('${data['title']}').trim();
    }).toList();
