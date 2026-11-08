"""Regression coverage for actual translation failures; no model/network in unit tests."""
from copy import deepcopy
import pytest
import server.translation as tr
from server.test_api import api, recipe

@pytest.fixture(autouse=True)
def no_models_or_network(monkeypatch,tmp_path):
    import server.quality_translation as quality
    import server.translation_cache as cache
    monkeypatch.setattr(quality, 'available', lambda: False)
    monkeypatch.setattr(tr,'model_identity',lambda source,target:f'fixture-{source}-{target}')
    monkeypatch.setattr(cache,'PATH',tmp_path/'translations.sqlite')

@pytest.mark.parametrize('original,translated,expected', [
    ('1.5 cups', '1,5 tazas', '1.5 tazas'),
    ('1/2 cup', '½ taza', '1/2 taza'),
    ('350 F for 20 minutes', '350 F durante 20 minutos', '350 F durante 20 minutos'),
])
def test_numeric_format_is_restored_without_fragmenting(original, translated, expected):
    assert tr.restore_numbers(original, translated) == expected

@pytest.mark.parametrize('translated', ['3 huevos', '2 huevos durante 10 minutos', 'huevos'])
def test_changed_or_invented_quantities_are_rejected(translated):
    with pytest.raises(ValueError): tr.restore_numbers('2 eggs', translated)


def test_opus_german_spelled_integer_retains_exact_quantity():
    assert tr.restore_numbers('2 Eier mischen.', 'Mezclar dos huevos.', allow_words=True) == 'Mezclar 2 huevos.'
    assert tr.restore_numbers('3 Eier, 10 Minuten.', 'Tres huevos, 10 minutos.', allow_words=True) == '3 huevos, 10 minutos.'
    with pytest.raises(ValueError):
        tr.restore_numbers('2 Eier mischen.', 'Mezclar dos huevos.')


@pytest.mark.parametrize('text', ['Mezclar tres huevos.', 'Mezclar dos y medio huevos.', 'Mezclar dos mil huevos.', 'Mezclar un huevo.', 'Mezclar dos huevos, cinco minutos.', 'Mezclar dos coma cinco huevos.'])
def test_spelled_quantities_never_repair_changed_ambiguous_or_added_values(text):
    with pytest.raises(ValueError):
        tr.restore_numbers('2 Eier mischen.', text, allow_words=True)


def test_german_endpoint_accepts_real_provider_spelling_without_saving(api, monkeypatch):
    monkeypatch.setattr(tr, 'translate_batch', lambda texts, source: [t.replace('2 Eier mischen.', 'Mezclar dos huevos.').replace('2 Eier', '2 huevos') for t in texts])
    original = {**recipe('Test'), 'language': 'de', 'ingredients': ['2 Eier'], 'steps': ['2 Eier mischen.']}
    response = api.post('/v1/translate-recipe', json={'recipe': original, 'source': 'de'})
    assert response.status_code == 200, response.text
    assert response.json()['steps'] == ['Mezclar 2 huevos.']
    assert response.json()['original']['steps'] == original['steps']
    assert api.get('/v1/snapshot').json()['entities'] == []


def test_language_contract_normalizes_bcp47_and_explains_unsupported(api,monkeypatch):
    monkeypatch.setattr(tr,'translate_texts',lambda texts,source:texts)
    value={**recipe('Test'),'language':'de-DE'}
    assert api.post('/v1/translate-recipe',json={'recipe':value,'source':'de-DE'}).status_code==200
    bad=api.post('/v1/translate-recipe',json={'recipe':value,'source':'ja'})
    assert bad.status_code==422 and 'Idioma no compatible' in bad.text and 'se conserva el original' in bad.text

def test_culinary_techniques_and_units_are_not_left_to_ambiguous_models(monkeypatch):
    monkeypatch.setattr(tr, 'translate_batch', lambda texts, source: [
        t.replace('les oignons puis', 'las cebollas y luego').replace('pendant', 'durante').replace('minutes', 'minutos').replace('sel', 'sal') for t in texts])
    result = tr.translate_texts(['Pain', '1/2 cuillère à café de sel', 'Faites revenir les oignons puis laissez mijoter pendant 20 minutes.'], 'fr')
    assert result == ['Pan', '1/2 cucharadita de sal', 'Rehoga las cebollas y luego deja cocer a fuego lento durante 20 minutos.']

def test_long_steps_are_complete_and_keep_blank_lines(monkeypatch):
    monkeypatch.setattr(tr, 'translate_batch', lambda texts, source: texts)
    text = ('Mix the ingredients for 20 minutes. ' * 120) + '\n\nServe.'
    assert tr.translate_texts([text, ''], 'en') == [text, '']
    assert all(len(t) <= 1800 for fixed,t in tr.text_parts(text, 'en') if not fixed)

def test_retranslation_uses_the_saved_original_and_does_not_overwrite_it(monkeypatch):
    calls = []
    def fake(texts, source):
        calls.append((texts, source)); return [t.replace('Bread','Pan').replace('Mix','Mezcla') for t in texts]
    monkeypatch.setattr(tr, 'translate_texts', fake)
    original = {**recipe('Bread'), 'steps':['Mix.'], 'language':'en', 'notes':'A family recipe.'}
    first = tr.translate_recipe(original, 'en')
    first['title'] = 'Traducción incorrecta'
    saved = deepcopy(first)
    result = tr.translate_recipe(first, 'en', force=True)
    assert calls[-1][0][0] == 'Bread' and calls[-1][0][-1] == 'A family recipe.'
    assert result['title'] == 'Pan' and result['original'] == first['original']
    assert result['translation']['revision'] == tr.REVISION and first == saved

def test_generated_spanish_notes_are_preserved(monkeypatch):
    calls = []
    monkeypatch.setattr(tr, 'translate_texts', lambda texts, source: calls.append(texts) or texts)
    value = {**recipe('Bread'), 'language':'en', 'notes':'Comprueba el rendimiento y el tiempo en la fuente.', 'origin':{'provider':'wiki-en'}}
    result = tr.translate_recipe(value, 'en')
    assert calls[0][-1] == '' and result['notes'] == value['notes']
    assert result['original']['notes_language'] == 'es'

def test_authenticated_endpoint_allows_retranslation_and_validates_original(api, monkeypatch):
    monkeypatch.setattr(tr, 'translate_texts', lambda texts, source: [t.replace('Bread','Pan') for t in texts])
    original = {**recipe('Bread'), 'language':'en', 'notes':''}
    translated = tr.translate_recipe(original, 'en')
    translated['title'] = 'Dolor'
    response = api.post('/v1/translate-recipe', json={'recipe':translated, 'source':'en', 'force':True})
    assert response.status_code == 200 and response.json()['title'] == 'Pan'
    assert api.get('/v1/snapshot').json()['entities'] == []
