"""Variante EPUB 2 del libro di prova: test/libro-prova-epub2/ e test/libro-prova-epub2.epub.

Deriva da test/libro-prova (da creare prima con crea_epub.py): pacchetto 2.0 senza nav,
XHTML 1.1 (DOCTYPE, solo xml:lang, <div> al posto di <section> e <aside>, niente epub:type).
Serve a verificare che le copie dei libri EPUB 2 restino valide anche per epubcheck.

Uso (dalla cartella del progetto):
    python test/crea_epub2.py
"""
import os
import re
import shutil
import zipfile

SRC = os.path.join("test", "libro-prova")
DEST = os.path.join("test", "libro-prova-epub2")
DOCTYPE = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'


def main():
    if os.path.exists(DEST):
        shutil.rmtree(DEST)
    shutil.copytree(SRC, DEST)
    os.remove(os.path.join(DEST, "OEBPS", "nav.xhtml"))

    opf_p = os.path.join(DEST, "OEBPS", "content.opf")
    opf = open(opf_p, encoding="utf-8").read()
    opf = opf.replace('version="3.0"', 'version="2.0"', 1)
    opf = opf.replace(' xml:lang="it"', "", 1)  # in EPUB 2 <package> non ha xml:lang
    opf = re.sub(r'\s*<item id="nav"[^>]*/>', "", opf)
    opf = re.sub(r'\s*<meta property="dcterms:modified">[^<]*</meta>', "", opf)
    opf = opf.replace(' properties="cover-image"', "")
    opf = opf.replace("<dc:title>Libro di prova per Parergon</dc:title>",
                      "<dc:title>Libro di prova EPUB 2</dc:title>")
    open(opf_p, "w", encoding="utf-8", newline="").write(opf)

    cartella = os.path.join(DEST, "OEBPS", "testo")
    for nome in sorted(os.listdir(cartella)):
        p = os.path.join(cartella, nome)
        s = open(p, encoding="utf-8").read()
        s = s.replace("<!DOCTYPE html>", DOCTYPE)
        s = s.replace(' xmlns:epub="http://www.idpf.org/2007/ops"', "")
        s = re.sub(r' epub:type="[^"]*"', "", s)
        s = re.sub(r' lang="[^"]*"', "", s)
        s = re.sub(r"<(/?)(section|aside)\b", r"<\1div", s)
        open(p, "w", encoding="utf-8", newline="").write(s)

    with zipfile.ZipFile(DEST + ".epub", "w") as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        for radice, cartelle, files in os.walk(DEST):
            cartelle.sort()
            for f in sorted(files):
                if f == "mimetype":
                    continue
                pieno = os.path.join(radice, f)
                z.write(pieno, os.path.relpath(pieno, DEST).replace(os.sep, "/"),
                        compress_type=zipfile.ZIP_STORED)
    print("creato " + DEST + ".epub")


if __name__ == "__main__":
    main()
