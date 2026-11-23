"""Costruisce l'EPUB di prova a partire dalla cartella test/libro-prova.

Uso:  python test/crea_epub.py            -> test/libro-prova.epub (deflate)
      python test/crea_epub.py --store    -> test/libro-prova-store.epub (tutto non compresso)

Il file mimetype è sempre la prima voce, non compresso e senza extra field,
come richiesto dalle specifiche OCF.
"""
import os
import sys
import zipfile

QUI = os.path.dirname(os.path.abspath(__file__))
SORGENTE = os.path.join(QUI, "libro-prova")


def crea(destinazione, compressione):
    with zipfile.ZipFile(destinazione, "w") as z:
        info = zipfile.ZipInfo("mimetype", date_time=(2026, 11, 22, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED
        z.writestr(info, b"application/epub+zip")
        voci = []
        for radice, _, files in os.walk(SORGENTE):
            for nome in files:
                completo = os.path.join(radice, nome)
                interno = os.path.relpath(completo, SORGENTE).replace(os.sep, "/")
                if interno != "mimetype":
                    voci.append((interno, completo))
        for interno, completo in sorted(voci):
            with open(completo, "rb") as f:
                dati = f.read()
            info = zipfile.ZipInfo(interno, date_time=(2026, 11, 22, 0, 0, 0))
            info.compress_type = compressione
            z.writestr(info, dati)
    print("creato", destinazione)


if __name__ == "__main__":
    if "--store" in sys.argv:
        crea(os.path.join(QUI, "libro-prova-store.epub"), zipfile.ZIP_STORED)
    else:
        crea(os.path.join(QUI, "libro-prova.epub"), zipfile.ZIP_DEFLATED)
