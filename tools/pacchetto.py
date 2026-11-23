"""Crea dist/parergon-<versione>.zip, da allegare alla release.

Lo zip contiene la sola cartella parergon.koplugin/, pronta da copiare nella
cartella plugins di KOReader. La versione si legge da _meta.lua.

    python tools/pacchetto.py
"""
import os
import re
import sys
import zipfile

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = "parergon.koplugin"


def versione():
    with open(os.path.join(RADICE, PLUGIN, "_meta.lua"), encoding="utf-8") as f:
        m = re.search(r'version\s*=\s*"([^"]+)"', f.read())
    if not m:
        sys.exit("versione non trovata in _meta.lua")
    return m.group(1)


def main():
    v = versione()
    os.makedirs(os.path.join(RADICE, "dist"), exist_ok=True)
    dest = os.path.join(RADICE, "dist", "parergon-%s.zip" % v)
    n = 0
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for cartella, sotto, file in os.walk(os.path.join(RADICE, PLUGIN)):
            sotto[:] = sorted(d for d in sotto if not d.startswith("."))
            for nome in sorted(file):
                if nome.startswith("."):
                    continue
                pieno = os.path.join(cartella, nome)
                rel = os.path.relpath(pieno, RADICE).replace(os.sep, "/")
                z.write(pieno, rel)
                n += 1
    print("creato %s (%d file)" % (os.path.relpath(dest, RADICE), n))


if __name__ == "__main__":
    main()
