import 'package:mesa/source_registry.dart' as production;
import 'package:mesa/source_registry.dart' show CatalogSource;

final fixtureSources = production.catalogSources
    .map(
      (s) => s.consultationOnly
          ? CatalogSource(
              s.id,
              s.name,
              s.language,
              s.description,
              country: s.country,
              url: s.url,
              mode: 'web',
              seed: s.seed,
              aliases: s.aliases,
              languageCode: s.languageCode,
            )
          : s,
    )
    .toList();
