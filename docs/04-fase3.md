# Fase 3 — copia consolidata con evidenziazioni permanenti

## Cosa fa
*Parergon → Create consolidated copy…* crea nella stessa cartella dell'originale
`Titolo (annotato).epub`, con ogni sottolineatura scritta nel testo come
`<span class="parergon-…">`. L'originale non viene mai aperto in scrittura.

## Impostazioni (menu Parergon)
| Voce | Valori | Predefinito |
|---|---|---|
| Stile delle evidenziazioni | Come in KOReader · Evidenziazione (sfondo) · Sottolineatura continua · tratteggiata · a zigzag | Come in KOReader |
| Stile per colore | per ognuno dei 9 colori: impostazione generale oppure una forma | impostazione generale |
| Colori | Mantieni i colori di KOReader · Grigio uniforme (schermi in bianco e nero) | Mantieni |

Con "Come in KOReader": *Evidenzia* e *Inverti* diventano evidenziazione, *Sottolinea*
diventa sottolineatura continua, *Barra* (e quindi l'ondulata di Readest) diventa zigzag.
Precedenza: forma scelta per la singola annotazione (campo interno `parergon_forma`,
per ora usato solo dal campionario) → mappatura per colore → impostazione generale →
stile salvato da KOReader.

## Scelte tecniche verificate
- **CSS a due livelli** (`parergon/stile.lua`). Il livello di base vale per crengine:
  `border-bottom` solid/dashed/dotted e sfondi opachi. Il livello web viene dopo
  `-cr-only-if: never`: crengine salta tutto ciò che segue nel blocco
  (`lvstsheet.cpp`, variabile `ignoring`), mentre i browser ignorano la proprietà
  sconosciuta. Nessuna linea doppia.
- **Sfondi calibrati per il bianco e nero.** In bianco e nero KOReader disegna ogni
  evidenziazione come un grigio al 20% (`readerview.lua`, `darkenRect`, `lighten_factor` 0.2).
  Per ogni colore calcolo uno sfondo con luminanza Rec. 601 di 0,80, cioè lo stesso grigio.
  Il giallo chiaro di KOReader, convertito in grigio, sarebbe quasi bianco.
  Per i motori web lo sfondo è semitrasparente, quindi leggibile anche con i temi scuri.
- **Linee scurite:** luminanza massima 0,45.
- **Titolo e identificatore.** Readest collega i libri anche tramite un *meta hash* di
  titolo, autori e identificatore (`readest_syncconfig.lua`; server: `book_hash OR meta_hash`
  in `sync.ts`). Una copia con gli stessi metadati riceverebbe le annotazioni
  dell'originale, con indirizzi sbagliati. Perciò la copia ha **titolo con suffisso**
  e **nuovo `dc:identifier`** (aggiornato anche in `dtb:uid` di `toc.ncx`). L'identificatore
  si lascia invariato solo se il libro usa l'offuscamento dei font, che ne deriva la chiave;
  in quel caso basta il titolo a separare le due copie.
- **ZIP.** È scritto da `parergon/zipscrivi.lua`:
  - `mimetype` per primo, non compresso e senza extra field;
  - le voci non modificate sono copiate byte per byte (stessi dati compressi e stesso CRC);
  - le voci modificate sono compresse con la zlib di KOReader (`parergon/deflate.lua`). Se
    la zlib manca, vengono salvate non compresse.
- **Sicurezza:**
  - la copia si scrive su un file `.tmp`, si verifica (mimetype, numero di voci,
    intestazioni, CRC delle voci non compresse) e solo allora si rinomina;
  - non si può scrivere sull'originale;
  - i libri con DRM (`rights.xml`, cifratura diversa dall'offuscamento, voci ZIP cifrate)
    vengono rifiutati;
  - ogni XHTML riscritto si ri-analizza: se la struttura peggiora, quel file resta
    invariato e le sue annotazioni finiscono fra le saltate;
  - due sottolineature sovrapposte: vince la prima, l'altra viene saltata e segnalata.

## Passi su più paragrafi (23/11/2026)
Prima venivano saltati. Ora un'evidenziazione o una sottolineatura che attraversa più
blocchi **dello stesso file** viene scritta (`corrisp.trovaMulti`):
- si parte dal paragrafo di `pos0` e si arriva a quello di `pos1`, compresi i blocchi in
  mezzo (anche titoli ed epigrafi dentro contenitori). Il testo si confronta mettendo uno
  spazio fra un blocco e l'altro: KOReader li separa con un a capo, come mostrano i dati
  reali del Kindle (`…ingannare.\nPrima riga`);
- il passo deve cominciare nel primo paragrafo e finire nell'ultimo. Se compare più
  volte, si sceglie per posizione come per un solo paragrafo. Non si cerca nel resto del
  file;
- si scrive uno `<span>` per ogni nodo di testo. Gli spazi fra un blocco e l'altro non si
  avvolgono, perché uno span fra `</p>` e `<p>`, o fra due `<li>`, non sarebbe valido;
- la nota (nel testo o con il richiamo `[n]`) va dopo la fine del passo, nell'ultimo
  paragrafo. L'àncora dell'indice personale sta sul primo span;
- restano saltati, con un motivo: i paragrafi non trovati dal percorso, l'ordine
  rovesciato, il testo che non corrisponde e i passi fra **capitoli diversi** (file
  diversi), che richiederebbero di dividere il passo fra due file.

## Test
```
python test/crea_epub.py && python test/crea_epub.py --store
luajit test/esegui.lua          # 167 verifiche (analisi, corrispondenza, traduzioni)
luajit test/esegui_fase3.lua    # 69 verifiche (CRC, ZIP, stile, riscrittura, copia, DRM)
luajit test/simula_koreader.lua # interfaccia completa con finti moduli KOReader
python tools/estrai_frasi.py --check
```
Ogni EPUB prodotto viene ricontrollato in modo indipendente da `test/verifica_epub.py`
(Python), che verifica i CRC di tutte le voci, il mimetype, la buona formazione XML con un
parser vero e la presenza delle voci del manifest. Anche Calibre (`ebook-meta`,
`ebook-convert`) legge le copie senza errori.

## File per la verifica visiva (in `test/uscita/`)
- `Libro di prova (annotated).epub`: le 12 annotazioni di prova.
- `Campionario colori (annotated).epub`: capitolo "Campionario", con i 9 colori × 4 forme,
  più due frasi lunghe che vanno a capo.
- `Campionario grigio (annotated).epub`: lo stesso campionario in grigio uniforme.

## Limiti noti
- In KOReader lo zigzag è puntinato: crengine non disegna linee ondulate.
- Se in KOReader sono disattivati gli stili del libro ("Stili incorporati"), le evidenziazioni
  permanenti non si vedono, perché vivono nel CSS del libro.
- I lettori in bianco e nero che non usano crengine (per esempio quelli nativi di Kobo o
  PocketBook) applicano il livello web: sfondi semitrasparenti, quindi chiari. Per loro serve
  l'opzione "Grigio uniforme".
- Verificato con epubcheck 5.4.0 il 23/11/2026: nessun errore né avviso (vedi `05-fase4.md`,
  «Libri EPUB 2», e `tools/epubcheck.py`).

## Aggiornamenti successivi della copia (22/11/2026)
- **Flusso previsto:** si annota sempre l'**originale**. Quando serve si ricrea la copia,
  che viene ricostruita da zero con tutte le annotazioni correnti e **sostituisce** la
  precedente, dopo una conferma.
- **Identificatore derivato e stabile** (`pacchetto.uuidDerivato`): un UUID versione 8 ricavato
  dall'identificatore dell'originale. È sempre uguale fra una rigenerazione e l'altra, così
  Readest riconosce le versioni successive come lo stesso libro, ma resta diverso
  dall'originale.
- **Marcatore** nell'OPF della copia: `<meta name="parergon:source" content="…"/>`, con
  l'identificatore dell'originale. Se si chiede di consolidare una copia, il plugin avvisa e
  propone di lavorare sull'originale ("Continua comunque" resta possibile). Il marcatore non
  viene mai duplicato.
- **Avviso prima di sostituire** una copia che ha annotazioni fatte direttamente su di essa:
  vengono contate leggendo il suo sidecar con `DocSettings`.
