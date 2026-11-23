"""Esegue epubcheck su tutti gli EPUB di test/uscita (escluso drm.epub, incompleto apposta).

Uso (dalla cartella del progetto):
    python tools/epubcheck.py percorso/di/epubcheck.jar
oppure con la variabile d'ambiente EPUBCHECK_JAR.

epubcheck si scarica da https://github.com/w3c/epubcheck/releases (serve Java 11 o più).
Esce con codice 0 se nessun file ha errori né avvisi.
"""
import glob
import os
import subprocess
import sys

ESCLUSI = {"drm.epub"}  # libro "protetto" finto, usato per verificare il rifiuto dei DRM


def main():
    jar = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("EPUBCHECK_JAR")
    if not jar or not os.path.isfile(jar):
        print("Indicare il percorso di epubcheck.jar (argomento o EPUBCHECK_JAR).")
        return 2
    file = sorted(f for f in glob.glob(os.path.join("test", "uscita", "*.epub"))
                  if os.path.basename(f) not in ESCLUSI)
    if not file:
        print("Nessun EPUB in test/uscita: eseguire prima i test.")
        return 2
    falliti = 0
    for f in file:
        r = subprocess.run(["java", "-Duser.language=en", "-jar", jar, f],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        uscita = r.stdout + r.stderr
        pulito = r.returncode == 0 and "No errors or warnings detected" in uscita
        print(("ok    " if pulito else "ERRORE ") + os.path.basename(f))
        if not pulito:
            falliti += 1
            for riga in uscita.splitlines():
                if riga.startswith(("ERROR", "WARNING", "FATAL")):
                    print("      " + riga)
    print(f"\n{len(file) - falliti}/{len(file)} senza errori né avvisi")
    return 0 if falliti == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
