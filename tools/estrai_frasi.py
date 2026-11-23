"""Estrae le frasi traducibili di Parergon e genera il modello locales/parergon.pot.

Cerca le chiamate _("...") e _.trf("...", ...) nei file Lua del plugin.
Le frasi devono essere stringhe letterali tra virgolette doppie su una riga.

Uso:  python tools/estrai_frasi.py          (scrive il modello)
      python tools/estrai_frasi.py --check  (verifica che ogni .po copra tutte le frasi)
"""
import glob
import os
import re
import sys

QUI = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.join(QUI, "..", "parergon.koplugin")
LOCALES = os.path.join(PLUGIN, "locales")

CHIAMATA = re.compile(r'_(?:\.trf)?\(\s*"((?:[^"\\]|\\.)*)"')


def frasi():
    trovate = {}
    for percorso in sorted(glob.glob(os.path.join(PLUGIN, "**", "*.lua"), recursive=True)):
        if os.path.basename(percorso) == "_meta.lua":
            continue  # _meta.lua usa il gettext di KOReader
        rel = os.path.relpath(percorso, PLUGIN).replace(os.sep, "/")
        with open(percorso, encoding="utf-8") as f:
            for n, riga in enumerate(f, 1):
                for m in CHIAMATA.finditer(riga):
                    trovate.setdefault(m.group(1), []).append(f"{rel}:{n}")
    return trovate


def leggi_po(percorso):
    voci, msgid, msgstr, campo = {}, None, None, None
    with open(percorso, encoding="utf-8") as f:
        for riga in f:
            riga = riga.rstrip("\n")
            if riga.startswith("msgid "):
                if msgid is not None:
                    voci[msgid] = msgstr
                msgid, msgstr, campo = riga[7:-1], "", "id"
            elif riga.startswith("msgstr "):
                msgstr, campo = riga[8:-1], "str"
            elif riga.startswith('"') and campo:
                if campo == "id":
                    msgid += riga[1:-1]
                else:
                    msgstr += riga[1:-1]
    if msgid is not None:
        voci[msgid] = msgstr
    voci.pop("", None)
    return voci


def scrivi_pot(trovate):
    righe = [
        "# Parergon — modello delle traduzioni.",
        "# Generato da tools/estrai_frasi.py: non modificare a mano.",
        'msgid ""',
        'msgstr ""',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        "",
    ]
    for msgid, dove in trovate.items():
        righe.append("#: " + " ".join(dove))
        righe.append(f'msgid "{msgid}"')
        righe.append('msgstr ""')
        righe.append("")
    with open(os.path.join(LOCALES, "parergon.pot"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(righe))
    print(f"{len(trovate)} frasi scritte in locales/parergon.pot")


def controlla_ombre():
    """Nei file che importano la traduzione come `_`, nessuna variabile deve chiamarsi `_`
    (per esempio `for _, x in ipairs(...)`): nasconderebbe la funzione di traduzione."""
    ok = True
    vietato = re.compile(r"\bfor\s+_\s*[,=]|\blocal\s+_\s*,|function\s*\(\s*_\s*[,)]")
    for percorso in sorted(glob.glob(os.path.join(PLUGIN, "**", "*.lua"), recursive=True)):
        with open(percorso, encoding="utf-8") as f:
            righe = f.readlines()
        if not any('require("parergon/i18n")' in r and r.strip().startswith("local _ ") for r in righe):
            continue
        for n, riga in enumerate(righe, 1):
            if vietato.search(riga):
                rel = os.path.relpath(percorso, PLUGIN)
                print(f"{rel}:{n}: la variabile `_` nasconde la funzione di traduzione")
                ok = False
    return ok


def controlla(trovate):
    ok = controlla_ombre()
    for po in sorted(glob.glob(os.path.join(LOCALES, "*.po"))):
        voci = leggi_po(po)
        mancanti = [m for m in trovate if not voci.get(m)]
        inutili = [m for m in voci if m not in trovate]
        nome = os.path.basename(po)
        for m in mancanti:
            print(f"{nome}: manca la traduzione di: {m}")
        for m in inutili:
            print(f"{nome}: voce non più usata: {m}")
        ok = ok and not mancanti and not inutili
        print(f"{nome}: {len(trovate) - len(mancanti)}/{len(trovate)} frasi tradotte")
    return ok


if __name__ == "__main__":
    t = frasi()
    if "--check" in sys.argv:
        sys.exit(0 if controlla(t) else 1)
    os.makedirs(LOCALES, exist_ok=True)
    scrivi_pot(t)
