import pytest
import server.quality_translation as quality
from server.translation import restore_numbers

def test_measurements_are_protected_and_restored_even_if_model_converts_inside_code():
    protected={}
    encoded=quality.protect_quantities('Bake at 350 F for 20 minutes; add 1/2 cup milk.',protected)
    assert '<code data-mesa="Q0000">350 F</code>' in encoded
    translated=encoded.replace('350 F','175 C').replace('20 minutes','20 minutos').replace('1/2 cup','120 ml')
    value=quality.restore_quantities(translated,protected)
    assert '350 F' in value and '20 minutos' in value and '1/2 taza' in value
    assert restore_numbers('350 F 20 minutes 1/2 cup',value)==value

def test_missing_repeated_reordered_and_cross_field_quantities_are_rejected():
    protected={};encoded=quality.protect_quantities('2 eggs and 350 F',protected)
    with pytest.raises(ValueError): quality.restore_quantities(encoded.replace('Q0000','Q0001'),protected)
    with pytest.raises(ValueError): quality.restore_quantities(encoded+encoded,protected)
    with pytest.raises(ValueError): quality.restore_quantities(encoded,{'Q0001':protected['Q0001']})

def test_bare_item_counts_can_lose_markup_but_measured_units_cannot():
    assert quality.restore_quantities('apio (1 rama)',{'Q0000':'1'})=='apio (1 rama)'
    with pytest.raises(ValueError): quality.restore_quantities('1 kg de apio',{'Q0000':'1'})
    with pytest.raises(ValueError): quality.restore_quantities('350 C',{'Q0000':'350 F'})
    with pytest.raises(ValueError): quality.restore_quantities('<code data-mesa="Q0000">1 kg de patatas</code>',{'Q0000':'1 kg'})

def test_field_boundaries_are_complete_and_single_field_may_have_no_header():
    assert quality.parse_fields('[MESA_FIELD_0000]\nPan\n[MESA_FIELD_0001]\n2 huevos',[0,1])==['Pan','2 huevos']
    assert quality.parse_fields('Pan',[0])==['Pan']
    with pytest.raises(ValueError): quality.parse_fields('[MESA_FIELD_0001]\n2 huevos',[0,1])
    with pytest.raises(ValueError): quality.parse_fields('Explanation\n[MESA_FIELD_0000]\nPan',[0])

def test_incomplete_batch_is_retried_as_complete_individual_fields(monkeypatch):
    calls=[]
    def translate(texts,source):
        calls.append(texts)
        if len(texts)>1: raise ValueError('missing field')
        return ('Pan' if texts[0]=='Bread' else '2 huevos',)
    monkeypatch.setattr(quality,'translate_group',translate)
    assert quality.translate_texts(['Bread','2 eggs'],'en')==['Pan','2 huevos']
    assert calls==[('Bread','2 eggs'),('Bread',),('2 eggs',)]

def test_dedicated_local_request_preserves_originals_and_uses_selected_model(monkeypatch):
    def request(path,body=None,**kwargs):
        assert path=='/api/chat' and body['model']=='translategemma:12b'
        assert '350 F' in body['messages'][0]['content'] and body['stream'] is False
        return {'done_reason':'stop','message':{'content':'[MESA_FIELD_0000]\nHornea a <code data-mesa="Q0000">175 C</code>.'}}
    monkeypatch.setattr(quality,'request',request)
    assert quality._translate_group(('Bake at 350 F.',),'en','translategemma:12b')==('Hornea a 350 F.',)
