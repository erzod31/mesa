"""Private, in-memory Indra OCR. One lazy CPU model set and bounded inference."""
import io
import os
from pathlib import Path
import threading
import time
import warnings

from PIL import Image, ImageOps, UnidentifiedImageError

MAX_IMAGE_BYTES = 10_000_000
MAX_IMAGE_PIXELS = 25_000_000
MAX_SIDE = 2400
MAX_TEXT = 100_000
MODEL_FOLDER = Path(__file__).resolve().parents[1]/'.tools/ocr/indra-v1.1.0'
MODEL_URL = 'https://huggingface.co/datalab-to/indra-ocr'
LICENSE_URL = MODEL_URL+'/blob/bd02167fdf2005a19962cc15188f8496a2c87d3b/LICENSE'
ATTRIBUTION = 'Indra OCR · Datalab · modelos sin modificar'
_gate = threading.Lock()
_engine = None
_loaded_path = None


class OcrError(Exception):
    def __init__(self, status, message):
        self.status = status
        super().__init__(message)


def _load_engine():
    global _engine, _loaded_path
    folder = Path(os.environ.get('INDRA_OCR_MODEL_DIR', MODEL_FOLDER)).resolve()
    if _engine is None or _loaded_path != folder:
        if not all((folder/name).is_file() for name in ('det.onnx','rec.onnx','order.onnx','meta.json')):
            raise OcrError(503, 'Faltan los modelos de Indra OCR en el ordenador. Actualiza Mesa o prepara sus modelos.')
        try:
            import indra_ocr
            # No runtime downloads, process pools, GPU or competing model copies.
            loaded = indra_ocr.load(path=folder, threads=min(4, os.cpu_count() or 1),
                                    mode='ocr', providers=['CPUExecutionProvider'], math=False)
        except Exception as error:
            raise OcrError(503, 'No se pudo iniciar Indra OCR en el ordenador.') from error
        _engine, _loaded_path = loaded, folder
    return _engine


def _decode(payload):
    if not payload:
        raise OcrError(422, 'Selecciona una foto con texto.')
    if len(payload) > MAX_IMAGE_BYTES:
        raise OcrError(413, 'La foto supera 10 MB.')
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(payload)) as image:
                if image.format not in ('JPEG','PNG','WEBP','BMP','TIFF'):
                    raise OcrError(415, 'Usa una foto JPEG, PNG, WebP, BMP o TIFF.')
                if image.width*image.height > MAX_IMAGE_PIXELS:
                    raise OcrError(413, 'La foto supera 25 millones de píxeles. Recorta el texto antes de leerlo.')
                image.draft('L', (MAX_SIDE, MAX_SIDE))
                upright = ImageOps.exif_transpose(image)
                # Composite transparent scans onto white rather than black.
                if upright.mode in ('RGBA','LA') or 'transparency' in upright.info:
                    rgba = upright.convert('RGBA')
                    white = Image.new('RGBA', rgba.size, 'white')
                    white.alpha_composite(rgba)
                    upright = white
                gray = upright.convert('L')
                gray.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
                import numpy as np
                return np.array(gray, dtype=np.uint8)
    except OcrError:
        raise
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
        raise OcrError(422, 'No se pudo leer la foto. Elige una imagen válida.') from error


def recognize_image(payload):
    if not _gate.acquire(blocking=False):
        raise OcrError(429, 'Mesa está leyendo otra foto. Espera a que termine y reintenta.')
    try:
        gray = _decode(payload)
        start = time.perf_counter()
        engine = _load_engine()
        try:
            page = engine.ocr(gray)
        except Exception as error:
            raise OcrError(422, 'Indra OCR no pudo leer esta foto. Prueba una imagen más clara.') from error
        text = page.text.strip()
        if len(text) > MAX_TEXT:
            raise OcrError(422, 'Hay demasiado texto. Recorta la receta y vuelve a leerla.')
        return {'engine':'indra-ocr', 'version':'1.1.2', 'text':text,
                'elapsed_ms':round((time.perf_counter()-start)*1000),
                'attribution':ATTRIBUTION, 'model_url':MODEL_URL,
                'license':'AI PUBS Open RAIL-M (modified)', 'license_url':LICENSE_URL}
    finally:
        _gate.release()
