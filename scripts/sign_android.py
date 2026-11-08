"""Generate a private family signing key once. Do not commit or lose this key."""
from pathlib import Path
import secrets
import subprocess

root = Path(__file__).resolve().parents[1]
directory = root / '.tools' / 'signing'
directory.mkdir(parents=True, exist_ok=True)
password_file = directory / 'password'
key = directory / 'mesa-family.jks'
if not password_file.exists():
    password_file.write_text(secrets.token_urlsafe(36), encoding='utf-8')
password = password_file.read_text(encoding='utf-8')
if not key.exists():
    subprocess.run([r'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe', '-genkeypair', '-keystore', str(key), '-storepass:file', str(password_file), '-keypass:file', str(password_file), '-alias', 'mesa', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-dname', 'CN=Mesa Familiar, O=Mesa'], check=True)
(root / 'client' / 'android' / 'key.properties').write_text(f'storeFile={key.as_posix()}\nstorePassword={password}\nkeyPassword={password}\nkeyAlias=mesa\n', encoding='utf-8')
print('Firma familiar preparada. Conserva una copia privada de .tools/signing.')
