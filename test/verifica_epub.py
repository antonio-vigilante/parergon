"""Verifica indipendente di un EPUB prodotto da Parergon (con la libreria standard di Python).

Controlla:
  - archivio ZIP integro (CRC di ogni voce, anche quelle copiate byte per byte);
  - mimetype prima voce, non compresso, senza extra field;
  - ogni file XHTML/OPF/NCX/XML ben formato secondo un vero parser XML;
  - ogni voce del manifest presente nell'archivio.

Uso:  python test/verifica_epub.py file.epub [altro.epub ...]
Esce con codice 1 al primo problema.
"""
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
from posixpath import dirname, join, normpath
from urllib.parse import unquote


def errore(msg):
    print("ERRORE:", msg)
    sys.exit(1)


def verifica(percorso):
    with open(percorso, "rb") as f:
        testa = f.read(30 + 8 + 20)
    if testa[:4] != b"PK\x03\x04":
        errore("intestazione ZIP assente")
    metodo, = struct.unpack("<H", testa[8:10])
    lnome, lextra = struct.unpack("<HH", testa[26:30])
    nome = testa[30:30 + lnome]
    if nome != b"mimetype" or metodo != 0 or lextra != 0:
        errore(f"mimetype non conforme (nome={nome!r}, metodo={metodo}, extra={lextra})")
    with zipfile.ZipFile(percorso) as z:
        guasto = z.testzip()
        if guasto:
            errore(f"CRC errato per {guasto}")
        if z.read("mimetype") != b"application/epub+zip":
            errore("contenuto del mimetype errato")
        nomi = set(z.namelist())
        for n in z.namelist():
            if n.endswith((".xhtml", ".html", ".opf", ".ncx", ".xml", ".svg")):
                try:
                    ET.fromstring(z.read(n))
                except ET.ParseError as e:
                    errore(f"{n} non è XML ben formato: {e}")
        cont = ET.fromstring(z.read("META-INF/container.xml"))
        ns = {"c": "urn:oasis:names:tc:opendocument:xmlns:container"}
        opf = cont.find(".//c:rootfile", ns).get("full-path")
        radice = ET.fromstring(z.read(opf))
        base = dirname(opf)
        for item in radice.iter("{http://www.idpf.org/2007/opf}item"):
            p = normpath(join(base, unquote(item.get("href"))))
            if p not in nomi:
                errore(f"voce del manifest assente nell'archivio: {p}")
        # ogni itemref dello spine deve esistere nel manifest
        ids = {i.get("id") for i in radice.iter("{http://www.idpf.org/2007/opf}item")}
        for ir in radice.iter("{http://www.idpf.org/2007/opf}itemref"):
            if ir.get("idref") not in ids:
                errore(f"itemref senza voce nel manifest: {ir.get('idref')}")
        # link interni con frammento: il file e l'id di destinazione devono esistere
        idperfile = {}
        documenti = {n: ET.fromstring(z.read(n)) for n in z.namelist() if n.endswith((".xhtml", ".html"))}
        for n, doc in documenti.items():
            idperfile[n] = {e.get("id") for e in doc.iter() if e.get("id")}
        for n, doc in documenti.items():
            for a in doc.iter("{http://www.w3.org/1999/xhtml}a"):
                href = a.get("href")
                if not href or "#" not in href or ":" in href.split("#")[0]:
                    continue
                f, frammento = href.split("#", 1)
                dest = normpath(join(dirname(n), unquote(f))) if f else n
                if dest not in idperfile:
                    errore(f"{n}: link a un file inesistente: {href}")
                if frammento not in idperfile[dest]:
                    errore(f"{n}: link a un id inesistente: {href}")
        # toc.ncx: ogni content src deve arrivare a un file (e a un id) esistente;
        # i playOrder devono essere distinti
        for n in z.namelist():
            if not n.endswith(".ncx"):
                continue
            ncx = ET.fromstring(z.read(n))
            ordini = []
            for el in ncx.iter():
                if el.tag.endswith("navPoint"):
                    ordini.append(el.get("playOrder"))
                if el.tag.endswith("content"):
                    src = el.get("src")
                    f, _, frammento = src.partition("#")
                    dest = normpath(join(dirname(n), unquote(f)))
                    if dest not in nomi:
                        errore(f"{n}: content src verso un file inesistente: {src}")
                    if frammento and frammento not in idperfile.get(dest, set()):
                        errore(f"{n}: content src verso un id inesistente: {src}")
            if len(ordini) != len(set(ordini)):
                errore(f"{n}: playOrder ripetuti")
    print("ok", percorso)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        verifica(p)
