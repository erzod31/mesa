"""One reviewed source directory shared by the API and Flutter; no recipe scraping."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEB = [
    ('mx-kiwilimon', 'Kiwilimón', 'México', 'https://www.kiwilimon.com', '/receta/desayunos/chilaquiles-rojos'),
    ('ar-paulina', 'Paulina Cocina', 'Argentina', 'https://www.paulinacocina.net', '/como-hacer-empanadas-de-carne/9220'),
    ('ar-cocineros', 'Cocineros Argentinos', 'Argentina', 'https://cocinerosargentinos.com', '/recetas/carne/empanadas-de-carne'),
    ('pe-buenazo', 'Buenazo', 'Perú', 'https://buenazo.pe/recetas', '/platos-de-fondo/lomo-saltado-ingredientes-preparacion-61'),
    ('mx-larousse', 'Larousse Cocina', 'México', 'https://laroussecocina.mx', '/receta/pozole-rojo/'),
    ('mx-nestle', 'Recetas Nestlé · México', 'México', 'https://www.recetasnestle.com.mx', '/recetas/chilaquiles-rojos'),
    ('es-nestle', 'Nestlé Cocina · España', 'España', 'https://www.nestlecocina.es', '/receta/tortilla-de-patatas'),
    ('es-bonviveur', 'Bon Viveur', 'España', 'https://www.bonviveur.com/es', '/recetas/tortilla-de-patatas'),
    ('es-rechupete', 'Recetas de Rechupete', 'España', 'https://www.abc.es/recetasderechupete', '/'),
    ('es-hogarmania', 'Hogarmania', 'España', 'https://www.hogarmania.com/cocina/recetas', '/'),
    ('es-petitchef', 'Petitchef · español', 'España', 'https://www.petitchef.es', '/'),
    ('es-directo', 'Directo al Paladar', 'España', 'https://www.directoalpaladar.com', '/'),
    ('es-gratis', 'RecetasGratis', 'España', 'https://www.recetasgratis.net', '/'),
    ('es-recetinas', 'Recetinas', 'España', 'https://recetinas.com', '/'),
]
BOOK = [
]


def build():
    rows = [
        dict(id='wiki-es', name='Wikilibros', country='Internacional', url='https://es.wikibooks.org/wiki/Artes_culinarias/Recetas', mode='catalog', description='Recetario abierto en español · solo recetas con foto'),
        dict(id='delokos-es', name='La cocina delokos', country='España', url='https://delokos.wordpress.com', mode='catalog', description='Fotos y cantidades · consulta en línea · uso familiar no comercial'),
    ]
    for key, name, country, base, seed in WEB:
        # Preserve the base path when forming each reviewed recipe seed.
        seed_url = base.rstrip('/') + seed
        rows.append(dict(id=key, name=name, country=country, url=base+'/', seed=seed_url,
                         mode='web', description='Catálogo por Internet desde este dispositivo · importar y guardar requiere conexión con Mesa'))
    samples = {
        'es-bonviveur': 'https://www.bonviveur.com/es/recetas/tortilla-de-betanzos',
        'es-rechupete': 'https://www.recetasderechupete.com/tortilla-de-patatas-espanola-receta-paso-a-paso/5182/',
        'es-hogarmania': 'https://www.hogarmania.com/cocina/recetas/tortilla-de-patatas-al-horno.html',
        'es-directo': 'https://www.directoalpaladar.com/recetas-de-huevos-y-tortillas/empezando-en-la-cocina-receta-de-tortilla-de-patatas-con-cebolla',
        'es-gratis': 'https://www.recetasgratis.net/receta-de-lentejas-con-arroz-y-tomate-59773.html',
        'es-nestle': 'https://www.nestlecocina.es/receta/tortilla-de-patatas-con-cebolla',
    }
    for row in rows:
        if row['id'] in samples: row['seed'] = samples[row['id']]
        if row['id'] == 'es-rechupete': row['aliases'] = ['www.recetasderechupete.com','recetasderechupete.com','www.abc.es']
        if row['id'] == 'es-bonviveur': row['aliases'] = ['bonviveur.com']
        if row['id'] == 'es-gratis': row['aliases'] = ['recetas.elperiodico.com']
        descriptions = {
            'es-nestle': 'Consulta del sitio original · la fuente bloquea actualmente la importación automática',
            'us-myplate': 'Consulta del sitio original · importación suspendida por un certificado no válido',
            'es-canarias': 'Consulta web · la receta examinada no declara cantidades; revisa cada ficha antes de importar',
            've-tuya': 'Consulta web · algunos artículos no contienen cantidades completas; se conserva el acceso al original',
        }
        if row['id'] in descriptions: row['description'] = descriptions[row['id']]
    for key, name, country, url, description in BOOK:
        rows.append(dict(id=key, name=name, country=country, url=url, mode='book', description=description))
    for row in rows:
        row['language_code']='es';row['language']='Español'
        if row['id']=='wiki-es': row.update(license='CC BY-SA 4.0',license_url='https://creativecommons.org/licenses/by-sa/4.0/deed.es')
        if row['id']=='delokos-es': row.update(license='CC BY-NC-SA 2.5 ES',license_url='https://creativecommons.org/licenses/by-nc-sa/2.5/es/')
    rows.append(dict(id='es-creativegan',name='CreatiVegan',country='España',url='https://creativegan.net/',mode='web',
        aliases=['www.creativegan.net'],seed='https://creativegan.net/archives/arroz-con-leche-de-soja/',language='Español',language_code='es',
        description='Recetas vegetales con cantidades y fotos · Virginia García · uso no comercial',
        license='CC BY-NC-SA 3.0 ES',license_url='https://creativecommons.org/licenses/by-nc-sa/3.0/es/'))
    rows.append(dict(id='es-encantar', name='Recetas para encantar', country='España',
        url='https://recetasparaencantar.com/', aliases=['recetasparaencantar.wordpress.com'],
        mode='catalog', language='Español', language_code='es',
        description='Cocina familiar con fotos del proceso · Dana Madiana · uso no comercial',
        license='CC BY-NC 3.0',license_url='https://creativecommons.org/licenses/by-nc/3.0/'))
    for provider,name in [('book-polaca','Mesa polaca')]:
        collection=json.loads((ROOT/'server/licensed_collections'/f'{provider}.json').read_text(encoding='utf8'))
        doc=collection['document']
        rows.append(dict(id=provider,name=name,country=doc['country'],url=doc['url'],mode='asset',
            asset=f'assets/catalogs/{provider}.json',language='Español',language_code='es',
            description='Texto disponible sin conexión · fotos del documento mediante el ordenador conectado',
            license=doc['license'],license_url=doc['license_url']))
    # A license cannot be inferred from accessible metadata or a public photo.
    # Preserve the original link and previously saved family recipes.
    for row in rows:
        if row['id'] in {entry[0] for entry in WEB}:
            row['mode']='book'
            row['description']='Sitio original disponible · catálogo e importación pendientes de autorización del editor'
    open_rows=json.loads((ROOT/'server/open_sources.json').read_text(encoding='utf-8'))
    rows.extend(open_rows)
    selection = json.loads((ROOT/'server/source_selection.json').read_text(encoding='utf-8'))
    if {row['id'] for row in rows} != set(selection['retained_ids'])|set(selection.get('added_open_ids',[])):
        raise ValueError('El registro no coincide con la selección y ampliación libre autorizadas.')
    counts = json.loads((ROOT/'server/source_counts.json').read_text(encoding='utf-8'))
    if set(counts) != {row['id'] for row in rows}:
        raise ValueError('Cada fuente actual debe tener una clasificación de recuento.')
    for row in rows:
        row.update(counts[row['id']])
        row['permission_status']='pending_editor_permission' if row['mode']=='book' else 'published_license'
        row['permission_checked_at']='2026-10-22' if row['id']=='es-encantar' else '2026-10-16'
        row['permission_evidence']=row.get('license_url') or row['url']
    (ROOT/'server/sources.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
    code = '''// Generated by scripts/prepare_source_registry.py; edit that shared registry.
class CatalogSource {
  const CatalogSource(this.id, this.name, this.language, this.description,
      {this.country = '', this.url = '', this.mode = 'catalog', this.asset = '', this.seed = '', this.aliases = const [],
       this.recipeCount, this.countKind = 'not_verified', this.countEvidence = '', this.countCheckedAt = '', this.countNote = '', this.languageCode='es', this.licenseName='', this.licenseUrl=''});
  final String id, name, language, description, country, url, mode, asset;
  final String seed;
  final String languageCode, licenseName, licenseUrl;
  final List<String> aliases;
  final int? recipeCount;
  final String countKind, countEvidence, countCheckedAt, countNote;
  bool get included => mode == 'asset';
  bool get consultationOnly => mode == 'book';
  bool get external => mode == 'web';
  bool get browseable => !consultationOnly && id != 'es-nestle';
}

const originalSourceCount = 38;
const retiredSourceCount = 22;
const addedOpenSourceCount = 9;

const catalogSources = [
'''
    for row in rows:
        quote = lambda x: json.dumps(x, ensure_ascii=False)
        code += '  CatalogSource('+', '.join(quote(x) for x in (row['id'], row['name'], row.get('language','Español'), row['description']))
        code += ', languageCode: '+quote(row.get('language_code','es'))+', licenseName: '+quote(row.get('license',''))+', licenseUrl: '+quote(row.get('license_url',''))
        code += ', country: '+quote(row['country'])+', url: '+quote(row['url'])+', mode: '+quote(row['mode'])
        if 'asset' in row: code += ', asset: '+quote(row['asset'])
        if 'seed' in row: code += ', seed: '+quote(row['seed'])
        if 'aliases' in row: code += ', aliases: '+quote(row['aliases'])
        if row['recipe_count'] is not None: code += ', recipeCount: '+str(row['recipe_count'])
        code += ', countKind: '+quote(row['count_kind'])+', countEvidence: '+quote(row['count_evidence'])
        code += ', countCheckedAt: '+quote(row['count_checked_at'])+', countNote: '+quote(row['count_note'])
        code += '),\n'
    code += '];\n'
    (ROOT/'client/lib/source_registry.dart').write_text(code, encoding='utf-8')
    print(len(rows), 'fuentes registradas')


if __name__ == '__main__':
    build()
