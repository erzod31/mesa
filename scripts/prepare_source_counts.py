"""Reviewed publisher-wide counts, without treating unverified totals as zero."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKED = '2026-10-11'
PUBLISHED = {
    'mx-kiwilimon': (21000, 'more_than',
        'https://www.kiwilimon.com/recetas',
        'El sitio anuncia más de 21.000 recetas. Es una cifra del editor, no un censo de fichas importables.'),
    'es-gratis': (20000, 'more_than', 'https://recetas.elperiodico.com/',
        'El título del sitio anuncia más de 20.000 recetas. RecetasGratis redirige a este dominio.'),
    'ar-cocineros': (10000, 'at_least', 'https://cocinerosargentinos.com/',
        'La portada declara 10.000+ recetas; es un mínimo publicado, no un total exacto.'),
    'es-hogarmania': (7000, 'more_than', 'https://www.hogarmania.com/quienes-somos.html',
        'La página Quiénes somos declara más de 7.000 recetas.'),
    'mx-larousse': (5000, 'more_than', 'https://laroussecocina.mx/',
        'La descripción oficial del sitio declara más de 5.000 recetas.'),
    'es-nestle': (3238, 'displayed_total', 'https://www.nestlecocina.es/recetas',
        'Total mostrado en el listado consultado. Puede cambiar; la importación automática está bloqueada.'),
}


def main():
    rows = json.loads((ROOT/'server/sources.json').read_text(encoding='utf-8'))
    reviewed = json.loads((ROOT/'server/reviewed_source_counts.json').read_text(encoding='utf-8'))
    current = {row['id'] for row in rows}
    if not set(reviewed).issubset(current):
        raise ValueError('Un recuento corresponde a una fuente retirada.')
    counts = {}
    for row in rows:
        count, kind, evidence, note = PUBLISHED.get(row['id'], (
            None, 'not_verified', '',
            'No se ha verificado un total de recetas en español. No significa que tenga cero recetas.'))
        if row['id'] == 'es-petitchef' and count is None:
            note += ' La cifra histórica de 100.000 de 2014 no acredita el total actual exclusivamente en español.'
        if row['id'] == 'py-senatur':
            kind = 'not_applicable'
            note = 'Es un programa de turismo gastronómico; no se ha identificado una base de recetas contable.'
        if row['id'] == 'us-myplate':
            note = 'No se ha podido verificar el total español: el sitio presenta un certificado TLS no válido. No se desactiva la validación ni se utiliza el total inglés como sustituto.'
        if row['id'] == 'cr-ucr':
            note = 'No se ha verificado el total del libro. La descarga oficial expira sin datos en varios intentos y no se ha podido revisar su índice; no se estima por páginas ni por otros libros de UCR.'
        counts[row['id']] = dict(recipe_count=count, count_kind=kind,
            count_evidence=evidence, count_checked_at=CHECKED, count_note=note)
        if row.get('language_code','es') != 'es':
            counts[row['id']].update(count_evidence=row['url'],count_note='Total del catálogo no verificado; no significa cero recetas. Se incluyen solo recetas con foto.')
        if row['id'] in reviewed:
            item = reviewed[row['id']]
            if (not isinstance(item['recipe_count'], int) or item['recipe_count'] <= 0
                    or not item['count_evidence'].startswith('https://')
                    or not item['count_note'] or item['count_checked_at'] != CHECKED):
                raise ValueError('Recuento revisado incompleto o incorrecto.')
            counts[row['id']].update(item)
    counts['es-creativegan']=dict(recipe_count=None,count_kind='not_verified',
        count_evidence='https://creativegan.net/archives/licencias-fotos-y-recetas/',count_checked_at='2026-10-16',
        count_note='Publicaciones con cantidades, preparación y foto; total único no verificado.')
    collection=json.loads((ROOT/'server/licensed_collections/book-polaca.json').read_text(encoding='utf8'))
    counts['book-polaca']=dict(recipe_count=len(collection['recipes']),count_kind='reviewed_selection',
        count_evidence=collection['document']['url'],count_checked_at='2026-10-16',
        count_note='Fichas seleccionadas y revisadas para Mesa; no es el total de recetas del editor.')
    (ROOT/'server/source_counts.json').write_text(json.dumps(counts, ensure_ascii=False, indent=2), encoding='utf-8')
    print(len(counts), 'fuentes;', sum(s['recipe_count'] is not None for s in counts.values()), 'con recuento documentado.')


if __name__ == '__main__':
    main()
