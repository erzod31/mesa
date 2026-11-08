"""Prepare a workspace-local ATL SDK for the VS 2022 14.44 compiler.

Payload URLs and hashes are from Microsoft's Visual Studio package catalog.
Prefer installing Visual Studio's C++ ATL component on other machines.
"""
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

import httpx

PACKAGES = {
    "Headers": "f8d375a254b6cfdbe0e7dc4fe7342d6212052068eb6394070dd932c815adb500",
    "X64": "6dd0b7f8079c654db2b8fdaebc74900e8418b5204914a77bde93a5b01ac0998c",
}


def main():
    root = (Path(__file__).resolve().parent.parent / ".tools" / "atl").resolve()
    root.mkdir(parents=True, exist_ok=True)
    for name, digest in PACKAGES.items():
        filename = f"Microsoft.VC.14.44.17.14.ATL.{name}.base.vsix"
        url = (
            "https://download.visualstudio.microsoft.com/download/pr/"
            f"d2fa077f-a814-4fb2-b903-1fca7658d17e/{digest}/{filename}"
        )
        response = httpx.get(url, timeout=30)
        response.raise_for_status()
        if sha256(response.content).hexdigest() != digest:
            raise ValueError("El paquete ATL no coincide con el catálogo oficial.")
        with ZipFile(BytesIO(response.content)) as archive:
            for member in archive.infolist():
                destination = (root / member.filename).resolve()
                if not destination.is_relative_to(root):
                    raise ValueError("Ruta inesperada en el paquete ATL.")
            archive.extractall(root)
        print(f"ATL {name} preparado y verificado dentro del proyecto.")


if __name__ == "__main__":
    main()
