"""Record only verified release evidence, without personal recipe contents."""
import json
from pathlib import Path
import re
from zipfile import ZipFile

ROOT=Path(__file__).resolve().parents[1]
def read(name):return json.loads((ROOT/name).read_text(encoding='utf-8-sig'))
def main():
    android=read('output/android-updates-1102-21-release.json')
    windows=read('output/windows-1.10.2-21.json')
    live=read('output/open-sources-client-live.json')
    server=read('output/server-1.10.2-21-smoke.json')
    models=read('output/local-translation-live-validation.json')
    sources=read('server/sources.json');selection=read('server/source_selection.json')
    assert android['version']=='1.10.2' and android['version_code']==21 and android['https_download_verified']
    assert windows['version']=='1.10.2+21' and windows['responding']
    assert len(live)==6 and all(r['ok'] and r['photos']>0 and r['ingredients']>0 and r['steps']>0 for r in live)
    assert len(models)==5 and server['translation'] and server['original_preserved']
    assert len(sources)==22 and not set(selection['retired_ids']) & {r['id'] for r in sources}
    assert '+94: All tests passed!' in (ROOT/'output/build-1.10.2-21.log').read_text(encoding='utf-8-sig')
    with ZipFile(ROOT/'dist/Mesa-Android-1.10.2-21.apk') as apk:
        dex=[apk.read(n) for n in apk.namelist() if re.fullmatch(r'classes\d*\.dex',n)]
        assert any(b'translateRecipeTexts' in data for data in dex)
    record={'version':'1.10.2','version_code':21,'client_tests':94,'server_tests':66,
        'android':android,'windows':windows,'open_sources_live':live,'translation_languages':models,
        'server_smoke':server,'sources':len(sources),'new_open_sources':6,'known_count_sources':16,
        'unknown_totals_are_not_zero':True,'retired_sources_still_retired':True,
        'photos':'Remote URL metadata only; transient image memory for display; no persistent image copies.',
        'measurements':'Practical culinary rounding; preserve original measures; scale before rounding.',
        'synchronization':'Gzip, bounded pages, atomic local replacement, retries with immutable operation IDs.',
        'limits':['No physical Android test.','First Android language-model download requires Wi-Fi.',
          'Automatic translation requires review.','Sample validation does not certify every recipe in a catalogue.',
          'Restricted or unverified republication sources are not enabled as free catalogues.']}
    (ROOT/'output/open-recipes-1.10.2-release.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    ranking={'version':'1.10.2','method':'Published totals and audited indexes are indicative; unknown totals remain null.',
             'sources':sorted(sources,key=lambda r:(r['recipe_count'] is None,-(r['recipe_count'] or 0)))}
    (ROOT/'output/ranking-fuentes-1.10.2.json').write_text(json.dumps(ranking,ensure_ascii=False,indent=2),encoding='utf-8')
    page=ROOT/'estado-fuentes-mesa.html';page.write_text(page.read_text(encoding='utf-8').replace('output/ranking-fuentes-actuales-1.7.2.json','output/ranking-fuentes-1.10.2.json'),encoding='utf-8')
    print(json.dumps({'version':'1.10.2','sources':22,'new_sources_verified':6,'client_tests':94,'server_tests':66,'physical_android_test':False}))

if __name__=='__main__':main()
