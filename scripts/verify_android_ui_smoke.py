"""Exercise only the dedicated MesaTest emulator with synthetic recipe data."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'output/auditoria-mesa-2026-10-12'
ADB = ROOT / '.tools/android/platform-tools/adb.exe'
SERIAL = 'emulator-5582'
VERSION, CODE_TEXT = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)',
    (ROOT / 'client/pubspec.yaml').read_text(encoding='utf-8'), re.M).groups()
CODE = int(CODE_TEXT)
events = []


def adb(*args):
    result = subprocess.run([str(ADB), '-s', SERIAL, *args], capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=40, check=True)
    events.append(dict(command=['adb', '-s', SERIAL, *args], result=result.stdout.strip()))
    return result.stdout.strip()


def screen(name):
    adb('shell', 'uiautomator', 'dump', '/sdcard/mesa-ui-smoke.xml')
    target = LAB / '03_observacion_ui' / (name + '.xml')
    adb('pull', '/sdcard/mesa-ui-smoke.xml', str(target))
    return list(ET.parse(target).iter('node'))


def label(node):
    return node.get('text', '') or node.get('content-desc', '')


def bounds(node):
    return list(map(int, re.findall(r'\d+', node.get('bounds', ''))))


def match(nodes, value):
    candidates = []
    for node in nodes:
        if (label(node) == value or label(node).startswith(value + '\n')) and len(bounds(node)) == 4:
            x1, y1, x2, y2 = bounds(node)
            if x2 > x1 and y2 > y1:
                candidates.append(node)
    # Flutter's route semantics may repeat a button's name across the entire
    # screen. Prefer the actual interactive control, then its smallest bounds.
    return min(candidates, key=lambda n: (
        0 if n.get('class') == 'android.widget.Button' else
        2 if n.get('class') == 'android.widget.EditText' else 1,
        (bounds(n)[2]-bounds(n)[0])*(bounds(n)[3]-bounds(n)[1]),
    )) if candidates else None


def tap(node):
    x1, y1, x2, y2 = bounds(node)
    adb('shell', 'input', 'tap', str((x1 + x2)//2), str((y1 + y2)//2))
    time.sleep(.5)


def click(value, name, scroll=False):
    for attempt in range(8 if scroll else 1):
        nodes = screen(name + '-' + str(attempt))
        node = match(nodes, value)
        if node is not None:
            tap(node)
            return
        if scroll:
            regions = [bounds(n) for n in nodes if n.get('scrollable') == 'true'
                       and n.get('package') == 'com.mesa.mesa' and len(bounds(n)) == 4]
            assert regions, 'No observed scrollable region for ' + value
            x1, y1, x2, y2 = max(regions, key=lambda r:r[3]-r[1])
            x = int(x1+(x2-x1)*.15)
            adb('shell', 'input', 'swipe', str(x), str(int(y1+(y2-y1)*.75)),
                str(x), str(int(y1+(y2-y1)*.25)), '350')
    raise AssertionError('Missing reachable control: ' + value)


def screenshot(name):
    adb('shell', 'screencap', '-p', '/sdcard/mesa-ui-smoke.png')
    adb('pull', '/sdcard/mesa-ui-smoke.png', str(LAB / '03_observacion_ui' / (name + '.png')))


def type_field(index, value):
    nodes = screen('android-field-' + str(index))
    fields = [n for n in nodes if n.get('class') == 'android.widget.EditText']
    assert len(fields) > index, 'Editor field absent'
    tap(fields[index])
    adb('shell', 'input', 'text', value.replace(' ', '%s'))
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(.3)


def main():
    assert adb('shell', 'getprop', 'ro.kernel.qemu') == '1', 'Only a test emulator is allowed'
    assert adb('shell','getprop','ro.boot.qemu.avd_name') == 'MesaTest', 'Only the dedicated MesaTest AVD is allowed'
    identity = adb('shell', 'dumpsys', 'package', 'com.mesa.mesa')
    assert 'versionCode=' + str(CODE) + ' ' in identity and 'versionName=' + VERSION in identity
    adb('shell', 'am', 'force-stop', 'com.mesa.mesa')
    adb('shell', 'am', 'start', '-W', '-n', 'com.mesa.mesa/.MainActivity')
    time.sleep(2)
    nodes = screen('android-final-home')
    assert match(nodes, 'Tu recetario') is not None and match(nodes, 'Recetas') is not None
    screenshot('android-final-home')
    click('Importar enlace o texto', 'android-import')
    nodes = screen('android-import-dialog')
    assert match(nodes, 'Importar receta') is not None
    click('Cancelar', 'android-import-cancel')
    click('Nueva receta', 'android-create')
    title = 'MESA_AUDIT_' + str(CODE) + '_' + datetime.now(timezone.utc).strftime('%H%M%S')
    type_field(0, title)
    type_field(1, '2 huevos')
    type_field(2, 'Cocer durante 5 minutos.')
    screenshot('android-final-editor')
    click('Guardar', 'android-save')
    time.sleep(1)
    # Search the newly saved fixture: older lab recipes remain intact and the
    # visible dock reduces the scrollable viewport on this compact emulator.
    type_field(0, title)
    nodes = screen('android-final-saved')
    if match(nodes, title) is None:
        # Scroll towards the recipe cards; the library itself remains the active surface.
        click(title, 'android-saved-scroll', scroll=True)
    else:
        tap(match(nodes, title))
    time.sleep(.5)
    nodes = screen('android-final-recipe')
    assert any('2 huevos' in label(n) for n in nodes), 'Ingredient amount missing in native recipe'
    screenshot('android-final-recipe')
    click('Más acciones', 'android-actions')
    nodes = screen('android-actions-sheet')
    assert any('Acciones de receta' in label(n) for n in nodes)
    assert any('Planificar' in label(n) for n in nodes)
    screenshot('android-final-actions')
    click('Cerrar menú', 'android-actions-close')
    click('Paso a paso', 'android-cook')
    nodes = screen('android-final-cooking')
    assert any('PASO 1 DE 1' in label(n).upper() for n in nodes)
    assert any('cocer durante 5 minutos.' in label(n).casefold() for n in nodes)
    assert not any('No se han podido activar las notificaciones' in label(n) for n in nodes)
    screenshot('android-final-cooking')
    adb('shell', 'am', 'force-stop', 'com.mesa.mesa')
    adb('shell', 'am', 'start', '-W', '-n', 'com.mesa.mesa/.MainActivity')
    time.sleep(1)
    # Older synthetic runs remain in the laboratory. Search rather than assume
    # the newest recipe is the first sorted card after a process restart.
    type_field(0, title)
    nodes = screen('android-final-restart')
    assert any(title in label(n) for n in nodes), 'Synthetic recipe did not survive native restart'
    screenshot('android-final-restart')
    for value, expected in [('Semana', 'Menú semanal'), ('Compra', 'Lista de compra'), ('Mi espacio', 'Familia y conexión')]:
        click(value, 'android-nav-' + value.replace(' ', '-'))
        nodes = screen('android-final-' + value.replace(' ', '-'))
        assert any(expected in label(n) for n in nodes)
        screenshot('android-final-' + value.replace(' ', '-'))
    click('Recetas', 'android-return-to-recipes')
    nodes = screen('android-final-tab-state')
    assert any(title == n.get('text') for n in nodes if n.get('class') == 'android.widget.EditText'), 'Search was lost after tab navigation'
    screenshot('android-final-tab-state')
    pid = adb('shell', 'pidof', 'com.mesa.mesa')
    assert pid and pid.isdigit()
    logs = adb('logcat', '-d', '--pid=' + pid)
    (LAB / '09_validacion/android-final-process.log').write_text(logs, encoding='utf-8')
    assert 'FATAL EXCEPTION' not in logs and 'Unhandled Exception' not in logs
    result = dict(status='APROBADO', version=VERSION + '+' + str(CODE), entrypoint='lib/main.dart',
                  emulator='MesaTest Android API 36 x86_64', serial=SERIAL, build_mode='release',
                  apk_sha256=hashlib.sha256((LAB / ('08_reconstruccion/Mesa-Android-' + VERSION + '-' + str(CODE) + '-x64-emulator.apk')).read_bytes()).hexdigest(),
                  synthetic_recipe=title, create_save=True, amounts_visible=True, cooking=True,
                  native_process_restart_persistence=True, four_destinations=True,
                  notifications_initialized=True,
                  import_dialog=True, adaptive_action_sheet=True, search_after_tab_navigation=True,
                  current_process_pid=int(pid), physical_phone=False,
                  limits='Same production entrypoint, separate x86_64 binary. No physical ARM64 installation, external catalogue/translation, family sync or installer flow tested here.',
                  actions=events)
    (LAB / '09_validacion/android-native-smoke.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    (LAB / ('09_validacion/android-native-smoke-' + VERSION + '-' + str(CODE) + '.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k != 'actions'}, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        (LAB / '09_validacion/android-native-smoke-failure.json').write_text(
            json.dumps(dict(status='FALLIDO', error=str(error), actions=events), ensure_ascii=False, indent=2),
            encoding='utf-8')
        raise

