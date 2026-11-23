# Parergon — stato del progetto

Ultimo aggiornamento: **23/11/2026**.

**23/11/2026: il plugin è stato rinominato da Marginalia a Parergon**, perché il nome era già
usato da due plugin KOReader. Sono cambiati la cartella `parergon.koplugin`, le impostazioni
(`parergon_*`), l'azione `parergon_annotations`, le classi CSS (`parergon-`), i file aggiunti
nell'EPUB (`parergon.css`, `parergon-notes.xhtml`, ...) e `locales/parergon.pot`. Tutti i test
passano. **Sul Kindle** va tolto `D:\koreader\plugins\marginalia.koplugin` e copiato
`parergon.koplugin`: le impostazioni di prova di Marginalia non vengono riprese.

## Fasi completate e verificate sul Kindle (KOReader v2026.07.2, con SimpleUI)
| Fase | Contenuto | Documento |
|---|---|---|
| 1 | Analisi del codice di KOReader, crengine e Readest | `01-analisi.md` |
| 2 | Prototipo di analisi: annotazione → file e punto dell'XHTML | `02-prototipo.md` |
| 3 | Copia `Titolo (annotato).epub` con evidenziazioni e sottolineature (4 forme, colori calibrati per e-ink) | `04-fase3.md` |
| 4 | Note nel testo `[…]` (corsivo opzionale) oppure note a comparsa con richiamo `[1]` sulla riga e pagina «Note del lettore» | `05-fase4.md` |
| 5 | Indice personale per temi (`#tema`, `#tema/sottotema`), ramo nella TOC (nav e ncx), nota di lettura nel frontespizio | `06-fase5.md` |

Tutte le decisioni prese sono in `03-decisioni.md`: licenza AGPL-3.0, nome Parergon,
interfaccia in inglese con traduzione italiana, convenzione `#tema` / `# Titolo`,
suffisso «(annotato)», identificatore derivato e altre.

## Test (tutti superati a questa data)
```
python test/crea_epub.py && python test/crea_epub.py --store && python test/crea_epub2.py
luajit test/esegui.lua           # 188 verifiche
luajit test/esegui_fase3.lua     #  86
luajit test/esegui_fase4.lua     # 104
luajit test/esegui_fase5.lua     #  88
luajit test/simula_koreader.lua  # interfaccia completa con finti moduli KOReader
python tools/estrai_frasi.py --check   # traduzione italiana: 155/155
python tools/epubcheck.py <percorso di epubcheck.jar>   # 11/11 senza errori né avvisi
```
Servono LuaJIT 2.1 (`luajit` nel PATH), Python 3 e, per epubcheck, Java.

## Da fare (prossima sessione)
**Per riprendere (fine della sessione del 23/11/2026):**
- ~~copiare sul Kindle i cinque file del punto 7 e ricreare la copia di «La scuola inclusiva
  ha fallito»~~: fatto, i numeri tornano (resta da contare a vista le 47 voci dell'indice);
- ~~togliere dal Kindle i libri di prova~~: li ha tolti l'utente il 23/11/2026, con le loro
  cartelle `.sdr`. Si possono ricreare da `test/uscita/`;
- provare un passo su più paragrafi in un altro libro (punto 5);
- ~~preparare la pubblicazione~~: il 23/11/2026 è stato pubblicato il repository
  https://github.com/antonio-vigilante/parergon (ramo `main`, tag `v1.0.0`). I commit usano
  l'indirizzo noreply di GitHub, impostato solo per questo repository. Il pacchetto si crea con
  `python tools/pacchetto.py` in `dist/`. Per ogni nuova versione: aggiornare `version` in
  `_meta.lua` e `CHANGELOG.md`, creare il tag `vX.Y.Z`, poi una release su GitHub con lo zip.

1. ~~**Sotto-temi più leggibili**~~ — fatto il 23/11/2026: «arte greca» al posto di
   «arte-greca» (vedi `06-fase5.md`).
2. ~~**Opzione per il secondo livello nella TOC**~~: fatto il 23/11/2026 (*Sub-themes in
   the table of contents*, spenta di default). Verificato sul Kindle il 23/11/2026: la TOC
   mostra i sotto-temi sotto i loro temi.
3. ~~**Prova della finestrella**~~: verificata sul Kindle il 23/11/2026. Con *Impostazioni →
   Tocchi e gesti → Collegamenti → Show footnotes in popup* attivo (è spento per default), la
   nota compare in fondo alla pagina, anche nei libri EPUB 2 senza `epub:type`. All'utente
   va bene così. Il README deve spiegare come attivare l'opzione.
4. ~~**epubcheck**~~: fatto il 23/11/2026 con epubcheck 5.4.0 (Java 25 già installato). Le copie
   EPUB 3 erano già valide. Per i libri EPUB 2 sono state corrette le pagine aggiunte e i
   richiami (vedi `05-fase4.md`). La finestrella funziona anche negli EPUB 2 (verificato sul Kindle).
5. ~~**Sottolineature che attraversano più paragrafi**~~: fatto il 23/11/2026 (vedi
   `04-fase3.md`). Restano saltati i passi fra capitoli diversi (file diversi).
   Da provare sul Kindle: un passo su due o tre paragrafi di un libro vero.
6. ~~**README**~~: fatto il 23/11/2026, in due lingue: `README.md` (inglese) e `README.it.md`
   (italiano), collegati fra loro. Contengono installazione per dispositivo, uso,
   finestrella delle note, temi e indice, limiti noti, licenza. Va aggiornato insieme
   alle funzioni.
7. ~~**Prova su un libro reale**~~: fatta il 23/11/2026 con «La scuola inclusiva ha fallito»
   (sul Kindle), vedi `03-decisioni.md`. Ne sono nate due correzioni: copie dello stesso
   passo, testo vuoto, asterisco finale nei temi (`#logica-della-carenza*`, un refuso) e
   note delle evidenziazioni contenute in un'altra. Il Kindle ha dato 46 evidenziazioni e 6
   note (riprodotto sul PC); con l'ultima correzione ci si aspettano 46 evidenziazioni, 6 note,
   1 evidenziazione contenuta con la nota conservata e 47 voci nell'indice.
   I cinque file aggiornati sono stati copiati sul Kindle il 23/11/2026. La copia ricreata dà
   46 evidenziazioni scritte, 6 note a comparsa, 1 evidenziazione contenuta in un'altra e
   20 saltate, cioè 67 su 67: risultato **verificato**. Resta da confermare a vista che
   l'indice abbia 47 voci.

## Note pratiche
- Il Kindle, collegato al PC, è l'unità `D:`. I libri stanno in `D:\koreader\libri`, i
  plugin in `D:\koreader\plugins`. L'utente lo scollega per ogni prova: chiedergli di
  ricollegarlo quando serve leggere qualcosa e dirgli quando può scollegarlo.
- I file di prova da copiare sul dispositivo sono in `test/uscita/`.
