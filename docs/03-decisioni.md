# Decisioni di progetto

## Licenza (22/11/2026)
**AGPL-3.0 o successiva**, la stessa di KOReader. Il testo integrale è in
`parergon.koplugin/LICENSE`, copiato da `COPYING` di KOReader. Tutte le intestazioni
dei file sono aggiornate.

## Indice personale: quali annotazioni e con quale titolo
Al momento di consolidare si sceglie tra tre criteri:

| Criterio | Annotazioni nell'indice |
|---|---|
| Tutte | ogni sottolineatura consolidata |
| **Solo con una nota** (predefinito) | quelle che hanno una nota |
| Solo con un titolo `#` | quelle la cui nota inizia con `#` |

**Sintassi della nota**, opzionale e facile da scrivere anche con la tastiera dell'e-reader:

```
# Il tema del viaggio
Qui l'autore riprende l'immagine del capitolo 1.
```

- Se la **prima riga inizia con `# ` (cancelletto e spazio)**, quella riga è il **titolo della voce** e
  **non** viene inserita nel testo. Il resto della nota, se c'è, va nel testo tra parentesi
  quadre.
- Senza `#`, il titolo è la prima riga della nota, accorciata a circa 60 caratteri. La nota
  intera va nel testo.
- Senza nota, il titolo sono le prime parole del passo, circa 8, seguite da "…".
- `#` è anche la sintassi dei titoli Markdown, quindi resta coerente con le note di formato `md`.

**Ordinamento e struttura:**
- nella TOC, un ramo "Indice personale" con le voci **in un solo livello**, nell'ordine del
  libro. Le TOC a più livelli sono gestite male da diverse applicazioni;
- nella pagina XHTML, voci **raggruppate per capitolo** (campo `chapter` dell'annotazione), con
  il passo, la nota e il link all'àncora.

## Visibilità nel menu
- La voce **"Parergon"** sta nella **prima pagina della scheda Strumenti**
  (`sorting_hint = "tools"`), vicino a "Esporta evidenziazioni", e non più in "Altri strumenti".
  Viene aggiunta in fondo all'elenco ufficiale. Un plugin esterno non può scegliere una posizione
  diversa senza modificare `reader_menu_order.lua` di KOReader.
- **Azione del Dispatcher** `parergon_annotations`, sezione "rolling". Permette di associare il
  plugin a un **gesto**, a un **tasto**, al **menu rapido** (Quick menu) o a un **profilo**.
  Nel menu dei gesti si trova fra le azioni dei documenti a scorrimento.
- Non è possibile, senza patch a KOReader, aggiungere una scheda propria nella barra del menu.
  Lo stesso vale per un pulsante nella finestra dell'elenco delle annotazioni.

## Nome e lingua (22/11/2026)
- Nome: **Parergon** (dal greco *pàrergon*, «ciò che sta accanto all'opera»), scelto il
  23/11/2026 al posto di *Marginalia*, già usato da due plugin KOReader (rmmr111/Marginalia.Koplugin
  e samfoy/marginalia). Cartella `parergon.koplugin`, chiave interna `name = "parergon"`,
  azione `parergon_annotations`. **Da non cambiare dopo la pubblicazione**, perché gli utenti
  perderebbero le impostazioni.
- Classi CSS nella copia consolidata: prefisso `parergon-` (`parergon-hl-continua`,
  `parergon-nota`, `parergon-lettore`...), al posto del `consolida-` dell'analisi iniziale.
- Interfaccia **in inglese** (frasi di base), con **traduzione italiana** in
  `locales/it.po`. Lingua scelta da *Parergon → Language*: "Automatic", che segue KOReader
  ed è il valore predefinito, "English" oppure "Italiano". L'impostazione è globale
  (`parergon_language`).
- `_meta.lua` (nome e descrizione nella gestione dei plugin di KOReader) resta in inglese:
  viene letto prima che il plugin carichi le proprie traduzioni.
- Commenti nel codice e documentazione in italiano. **README in due lingue** (23/11/2026):
  `README.md` in inglese, la pagina predefinita su GitHub, e `README.it.md` in italiano, con
  lo stesso contenuto. Ogni modifica va fatta in entrambi.
- Per aggiungere una lingua: `python tools/estrai_frasi.py` genera `locales/parergon.pot`.
  Da lì si crea `locales/<codice>.po` e si aggiunge la lingua a `i18n.DISPONIBILI`.
  `python tools/estrai_frasi.py --check` verifica che la traduzione sia completa.

## Nome della copia (22/11/2026)
Suffisso del nome del file e del titolo: **(annotato)** in italiano, **(annotated)** in inglese
(frase tradotta `"annotated"`). Le voci di menu continuano a chiamare l'operazione "copia consolidata".

## Temi della patch «Indice tematico» e titoli (22/11/2026)
La patch utente `2-indice-tematico.lua` marca le annotazioni con temi scritti nella nota:
`#tema`, anche annidati come `#genitore/figlio` (criterio `#([^%s#]+)`). Per non entrare
in conflitto, Parergon distingue i due usi di `#` come fa Markdown:
- `#tema`, **attaccato**: è un **tema**. Non va mai nel testo del libro, ovunque si trovi
  nella nota. La punteggiatura finale (`#digitale,`) non fa parte del nome e resta nel
  testo.
- `# Titolo`, **con lo spazio**: è il **titolo** della voce dell'indice personale e non va
  nel testo.
- Una nota fatta solo di temi non aggiunge nulla al testo, ma non è "vuota": conta fra le
  annotazioni con una nota.
- Nell'indice i nomi dei temi si mostrano con gli spazi al posto di `-` e `_`
  (23/11/2026). I temi scritti in modo diverso ma letti allo stesso modo si uniscono.
  Effetto voluto anche per parole composte: `#post-moderno` si legge «post moderno».
- Nella fase 5 l'indice personale sarà organizzato per temi (vedi la proposta nella
  conversazione).

## Prova su un libro reale (23/11/2026)
«La scuola inclusiva ha fallito», EPUB 3, sul Kindle (DOM 20240114): 67 annotazioni, 24 con
una nota e 19 con dei temi. Libro e sidecar sono stati copiati sul PC, senza modificare il
Kindle. Risultati: 66 annotazioni su 67 ritrovate e 46 scritte; 17 temi nell'indice, con i
nomi leggibili; copie valide per epubcheck. Due regole sono nate da questa prova:
- **Copie dello stesso passo.** Il sidecar conteneva 18 annotazioni con lo stesso inizio, la
  stessa data e fini via via più avanti, più tre coppie con date distanti 2 ore, in cui una
  versione è la stessa sottolineatura senza la prima parola. Fra annotazioni sovrapposte
  ora, a parità di inizio, vince la **più lunga** (prima vinceva la prima, che qui era la più
  corta). Quelle tutte dentro un'altra sono segnalate come «contenuta in un'altra
  evidenziazione» (`riscrivi.senzaSovrapposizioni`).
- **Testo vuoto.** Un'evidenziazione con una nota aveva il testo vuoto nel sidecar: la
  selezione cominciava su un link nel titolo di un capitolo. Sul dispositivo il testo
  mancante si chiede a crengine (`getTextFromXPointers(pos0, pos1)`), su una copia della
  voce: le annotazioni di KOReader non cambiano (`Parergon:annotazioni`). Fuori dal
  dispositivo resta saltata come «testo vuoto».
- **Evidenziazione dentro un'altra, con una nota.** Sul Kindle la copia aveva 46
  evidenziazioni e non 47. Il passo del cap. 5, ritrovato grazie al testo chiesto a crengine,
  conteneva una sottolineatura con `#tempo-pieno`, che veniva scartata insieme al suo tema.
  Ora un'evidenziazione contenuta in un'altra non si avvolge una seconda volta, ma, se ha
  una nota o dei temi, li conserva: la nota (nel testo o con il richiamo) va dopo la fine
  dell'evidenziazione che la contiene, perché dentro sarebbe sottolineata anche lei, e
  l'indice punta a un'àncora all'inizio del passo contenuto. Il riepilogo la conta a parte
  («Evidenziazioni contenute in un'altra (nota e temi conservati)»). Quelle contenute senza
  nota restano saltate come «contenuta».
- **Asterisco finale nei temi.** `#logica-della-carenza*` era un refuso (lo ha confermato
  l'utente). Un `*` in fondo a un tema non fa parte del nome e, a differenza della
  punteggiatura, non resta nel testo (`note.separaPunteggiatura`).

