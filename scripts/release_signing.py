"""Offline release metadata signing; private key never enters runtime payloads."""
import base64
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from server.windows_updates import canonical

ROOT = Path(__file__).resolve().parents[1]


def sign_android(metadata):
    release = {k: v for k, v in metadata.items() if k != 'signature'}
    release.update(product='com.mesa.mesa', platform='android', architecture='arm64-v8a')
    key = serialization.load_pem_private_key(
        (ROOT/'.tools/signing/windows-updates-ed25519.pem').read_bytes(), password=None)
    return {**release, 'signature': base64.b64encode(key.sign(canonical(release))).decode()}
