"""Install the official Android command line tools in this workspace."""
from pathlib import Path
import os
import subprocess
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / '.tools' / 'android'
SDK.mkdir(parents=True, exist_ok=True)
manager = SDK / 'cmdline-tools' / 'latest' / 'bin' / 'sdkmanager.bat'
if not manager.exists():
    doc = ET.fromstring(urllib.request.urlopen('https://dl.google.com/android/repository/repository2-1.xml').read())
    candidates = []
    for package in doc:
        if package.tag.endswith('remotePackage') and package.get('path', '').startswith('cmdline-tools;'):
            channel = next((x.get('ref') for x in package if x.tag.endswith('channelRef')), 'channel-0')
            if channel != 'channel-0':
                continue
            revision = next(x for x in package if x.tag.endswith('revision'))
            major = int(next(x.text for x in revision if x.tag.endswith('major')))
            for archive in package.iter():
                if not archive.tag.endswith('archive'):
                    continue
                host = next((x.text for x in archive if x.tag.endswith('host-os')), '')
                url = next((x.text for x in archive.iter() if x.tag.endswith('url')), '')
                if host == 'windows' and url:
                    candidates.append((major, url))
    url = max(candidates)[1]
    archive_path = ROOT / '.tools' / 'android-tools.zip'
    print('Downloading official Android tools:', url, flush=True)
    urllib.request.urlretrieve('https://dl.google.com/android/repository/' + url, archive_path)
    with zipfile.ZipFile(archive_path) as archive:
        archive.extractall(SDK / 'cmdline-tools' / 'latest-temp')
    (SDK / 'cmdline-tools' / 'latest-temp' / 'cmdline-tools').rename(SDK / 'cmdline-tools' / 'latest')

env = os.environ.copy()
env['ANDROID_HOME'] = str(SDK)
env['ANDROID_USER_HOME'] = str(ROOT / '.tools' / 'android-user')
env['GRADLE_USER_HOME'] = str(ROOT / '.tools' / 'gradle')
android = SDK / 'cmdline-tools' / 'latest' / 'bin' / 'android.exe'
args = [str(android), '--no-metrics', '--sdk=' + str(SDK), 'sdk', 'install']
for package in ('platform-tools', 'platforms;android-36', 'platforms;android-35', 'build-tools;36.0.0', 'ndk;28.2.13676358', 'cmake;3.22.1'):
    subprocess.run(args + [package], text=True, env=env, check=True)
if not (SDK / 'platforms' / 'android-36' / 'android.jar').exists():
    raise RuntimeError('Android platform installation did not complete.')
print('Android SDK ready:', SDK, flush=True)
