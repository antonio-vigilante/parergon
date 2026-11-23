# consolida.koplugin — Fase 1: analisi del codice e scelte tecniche

Sorgenti esaminati (clone del 22/11/2026):

| Repository | Revisione |
|---|---|
| koreader/koreader | `1294bb3` (master, 21/11/2026) |
| koreader/koreader-base | master, stessa data |
| koreader/crengine | master, stessa data (`DOM_VERSION_CURRENT 20260812`) |
| readest/readest, cartella `apps/readest.koplugin` | master, stessa data |

> Quanto segue vale per il master attuale. La versione installata sul BOOX potrebbe
> essere più vecchia: indico i punti in cui questo cambia qualcosa.

---

## 1. Struttura di un plugin

Ho preso come modello `plugins/hello.koplugin`:

- `_meta.lua` restituisce `{ fullname = _("…"), description = _("…") }`.
- `main.lua` restituisce un `WidgetContainer:extend{ name = "consolida", is_doc_only = true }`.
  Dentro `init()` il plugin si registra con `self.ui.menu:registerToMainMenu(self)`, poi
  `addToMainMenu(menu_items)` aggiunge `menu_items.consolida = { text = …, sorting_hint = "more_tools", callback = … }`.
- Con `is_doc_only = true` il plugin si carica solo nel lettore, quindi `self.ui.document` è disponibile.
- Per aprire un altro libro esiste `ReaderUI:switchDocument(new_file, …)`
  (`frontend/apps/reader/readerui.lua:969`).
- Le impostazioni globali del plugin (per esempio il nome del lettore) vanno in `G_reader_settings`.
  Quelle legate al singolo libro vanno in `self.ui.doc_settings`.

## 2. Dove e come sono salvate le annotazioni

### 2.1 Il file
`frontend/docsettings.lua:143`: il nome del file è `"metadata." .. suffisso .. ".lua"`, quindi
`metadata.epub.lua`. Non si trova per forza in `Libro.sdr` accanto al libro:
`getSidecarDir()` (riga 118) gestisce **tre posizioni**: `"doc"` (accanto al libro), `"dir"`
(cartella `docsettings` centrale) e `"hash"` (cartella indicizzata per hash). Quale si usa
dipende da un'impostazione dell'utente.

**Scelta:** il plugin non legge il file `.sdr`. Usa la lista viva
`self.ui.annotation.annotations`, che è la stessa tabella che `ReaderAnnotation:onSaveSettings()`
scrive come chiave `annotations` (`readerannotation.lua:250-252`). Così funziona con
qualunque posizione del sidecar e include anche le modifiche non ancora salvate.

### 2.2 I campi (verificati in `readerannotation.lua:66-84`)

| campo | contenuto | uso nel plugin |
|---|---|---|
| `datetime` | creazione, `"AAAA-MM-GG HH:MM:SS"` | ordinamento, id stabile |
| `drawer` | stile: `"lighten"`, `"underscore"`, `"strikeout"`, `"invert"` (righe 377-380 di `readerhighlight.lua`); **assente = segnalibro di pagina** | distingue le sottolineature dai segnalibri e sceglie lo stile |
| `color` | `red orange yellow green olive cyan blue purple gray` (`readerhighlight.lua:29-39`), più eventuali colori personalizzati | mappatura verso lo stile |
| `text` | testo sottolineato | verifica della corrispondenza |
| `text_edited` | `true` se l'utente ha modificato il testo a mano | probabile mancata corrispondenza: va segnalato |
| `note` | nota dell'utente (`nil` se vuota) | nota tra parentesi quadre e titolo nell'indice |
| `note_format` | `nil` (testo semplice), `"html"` o `"md"` | v1: testo semplice; per `html`/`md` tolgo il markup |
| `chapter`, `pageno`, `pageref` | capitolo e pagina | rapporto e pagina dell'indice |
| `page`, `pos0`, `pos1` | XPointer (stringhe) per EPUB | corrispondenza |
| `epubcfi` | CFI calcolato da pos0/pos1 | non usato |

### 2.3 Annotazioni provenienti da Readest
Ho letto `readest_syncannotations.lua` del plugin ufficiale:

- Readest scambia con KOReader **XPointer** (`xpointer0`, `xpointer1`), non CFI. Le
  annotazioni create sul telefono arrivano in KOReader come voci normali con `pos0` e `pos1`.
- La conversione degli stili (righe 488-493) è: `highlight → "lighten"`, `underline → "underscore"`
  e **`squiggly` (ondulata) → `"strikeout"`**. In KOReader, quindi, la sottolineatura ondulata
  di Readest appare come barrato. Per questo la mappatura predefinita proposta è
  **`strikeout → zigzag`**: la sottolineatura ondulata fatta sul telefono torna ondulata
  nella copia consolidata.
- I colori sono mappati in modo biunivoco (`violet ↔ purple`, `#ff8800 ↔ orange`…), quindi anche
  `color` è affidabile per la mappatura.
- I libri si riconoscono da `partial_md5_checksum` (`util.partialMD5`, campioni di 1 KB a offset
  4^i). Qualunque modifica all'originale lo scollegherebbe, il che conferma la scelta di
  lavorare su una copia. La copia avrà un hash suo e sarà un libro nuovo, senza annotazioni.
- **Rischio:** gli XPointer prodotti da Readest vengono da un DOM di browser, non da crengine.
  Potrebbero differire da quelli nativi negli indici dei nodi di testo. È un motivo in più
  per **verificare sempre il testo** e non fidarsi degli offset.

## 3. XPointer di crengine: cosa dice davvero il codice

### 3.1 `DocFragment[N]` → elemento dello spine (`crengine/src/epubfmt.cpp:1536-1690`)
- Ogni `<itemref>` del `<spine>` il cui `idref` **esiste nel manifest** diventa un elemento
  dello spine. Gli `itemref` con idref inesistente vengono scartati e non contano.
  `linear="no"` **non** esclude l'elemento: crea comunque un DocFragment, marcato come non lineare.
- Con versione DOM ≥ **20240114** ("relaxed spine") ogni elemento dello spine produce un
  DocFragment, anche se non è XHTML: per SVG ne crea uno contenitore, per i tipi non supportati
  uno fittizio. Con versione DOM **< 20240114** contano solo gli elementi con
  `media-type="application/xhtml+xml"`.
- La versione DOM è salvata per libro in `doc_settings` come `cre_dom_version`
  (`readerrolling.lua:172-184`). I libri aperti per la prima volta con KOReader vecchi
  mantengono la versione vecchia.

**Scelta:** il plugin ricostruisce la corrispondenza N → file come fa crengine, leggendo
`cre_dom_version` e applicando o meno il filtro sul media-type. Come controllo incrociato
confronta il numero di DocFragment atteso con quello reale.

### 3.2 Il percorso (`lvtinydom.cpp:11658-11746`, `toStringV2`)
- Dalla versione DOM 20200223 gli XPointer sono **normalizzati**. I nodi che crengine
  inserisce per l'impaginazione (`autoBoxing`, `floatBox`, `inlineBox`, `tabularBox`,
  `rubyBox`, pseudo-elementi) vengono **saltati** nel percorso, quindi il percorso
  ricalca la struttura dell'XHTML. Con versioni DOM più vecchie (`toStringV1`) questi nodi
  compaiono e il percorso può non corrispondere al file.
- **Novità della 20260812:** l'indice `[1]` ora è sempre esplicito (`p[1]`, `text()[1]`).
  Prima veniva omesso quando l'elemento era l'unico del suo nome. Il parser del plugin deve
  quindi accettare sia `p` sia `p[1]`.
- Gli indici contano i fratelli **con lo stesso nome** (`p[3]` = terzo `<p>` tra i figli,
  non terzo figlio). `text()[k]` conta solo i nodi di testo.
- Il nome di `<html>` sparisce: il percorso è `/body/DocFragment[N]/body/…`, dove il secondo
  `body` è il `<body>` del file.

### 3.3 Perché gli offset non coincidono col file
Dal codice risultano almeno queste trasformazioni:
1. **Nodi di spazi iniziali eliminati.** `ldomElementWriter::onText` (`lvtinydom.cpp:9062`) scarta
   un nodo di soli spazi se è il **primo figlio** di un elemento a blocco. Così cambia la
   numerazione di `text()[k]` rispetto al sorgente.
2. **Entità risolte e spazi compressi.** `PreProcessXmlString` (`lvxml.cpp:5616`) decodifica le
   entità e comprime le sequenze di spazi. Un offset di `text().OFFSET` conta caratteri
   Unicode dopo queste trasformazioni, non byte del file.
3. **Parser HTML, non XML.** I file vengono letti con `LVHTMLParser` (`epubfmt.cpp:1634`), che può
   chiudere automaticamente tag non bilanciati (regole "HTML5" dalla DOM 20200824). Con XHTML
   ben formato la struttura resta uguale. Con file mal formati no.
4. `<pre>`: dalla DOM 20210904 viene tolto l'a capo iniziale.

### 3.4 Strategia di corrispondenza proposta
Per ogni annotazione con `drawer` e XPointer:

1. **Analisi degli XPointer.** Da `pos0` e `pos1` ricavo N, i passi del percorso (nome, indice),
   `text()[k]` e l'offset.
2. **Filtro v1, un solo paragrafo.** Calcolo per pos0 e pos1 l'antenato a blocco più vicino
   (`p, h1-h6, li, dd, dt, blockquote, div, td, th, figcaption, pre, caption`). Se N o
   l'antenato differiscono, salto l'annotazione con il motivo *"attraversa più paragrafi"*.
3. **File.** N diventa l'href del file nello spine, che leggo dall'EPUB originale (byte esatti).
4. **Nodo.** Analizzo l'XHTML con un tokenizzatore che registra la **posizione in byte** di ogni
   tag e di ogni nodo di testo, poi scendo il percorso da `<body>`. Se il percorso non si
   risolve (struttura alterata), cerco nell'intero file e accetto solo **una corrispondenza
   unica**, annotando nel rapporto che è stata trovata per ricerca.
5. **Testo normalizzato con mappa.** Del blocco trovato costruisco il "testo visibile":
   entità decodificate, ogni sequenza di spazi (inclusi NBSP e gli spazi Unicode) ridotta
   a un solo spazio, trattini morbidi (U+00AD, `&shy;`) ignorati. Per ogni carattere
   conservo l'intervallo di byte d'origine. Normalizzo allo stesso modo `annotation.text`.
6. **Ricerca.** Cerco il testo dell'annotazione nel testo del blocco.
   - 0 occorrenze: salto, *"testo non trovato nel paragrafo"* (con `text_edited` il motivo diventa
     *"testo modificato in KOReader"*).
   - 1 occorrenza: corrispondenza certa.
   - più di una occorrenza: disambiguo con la posizione. Sul dispositivo chiedo a crengine il
     testo dall'inizio del blocco a `pos0` (`document:getTextFromXPointers(inizio_blocco, pos0)`),
     lo normalizzo e ne prendo la lunghezza come posizione attesa. Scelgo l'occorrenza che
     inizia lì. Se nessuna coincide entro pochi caratteri, salto con il motivo *"ambiguo"*.
     Fuori dal dispositivo, nei test, passo la posizione attesa a mano.
7. **Riconversione in byte.** L'intervallo trovato torna a intervalli di byte, **uno per ogni
   nodo di testo attraversato**. Se il passo contiene `<i>…</i>`, ottengo più segmenti, ognuno
   avvolto nel proprio `<span>`. Così l'XML resta sempre ben formato e non si spezzano mai
   le entità.
8. **Sovrapposizioni.** Se due annotazioni si sovrappongono nello stesso file, la seconda viene
   saltata (*"sovrapposta a un'altra annotazione"*). Le affronteremo nella fase multi-elemento.

## 4. Parser XML o manipolazione testuale?

Disponibili in KOReader:
- `frontend/luxl.lua`: tokenizzatore XML a eventi (usato dal plugin OPDS). **Non restituisce le
  posizioni in byte**, gestisce male commenti, CDATA, DOCTYPE e istruzioni di elaborazione, e
  dipende da `ffi`.
- `lua-htmlparser` (usato da newsdownloader): parser HTML con selettori CSS, pensato per estrarre
  dati e non per riscrivere fedelmente.
- `newsdownloader.koplugin/lib/xml.lua`: privato di quel plugin, quindi non va usato.
- crengine stesso: ha il DOM, ma è il DOM **trasformato** (vedi 3.3) e non esiste un modo per
  riserializzare il file sorgente originale.

**Scelta: manipolazione testuale prudente guidata da un tokenizzatore scritto per il plugin**
(Lua puro, circa 200 righe, senza `ffi`). Le ragioni:
1. Analizzare e riserializzare l'intero file cambierebbe byte ovunque (entità, DOCTYPE,
   namespace, spazi, ordine degli attributi), con il rischio di rompere libri che oggi
   funzionano. Con l'inserimento chirurgico **ogni byte fuori dai punti d'inserimento resta
   identico**.
2. Mi servono le posizioni in byte, e nessuno dei parser disponibili le fornisce.
3. Il Lua puro si può testare sul PC con un normale interprete Lua o LuaJIT.

Il tokenizzatore riconosce tag di apertura e chiusura, tag vuoti, commenti, CDATA, `<?…?>`,
`<!DOCTYPE…>`, e attributi con virgolette singole o doppie (anche con `>` dentro). Dopo ogni
riscrittura **ri-tokenizzo il file modificato e verifico che i tag siano bilanciati**. Se il
controllo fallisce, scarto tutte le modifiche a quel file e lo riporto nel rapporto.

Uso lo stesso tokenizzatore per OPF, `nav.xhtml` e `toc.ncx`: trovo i punti di inserimento
(`</manifest>`, `</spine>`, la fine dell'`<ol>` principale del `nav` di tipo `toc`, la fine di
`<navMap>`) e aggiungo testo senza toccare il resto.

## 5. Archivi zip: `ffi/archiver` (libarchive)

**Esiste** nel master: `koreader-base/ffi/archiver.lua`, con `Reader` e `Writer`.

- `Reader:new()`, `:open(path)`, `:iterate()` (voci con `path`, `mode`, `size`, `index`),
  `:extractToMemory(path)` e `:close()`. Lo usano già `readerui.lua:683`, `readerdictionary.lua`
  e `wikipedia.lua`.
- `Writer:new()`, `:open(path, "epub")` (`"epub"` viene tradotto in `"zip"`),
  `:setZipCompression("store"|"deflate")`, `:addFileFromMemory(path, contenuto, mtime)`
  e `:close()`.
- `newsdownloader.koplugin/epubdownloadbackend.lua:533-548` crea un EPUB proprio così:
  `setZipCompression("store")`, poi `mimetype`, poi `setZipCompression("deflate")`. **Il
  mimetype come prima voce non compressa si ottiene quindi con le API esistenti.**
- (Di passaggio: a riga 705 newsdownloader passa un booleano come terzo argomento di
  `addFileFromMemory`, che invece è `mtime`. È un piccolo bug suo e non ci riguarda.)
- `ffi/zlib` offre solo `compress2`, `uncompress` e `crc32`, non il deflate grezzo. Scrivere da
  soli lo zip compresso non conviene, quindi uso libarchive.

**Rischio da verificare in fase 3.** Il writer zip di libarchive di solito aggiunge un
*extra field* (timestamp "UT"/"ux") a ogni intestazione locale, mimetype compreso.
epubcheck lo segnala (PKG-005), anche se i lettori in pratica lo tollerano: gli EPUB di
newsdownloader si aprono ovunque. Se l'extra field c'è, propongo un post-processo in Lua puro:
tolgo l'extra field dall'intestazione locale del mimetype (che è la prima voce) e
correggo gli offset nella directory centrale e nell'EOCD. È un'operazione deterministica e
testabile sul PC.

Altre regole per la copia:
- Riscrivo le voci nell'ordine originale. Le immagini e i font restano `store` (sono già
  compressi), il resto va in `deflate`.
- `META-INF/encryption.xml`: se contiene solo l'offuscamento dei font (IDPF o Adobe) proseguo e
  **non cambio `dc:identifier`**, perché la chiave di offuscamento IDPF deriva da lì. Se
  contiene altro (DRM), mi fermo con un messaggio.
- Scrivo prima `… (consolidato).epub.tmp`, poi verifico e rinomino. Se la copia esiste già
  chiedo conferma. **L'originale non viene mai aperto in scrittura.**
- Verifica finale: riapro la copia con `Archiver.Reader`, controllo che la prima voce sia
  `mimetype`, che ogni voce si legga, che l'OPF si analizzi e che i file modificati siano
  bilanciati. Poi una `ConfirmBox` propone di aprirla con `switchDocument`, che è anche la
  prova definitiva che si apre.
- Le annotazioni dell'originale restano intatte, perché il plugin le legge e basta. La copia
  nasce senza sidecar.

## 6. Stili di sottolineatura: cosa supporta crengine

Verificato in `crengine/src/lvstsheet.cpp` e `lvtextfm.cpp`:

| Proprietà | crengine (KOReader) |
|---|---|
| `text-decoration: underline` (abbreviata) | **sì** (riga 4119). Colore, stile e spessore nell'abbreviata vengono ignorati, ma la parola `underline` resta valida |
| `text-decoration-line`, `-style`, `-color`, `-thickness` | **no**, sono proprietà sconosciute e vengono ignorate del tutto |
| `border-bottom` su elementi in linea | **sì**, con `solid`, `dashed` e `dotted` (`drawBorder`, righe 6195-6232). Gli altri stili vengono disegnati come `solid` |
| `background-image` su elementi in linea | **no**. Per gli elementi in linea viene disegnato solo il colore di sfondo |
| ondulato (`wavy`) | **impossibile** |
| `-cr-only-if: never` | estensione di crengine: **dichiarazioni successive ignorate da crengine**, applicate dai browser (che ignorano la proprietà sconosciuta) |

Conseguenze:
- La proprietà `text-decoration-line` proposta nella specifica **in KOReader non
  sottolineerebbe nulla**. Serve l'abbreviata `text-decoration: underline`.
- L'idea dello sfondo SVG per lo zigzag in KOReader non funziona. Nei motori web (Readest usa
  una WebView con foliate-js) funziona, ma lì `text-decoration-style: wavy` è già
  supportato ed è migliore, perché segue le discendenti e cambia colore con il tema.

**Proposta.** Usare `border-bottom` per KOReader, `text-decoration` per gli altri, e separarli con
`-cr-only-if: never`:

```css
/* Base per crengine e motori semplici; tre stili distinguibili anche su e-ink. */
.consolida-hl-continua     { border-bottom: 0.08em solid  currentColor; }
.consolida-hl-tratteggiata { border-bottom: 0.08em dashed currentColor; }
.consolida-hl-zigzag       { border-bottom: 0.12em dotted currentColor; } /* in KOReader lo zigzag diventa puntinato */

/* Motori web (Readest, Apple Books, Calibre…): crengine si ferma a -cr-only-if. */
.consolida-hl-continua, .consolida-hl-tratteggiata, .consolida-hl-zigzag {
  -cr-only-if: never;
  border-bottom: none;
  text-decoration: underline;                 /* ripiego per chi non conosce lo stile */
  text-underline-offset: 0.15em;
}
.consolida-hl-tratteggiata { -cr-only-if: never; text-decoration: underline dashed; }
.consolida-hl-zigzag       { -cr-only-if: never; text-decoration: underline wavy; }
```

Il risultato è che nessun motore mostra una linea doppia, i motori che non capiscono lo stile
nell'abbreviata mantengono `underline` semplice, e non ci sono sfondi colorati. Il colore di
KOReader può dare in più una tinta alla linea, ma senza mai essere l'unico segnale.

**Da verificare sul campo, non solo nel codice.** Tre punti:
- Readest può applicare un "override" degli stili del libro: va provato con il libro di test.
- Il margine sotto il testo in KOReader dipende da `line-height`.
- L'effetto di `-cr-only-if` nei fogli di stile *del libro* (non solo in quelli interni di
  KOReader): dal codice è generale, ma lo controllo nella fase 3.

**Mappatura configurabile:** stile = regola per annotazione → regola per `drawer` → regola per
`color` → stile predefinito del libro. Valori predefiniti proposti: `underscore → continua`,
`strikeout → zigzag` (corrisponde all'ondulata di Readest), `lighten`/`invert` → stile generale.
Per i colori la mappatura parte vuota e si configura nel menu. La scelta per singola
annotazione, nella prima versione, passa dalla mappatura (colore o stile assegnato in KOReader).
Una lista di revisione per annotazione la propongo come passo successivo.

## 7. Altre strutture dell'EPUB

- **Frontespizio:** cerco in `nav.xhtml` `<nav epub:type="landmarks">` con
  `epub:type="titlepage"` e in OPF `<guide><reference type="title-page">` (accetto anche
  `"titlepage"`). Inserisco `<p class="consolida-lettore">…</p>` prima di `</body>`. Se non c'è
  certezza, creo `consolida-lettore.xhtml` e la inserisco nello spine dopo la copertina
  (landmark `cover`, guide `type="cover"`, oppure primo elemento dello spine se il manifest lo
  marca come copertina). Se anche la copertina è incerta, la metto in testa.
- **Indice personale:**
  - in `nav.xhtml`, un nuovo `<li>` in fondo all'`<ol>` principale del `nav` di tipo `toc`, con
    `<a href="consolida-indice.xhtml">Indice personale</a><ol>…</ol>`;
  - in `toc.ncx`, un nuovo `<navPoint>` in fondo a `<navMap>`, con `playOrder` successivi al
    massimo esistente e `id` univoci;
  - le voci dell'autore restano intatte.
- **Pagina dell'indice:** `consolida-indice.xhtml` in fondo allo spine, con link
  `capitolo.xhtml#consolida-ann-K`.
- **Àncora:** `id="consolida-ann-K"` sul primo `<span>` dell'evidenziazione. Se le evidenziazioni
  sono disattivate, uso uno `<span id="…"></span>` vuoto, scritto **esplicito** e non
  autochiudente, perché crengine legge i file con un parser HTML.
- **Manifest:** aggiungo `consolida.css`, le pagine nuove e, dove serve, `properties`. Ogni file
  modificato riceve un `<link rel="stylesheet">` con percorso relativo prima di `</head>`.
- **Data in italiano:** tabella dei mesi nel codice (`os.date` dipende dalla locale e su Android
  non è affidabile).

## 8. Struttura del progetto proposta

```
consolida.koplugin/
  _meta.lua
  main.lua                 -- menu, finestra delle opzioni, rapporto (widget KOReader)
  consolida/xpointer.lua   -- analisi degli XPointer
  consolida/xmltok.lua     -- tokenizzatore con posizioni in byte
  consolida/testo.lua      -- normalizzazione, entità, mappa carattere → byte
  consolida/corrisp.lua    -- corrispondenza annotazione → intervalli di byte
  consolida/epub.lua       -- OPF/spine/nav/ncx, lettura e scrittura (archiver)
  consolida/riscrivi.lua   -- inserimenti, CSS, indice, frontespizio
test/                      -- test eseguibili sul PC (Lua puro), EPUB di prova
README.md, LICENSE (GPL-3.0)
```

Solo `main.lua` ed `epub.lua` (lettura e scrittura dello zip) dipendono da KOReader. Tutto il
resto è Lua puro e si testa sul PC. Sul PC non c'è ancora un interprete Lua: per i test
propongo di installare LuaJIT (lo stesso motore di KOReader) oppure Lua 5.1/5.4. Il codice
resterà compatibile con entrambi.
