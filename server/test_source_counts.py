import json
from pathlib import Path
from urllib.parse import urlsplit

from server.catalogs import SOURCES


def test_every_current_source_has_reviewed_count_classification():
    counts = json.loads(Path(__file__).with_name('source_counts.json').read_text(encoding='utf-8'))
    assert counts.keys() == SOURCES.keys() and len(counts) == 25
    assert not {'agro-caribe', 'agro-arracacha', 'sabores-uy'} & counts.keys()
    known = [s for s in SOURCES.values() if s['recipe_count'] is not None]
    assert len(known) == 17
    assert all(s['recipe_count'] > 0 and urlsplit(s['count_evidence']).scheme == 'https' for s in known)
    for source in SOURCES.values():
        assert source['count_checked_at'] in {'2026-10-11','2026-10-16','2026-10-22'} and source['count_note']
        assert counts[source['id']]['recipe_count'] == source['recipe_count']
        if source['recipe_count'] is None:
            assert source['count_kind'] in ('not_verified', 'not_applicable')
    # Historical multi-language platform totals are excluded from current ranks.
    assert SOURCES['es-petitchef']['recipe_count'] == 33527
    assert SOURCES['es-petitchef']['count_kind'] == 'indexed_entries'
    assert SOURCES['es-petitchef']['count_evidence'].endswith('/recipe-es.xml')
    assert SOURCES['mx-kiwilimon']['recipe_count'] == 21000
    selection = json.loads(Path(__file__).with_name('source_selection.json').read_text(encoding='utf-8'))
    assert set(SOURCES) == set(selection['retained_ids']) | set(selection['added_open_ids'])
    assert not set(selection['retired_ids']) & set(SOURCES)
    ranked = sorted(known, key=lambda source: source['recipe_count'], reverse=True)
    assert ranked[-1]['id'] == 'book-polaca' and ranked[-1]['recipe_count'] == 12
    assert sum(s['recipe_count'] is None for s in SOURCES.values()) == 8
