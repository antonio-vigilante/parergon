# Fase 4 — note del lettore nel testo

## Finestra di consolidamento
*Parergon → Crea la copia consolidata…* apre una finestra con:
- il nome della copia e i conteggi (sottolineature, di cui con nota);
- ☑/☐ **Evidenziazioni nel testo**;
- ☑/☐ **Note tra parentesi quadre**;
- ◉/○ **Tutte le annotazioni** / **Solo quelle con una nota**;
- **Annulla** e **Crea**. *Crea* è disattivato se entrambe le caselle sono vuote.

Ogni scelta chiude e riapre la finestra: un solo aggiornamento dello schermo e nessuna
animazione. Le scelte vengono ricordate (`parergon_options`).

## Regole delle note (`parergon/note.lua`)
- **Posizione.** Subito dopo il passo, nello stesso paragrafo:
  `…oscura</span> <span class="parergon-note">[Inizio celebre]</span>.`
  Se il passo finisce dentro un **link** o un **esponente** (`a`, `sup`, `sub`, `ruby`, `rt`),
  la nota va dopo quell'elemento (`riscrivi.puntoNota`). Altrimenti diventerebbe parte del
  link, oppure minuscola e rialzata. Corsivi, grassetti e span generici non si scavalcano:
  nei libri convertiti uno span avvolge spesso l'intero paragrafo.
- **Titolo `#`.** Se la prima riga inizia con `#`, è il titolo della voce dell'indice
  (fase 5) e non va nel testo. Una nota fatta solo di titolo non aggiunge nulla nel testo.
- **A capo.** Diventano `<br/>`. Più righe vuote di seguito valgono un solo a capo.
- **Formati.** Le note HTML e Markdown di KOReader (`note_format`) vengono ridotte a testo.
- **Caratteri speciali** protetti (`&lt;`, `&amp;`…).
- **Annotazioni saltate.** Se il passo non viene trovato, anche la nota viene saltata e
  compare nel rapporto.
- **Segnalibri di pagina con nota.** Non hanno un passo a cui agganciarsi: vengono saltati
  e segnalati (codice `segnalibro`).

## Aspetto (`stile.css`)
- Base (KOReader / e-ink): corsivo, `font-size: 0.9em`, colore blu scuro `#2E4A7D`, peso
  normale, nessuna sottolineatura, linea di base normale.
- Web: blu intermedio `#5577AA`, leggibile sul tema chiaro e su quello scuro.

## Test
```
luajit test/esegui_fase4.lua    # 77 verifiche
```
Produce `test/uscita/Note di prova (annotated).epub` per la verifica visiva. Le note di
prova coprono: nota semplice, titolo `#` con corpo, solo titolo, nota su due righe con
caratteri speciali, nota HTML su un passo che attraversa il richiamo di nota, annotazione
senza nota, segnalibro con nota, passo inesistente.

## Note a comparsa (22/11/2026)
Nella finestra di consolidamento, sotto «Note del lettore»:
◉ **Nel testo, tra parentesi** (con ☑ **Note in corsivo**, opzionale) oppure
◉ **A comparsa, con richiamo [1]**.

- **Nel testo**, dopo il passo, c'è un richiamo `[n]`:
  `<a class="parergon-noteref" id="parergon-r-n" href="…parergon-notes.xhtml#parergon-n-n" epub:type="noteref" role="doc-noteref">[n]</a>`.
  KOReader considera affidabili `epub:type="noteref"` e `role="doc-noteref"`
  (`cre.cpp`, `isLinkToFootnote`) e mostra la nota in una finestrella. Readest e Apple
  Books fanno lo stesso. Nei libri EPUB 2 i due attributi non ci sono (vedi «Libri EPUB 2»).
- **Parentesi quadre e colore delle note**, perché il richiamo non si confonda con gli
  esponenti dell'autore (¹, \*). La numerazione è continua in tutto il libro.
- **Forma del richiamo** (*Parergon → Richiamo delle note a comparsa*):
  - **sulla riga** (predefinito dal 22/11/2026, scelto dopo la prova sul Kindle), al 90%;
  - **in apice**, all'80% del corpo invece del 60–65% abituale.

  In entrambi i casi è in grassetto, con un piccolo margine che allarga l'area di tocco.
- **Pagina «Note del lettore»** (`parergon-notes.xhtml`), in fondo allo spine, nel
  manifest:
  - per ogni nota, il numero `[n]`, che è anche il link di ritorno al passo
    (`role="doc-backlink"`), poi la nota e sotto il passo citato con il capitolo;
  - marcature `epub:type="endnote"` e `role="doc-endnote"`;
  - nelle app che non mostrano la finestrella, il richiamo porta a questa pagina e il
    numero riporta al testo.
- **File EPUB 2.** Se un XHTML non dichiara il prefisso `epub:`, viene aggiunto
  `xmlns:epub` all'elemento `<html>` (`riscrivi.dichiaraEpub`). Senza, il file non
  sarebbe XML ben formato.
- **Numerazione e file saltati.** Se un file non si può modificare in modo sicuro, i
  numeri delle sue note tornano disponibili: la numerazione resta senza buchi.
- **Verifica indipendente.** `test/verifica_epub.py` ora controlla anche che ogni
  `itemref` esista nel manifest e che ogni link interno con frammento (`file#id`) arrivi
  a un id esistente.

File per la prova visiva:
- `test/uscita/Note a comparsa (annotated).epub` (richiamo in apice);
- `test/uscita/Note a comparsa sulla riga (annotated).epub`.

### Correzioni dopo la prova sul Kindle (22/11/2026)
- **La finestrella non compariva.** In KOReader l'opzione *Show footnotes in popup*
  (`footnote_link_in_popup`) è **disattivata per impostazione predefinita**: senza, il
  richiamo porta alla pagina delle note. Si attiva da *Impostazioni → Tocchi e gesti →
  Collegamenti*. È un'impostazione dell'utente, non del libro: va indicata nel README.
- **Pagina delle note poco leggibile** (font piccolo, margini minimi). Lo stile opzionale
  di KOReader *In-page EPUB footnotes* rimpicciolisce e azzera i margini degli elementi
  con `epub:type="endnote"` o `role="doc-endnote"`. Le voci della pagina non hanno più
  queste marcature (non servono alla finestrella, che si basa sul richiamo). La pagina ha
  ora margini laterali propri (1,5 em, perché non riceve il CSS del libro), corpo pieno,
  interlinea 1,45 e voci ben separate.

## Libri EPUB 2 (23/11/2026)
epubcheck 5.4.0 ha mostrato che le copie dei libri EPUB 2 non erano valide: XHTML 1.1 non
ammette `<section>`, il DOCTYPE di HTML5, `lang`, `epub:type` e `role`. Il libro di prova
è EPUB 3, quindi i test non lo vedevano. Ora, quando il pacchetto è in versione 2:
- le pagine aggiunte (indice personale, note del lettore, nota di lettura) hanno il DOCTYPE
  XHTML 1.1, solo `xml:lang` e `<div>` al posto di `<section>` (`testo.inizioPagina`);
- i richiami `[n]` sono link semplici, senza `epub:type="noteref"` e `role`, e il
  capitolo non riceve il prefisso `xmlns:epub`. **Scelta dell'utente**: la copia deve
  essere valida. Secondo `cre.cpp` (`isLinkToFootnote`, flag predefiniti di
  `readerlink.lua`) KOReader riconosce comunque il link come nota: il testo `[n]` è un
  numero, la destinazione ha un id e viene dopo nel libro, e il link non è l'unico
  contenuto del paragrafo. **Verificato sul Kindle il 23/11/2026** con
  `test/uscita/Note a comparsa EPUB 2 (annotated).epub`: con *Show footnotes in popup*
  attivo, la nota compare nella finestrella in fondo alla pagina.

Il libro EPUB 2 di prova si crea con `python test/crea_epub2.py`, a partire dal libro di
prova. epubcheck si lancia con `python tools/epubcheck.py <epubcheck.jar>`.
