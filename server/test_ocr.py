import io
import json
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from server.app import create_app
from server import ocr


def photo(size=(80, 50), mode='RGB', color='white', format='PNG'):
    buffer = io.BytesIO()
    Image.new(mode, size, color).save(buffer, format=format)
    return buffer.getvalue()


@pytest.fixture
def api(tmp_path):
    client = TestClient(create_app(tmp_path))
    token = json.loads((tmp_path/'desktop-connection.json').read_text())['token']
    client.headers['Authorization'] = 'Bearer '+token
    return client


def test_ocr_requires_authentication_before_inference(api, monkeypatch):
    monkeypatch.setattr(ocr, 'recognize_image', lambda _: pytest.fail('Unauthenticated inference'))
    api.headers.clear()
    assert api.post('/v1/ocr', content=photo()).status_code == 401


def test_ocr_upload_is_bounded_even_for_chunked_body(api):
    response = api.post('/v1/ocr', content=iter([b'x'*5_000_000, b'x'*5_000_001]))
    assert response.status_code == 413


@pytest.mark.parametrize('payload,status', [(b'',422),(b'not an image',422),(b'x'*10_000_001,413)], ids=['empty','invalid','too-large'])
def test_rejects_bad_input_without_loading_models(payload, status, monkeypatch):
    monkeypatch.setattr(ocr, '_load_engine', lambda: pytest.fail('Invalid input loaded a model'))
    with pytest.raises(ocr.OcrError) as error:
        ocr.recognize_image(payload)
    assert error.value.status == status


def test_rejects_compressed_pixel_bomb_before_loading(monkeypatch):
    monkeypatch.setattr(ocr, '_load_engine', lambda: pytest.fail('Oversized raster loaded a model'))
    with pytest.raises(ocr.OcrError) as error:
        ocr.recognize_image(photo(size=(5100,5000),mode='1',color=1))
    assert error.value.status == 413


def test_rejects_overlapping_inference():
    with ocr._gate:
        with pytest.raises(ocr.OcrError) as error:
            ocr.recognize_image(photo())
    assert error.value.status == 429


def test_image_orientation_and_transparency():
    assert ocr._decode(photo(mode='RGBA',color=(0,0,0,0))).min() == 255
    image=Image.new('RGB',(80,50),'white')
    exif=Image.Exif(); exif[274]=6
    buffer=io.BytesIO(); image.save(buffer,format='JPEG',exif=exif)
    assert ocr._decode(buffer.getvalue()).shape == (80,50)


def test_ocr_text_keeps_order_quantities_and_attribution_without_saving_photo(api, monkeypatch):
    text='Tortilla\n2 huevos\n250 g de patatas\n1. Batir.'
    monkeypatch.setattr(ocr, '_load_engine', lambda: SimpleNamespace(ocr=lambda gray: SimpleNamespace(text=text)))
    before={p.name for p in api.app.state.root.iterdir()}
    response=api.post('/v1/ocr',content=photo(),headers={'Content-Type':'application/octet-stream'})
    assert response.status_code==200
    assert response.json()['text']==text
    assert response.json()['engine']=='indra-ocr'
    assert 'LICENSE' in response.json()['license_url']
    assert before=={p.name for p in api.app.state.root.iterdir()}
    assert api.get('/v1/snapshot').json()['entities']==[]


def test_one_lazy_cpu_converter_reused_without_download(monkeypatch,tmp_path):
    import indra_ocr
    for name in ('det.onnx','rec.onnx','order.onnx','meta.json'):
        (tmp_path/name).write_bytes(b'test')
    monkeypatch.setenv('INDRA_OCR_MODEL_DIR',str(tmp_path))
    monkeypatch.setattr(ocr,'_engine',None)
    monkeypatch.setattr(ocr,'_loaded_path',None)
    calls=[]
    def load(**options):
        calls.append(options)
        return SimpleNamespace(ocr=lambda gray: SimpleNamespace(text='2 huevos'))
    monkeypatch.setattr(indra_ocr,'load',load)
    assert ocr.recognize_image(photo())['text']=='2 huevos'
    assert ocr.recognize_image(photo())['text']=='2 huevos'
    assert len(calls)==1
    assert calls[0]['providers']==['CPUExecutionProvider']
    assert calls[0]['path']==tmp_path
    assert calls[0]['threads']<=4 and calls[0]['math'] is False


def test_missing_models_produces_actionable_error(monkeypatch,tmp_path):
    monkeypatch.setenv('INDRA_OCR_MODEL_DIR',str(tmp_path))
    monkeypatch.setattr(ocr,'_engine',None)
    with pytest.raises(ocr.OcrError) as error:
        ocr.recognize_image(photo())
    assert error.value.status==503
