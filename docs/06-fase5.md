# Fase 5 — indice personale e nota di lettura

## Finestra di consolidamento (righe nuove)
```
☑ Indice personale
   ◉ Tutte   ○ Con un #tema   ○ Con una nota
   ◉ Temi dalla A alla Z   ○ Temi nell'ordine del libro
☐ Nota di lettura nel frontespizio
```
Per default l'indice è attivo e la nota di lettura no. Le scelte vengono ricordate.

## Indice personale (`parergon/indice.lua`)
- **Organizzazione per temi.** I temi sono `#tema` nella nota, anche annidati come
  `#genitore/figlio`: è la stessa convenzione della patch utente «Indice tematico», ma
  Parergon **non dipende dalla patch** e non ne legge le preferenze. Un'annotazione con
  più temi compare sotto ciascuno. Le annotazioni senza tema vanno in fondo, sotto
  «Altre annotazioni». Se nessuna annotazione ha un tema, le voci si raggruppano per
  capitolo.
- **Nomi leggibili** (23/11/2026). Nell'indice e nella TOC trattini e trattini bassi
  diventano spazi: `#arte-greca` e `#arte_greca` si leggono «arte greca», sia come temi
  sia come sotto-temi. Più separatori di fila danno un solo spazio, e quelli agli estremi
  si tolgono. Le maiuscole restano. Due temi che si leggono allo stesso modo
  finiscono sotto un unico titolo. La nota non cambia (`indice.nomeVisibile`).
- **Titolo della voce.** Viene, nell'ordine, dalla riga `# Titolo`, dalla prima riga del
  commento o dalle prime 8 parole del passo.
- **Pagina** `parergon-index.xhtml`, in fondo allo spine e prima delle «Note del
  lettore»:
  - un titolo per tema con il numero di voci (sotto-temi compresi);
  - per ogni voce il titolo come link al passo, poi il passo citato col capitolo, poi il
    commento quando aggiunge qualcosa al titolo;
  - margini e corpo come in un capitolo.
- **Àncore.** Con le evidenziazioni, il link punta all'id del primo span. Senza, si
  inserisce davanti al passo uno `<span id="…"></span>` vuoto, scritto per esteso perché
  crengine legge i file con un parser HTML.

## TOC (`parergon/toc.lua`)
- **nav.xhtml.** Nuovo `<li>` «Indice personale» in fondo all'`<ol>` principale del nav
  `toc`, con un livello di sotto-voci, una per gruppo (tema), che portano alla sezione
  della pagina. Se ci sono note a comparsa, c'è anche la voce «Note del lettore».
- **toc.ncx.** Nuovi `<navPoint>` in fondo a `<navMap>`: `playOrder` successivi al
  massimo esistente, id univoci, `dtb:depth` portato almeno alla profondità del nuovo
  ramo (2, oppure 3 con i sotto-temi).
- **Sotto-temi nella TOC** (23/11/2026, opzione *Sub-themes in the table of contents*,
  in italiano «Sotto-temi nell'indice del libro», spenta di default). Ogni tema porta
  sotto di sé i suoi sotto-temi diretti (`#viaggi/mare` → «mare» sotto «viaggi»), sia nel
  nav sia nel ncx. I livelli più profondi (`#a/b/c`) restano solo nella pagina. L'opzione
  è spenta di default perché alcune applicazioni gestiscono male le TOC profonde.
  Opzione interna `indice_toc_sottotemi`. Verificata sul Kindle il 23/11/2026.
- **Voci dell'autore** e **landmarks** intatti. Le singole voci dell'indice stanno solo
  nella pagina, non nella TOC.

## Nota di lettura (`parergon/frontespizio.lua`, `parergon/data.lua`)
- **Nome.** Viene chiesto la prima volta e poi ricordato (`parergon_reader_name`). Si
  cambia con «Cambia nome».
- **Frase.** Quella proposta, «Letto e annotato da *Nome* nel novembre 2026», è
  modificabile per intero. I mesi sono scritti nel plugin, non presi da `os.date`.
  Le elisioni sono gestite: «nell'aprile», «nell'agosto», «nell'ottobre».
- **Frontespizio.** Lo si cerca solo da indicazioni esplicite: landmark
  `epub:type="titlepage"` nel nav, poi `<guide>` `type="title-page"`/`"titlepage"`. Il
  file deve essere nello spine. La frase va in un paragrafo `parergon-reader`, centrato
  e in corsivo, prima di `</body>`.
- **Frontespizio non individuato con certezza.** Si crea `parergon-reader.xhtml`, subito
  dopo la copertina (landmark `cover` o guide `cover`) oppure, se la copertina non è nota,
  all'inizio dello spine. I file incerti non vengono toccati.

## Correzioni collegate
- L'aggiornamento di `dtb:uid` in `toc.ncx` ora parte dalla versione già modificata,
  quindi non cancella il ramo appena aggiunto alla TOC.
- `test/verifica_epub.py` controlla anche i `content src` di `toc.ncx` (file e id) e che
  i `playOrder` non si ripetano.

## Test
```
luajit test/esegui_fase5.lua    # 79 verifiche
```
Produce `test/uscita/Indice personale (annotated).epub`: in italiano, con temi annidati,
annotazioni senza tema e la nota di lettura nel frontespizio. Produce anche
`test/uscita/Sotto-temi nella TOC (annotated).epub`, con i sotto-temi «arte moderna» e
«mare aperto» (scritti `#arte/arte-moderna` e `#viaggi/mare_aperto`) nella TOC.
