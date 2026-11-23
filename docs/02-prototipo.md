# Fase 2 — prototipo di analisi (nessuna modifica ai libri)

## Compatibilità con le versioni di KOReader

Verificata sulla storia del repository (tag ufficiali):

| Cosa serve | Da quale versione | Conseguenza |
|---|---|---|
| `ReaderAnnotation` (`self.ui.annotation.annotations`, campi `drawer`, `color`, `note`…) | **v2024.07** (commit d8281595, 05/2024) | versione minima supportata. Con versioni più vecchie il plugin mostra un messaggio chiaro |
| `CreDocument:getDocumentFileContent`, `getTextFromXPointers`, `isXPointerInDocument` | già presenti in v2024.07 | usati per leggere i file compressi e per disambiguare |
| `cre_dom_version` nelle impostazioni del libro | già presente | serve per la corrispondenza DocFragment → file |
| `ffi/archiver` (libarchive) | **v2025.08** (commit f63c76d6, 05/2025) | **non** si può dare per scontato: lo uso solo se esiste |
| `ffi/zipwriter` | rimosso in v2025.08 | inutilizzabile come unica via |
| `ffi/zlib_h` (`compress2`, `crc32`) | dal 2020 | disponibile in tutte le versioni supportate |

### Lettura dell'EPUB (fase 2)
- La directory centrale dello zip la legge `parergon/zip.lua` (Lua puro, solo lettura).
- Le voci non compresse si leggono direttamente.
- Per le voci compresse uso `ffi/archiver` se c'è, altrimenti `document:getDocumentFileContent()`
  di crengine, che esiste in tutte le versioni.

### Scrittura (proposta per la fase 3)
Propongo uno **scrittore zip proprio** al posto di `ffi/archiver`:
- le voci **non modificate** vengono copiate così come sono (byte compressi, CRC e metodo
  identici), senza decomprimerle né ricomprimerle. È più veloce, e i font offuscati
  restano intatti (crengine li restituirebbe già decifrati);
- le voci **modificate** (XHTML, OPF, nav, ncx, CSS) vengono compresse con `compress2` di zlib,
  da cui tolgo intestazione e checksum zlib per ottenere deflate grezzo (è la tecnica che usava
  il vecchio `ffi/zipwriter`); il CRC lo calcola `crc32`;
- `mimetype` va per primo, non compresso e **senza extra field**. Questo risolve anche il dubbio
  su libarchive sollevato nell'analisi.

Così c'è un'unica via di scrittura valida per tutte le versioni dalla 2024.07 in poi,
testabile sul PC.

## Moduli

| File | Ruolo | Dipende da KOReader |
|---|---|---|
| `parergon/testo.lua` | UTF-8, entità, normalizzazione con mappa carattere → byte | no |
| `parergon/xmltok.lua` | tokenizzatore con posizioni in byte, albero, controllo di bilanciamento | no |
| `parergon/xpointer.lua` | analisi degli XPointer (tutte le varianti) | no |
| `parergon/corrisp.lua` | corrispondenza annotazione → segmenti di byte | no |
| `parergon/zip.lua` | lettura della struttura zip | no |
| `parergon/epub.lua` | container, OPF, spine → DocFragment | no |
| `parergon/analisi.lua` | analisi completa e rapporto | no |
| `main.lua` | menu, lettore del file, finestra del rapporto | sì |

## Test sul PC

```
python test/crea_epub.py
python test/crea_epub.py --store
luajit test/esegui.lua          # 131 verifiche
luajit test/simula_koreader.lua # carica main.lua con finti moduli KOReader
```

`test/annotazioni_prova.lua` contiene 16 annotazioni di prova con l'esito atteso: passi
semplici, corsivi, entità e NBSP, testo ripetuto, spazi irregolari, il nodo di spazi
iniziale scartato da crengine, trattino morbido, `<br/>`, due paragrafi, testo assente,
percorso sbagliato, XPointer vecchio stile, div annidati, richiamo di nota e un segnalibro.

## Limiti noti del prototipo
- Gli XPointer delle annotazioni di prova sono scritti a mano seguendo il codice di crengine.
  Vanno confrontati con quelli reali prodotti sul dispositivo (vedi la prova qui sotto).
- epubcheck, che allora era bloccato dai permessi, è stato eseguito il 23/11/2026: nessun
  errore (vedi `tools/epubcheck.py`).

## Prova sul dispositivo
1. Copia la cartella `parergon.koplugin` in `koreader/plugins/` (su BOOX di solito
   `/sdcard/koreader/plugins/`) e riavvia KOReader.
2. Copia `test/libro-prova.epub` sul dispositivo e aprilo.
3. Sottolinea alcuni dei passi elencati in `test/annotazioni_prova.lua`: per esempio «per una
   selva oscura», «cammino della vita», la seconda «una rosa», «testo normale», «riga seconda
   riga», «una nota1 a piè di» e una sottolineatura su due paragrafi.
4. Menu → Strumenti → Altri strumenti → **Parergon** → *Analyze annotations*
   corrispondenze*.
5. Il rapporto viene salvato anche in `koreader/parergon-report.txt`: mandamelo,
   insieme a quello di un libro vero con annotazioni arrivate da Readest.
