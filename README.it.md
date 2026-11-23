# Parergon

*[English](README.md) · Italiano*

**Parergon** è un plugin per [KOReader](https://koreader.rocks) che scrive le tue
evidenziazioni, le tue note e un indice personale dentro una **copia** del libro EPUB.
Le annotazioni di KOReader vivono in un file a parte e si vedono solo in KOReader. Nella
copia diventano parte del libro: si vedono in qualsiasi applicazione di lettura, si possono
stampare, condividere o archiviare.

L'originale e le sue annotazioni non vengono mai modificati.

Il nome viene dal greco *pàrergon*, «ciò che sta accanto all'opera».

## Cosa fa

- **Evidenziazioni e sottolineature** scritte nel testo, con lo stile di KOReader oppure con
  uno stile scelto da te: sfondo, sottolineatura continua, tratteggiata o a zigzag, anche
  diverso per ogni colore. Per gli schermi in bianco e nero c'è un'opzione in grigio
  uniforme.
- **Note del lettore**, in due modi:
  - nel testo, subito dopo il passo, tra parentesi quadre e se vuoi in corsivo;
  - a comparsa: un richiamo `[1]` nel testo porta alla nota, raccolta in una pagina «Note del
    lettore» in fondo al libro, con il link di ritorno al passo.
- **Indice personale** in fondo al libro e nell'indice (TOC) del libro, organizzato per
  temi che scrivi nelle note (vedi sotto).
- **Nota di lettura** nel frontespizio, per esempio «Letto e annotato da Maria nel novembre
  2026». La frase si può modificare prima di creare la copia.
- **Analisi** delle annotazioni senza modificare nulla: per ognuna dice dove si trova nel
  libro e, se non si può scrivere, perché.

La copia si chiama `Titolo (annotato).epub` e sta nella stessa cartella dell'originale.
Ha un identificatore proprio, così le applicazioni di lettura non la confondono con
l'originale. Se ricrei la copia, quella nuova sostituisce la precedente. Parergon ti
avvisa se la vecchia copia contiene annotazioni fatte direttamente su di essa.

## Requisiti

- KOReader **2024.07** o successivo, su qualsiasi dispositivo: Kindle con jailbreak, Kobo,
  PocketBook, BOOX e altri Android, Linux, macOS, Windows.
- Libri **EPUB** (2 o 3) senza DRM. I libri protetti vengono rifiutati.

## Installazione

1. Scarica `parergon-<versione>.zip` dall'[ultima release](../../releases/latest) e
   decomprimilo: ottieni la cartella `parergon.koplugin`.
2. Copia la cartella nella cartella `plugins` di KOReader:

   | Dispositivo | Cartella |
   |---|---|
   | Kindle | `koreader/plugins/` nella memoria del Kindle collegato al computer |
   | Kobo | `.adds/koreader/plugins/` |
   | PocketBook | `applications/koreader/plugins/` |
   | BOOX e altri Android | `koreader/plugins/` nella memoria interna |

3. Riavvia KOReader.

Il plugin compare in **Strumenti → Parergon**, a libro aperto. Puoi anche assegnarlo a un
gesto: *Parergon: scrivi le annotazioni nel libro*.

## Uso

1. Leggi e annota il libro in KOReader come al solito.
2. Apri **Strumenti → Parergon → Crea la copia consolidata…**.
3. Scegli che cosa scrivere nella copia: evidenziazioni, note (nel testo o a comparsa),
   indice personale, nota di lettura, tutte le annotazioni o solo quelle con una nota.
   Le scelte vengono ricordate.
4. Tocca **Crea**. Alla fine Parergon mostra un riepilogo e propone di aprire la copia.

Le altre voci del menu sono **Analizza le annotazioni**, **Stile delle evidenziazioni**,
**Stile per colore**, **Colori**, **Richiamo delle note a comparsa** (sulla riga o in
apice) e **Lingua**. La lingua è automatica (come KOReader), inglese o italiano.

### Note a comparsa in KOReader

Per vedere le note in una finestrella invece di saltare alla pagina delle note, attiva in
KOReader *Impostazioni → Tocchi e gesti → Collegamenti → Show footnotes in popup*. Di
default l'opzione è spenta. Con l'opzione attiva, la nota compare in fondo alla pagina.

## Indice personale e temi

Nelle note puoi scrivere dei **temi** con il cancelletto attaccato alla parola:

```
#viaggi
#arte/arte-greca
Il passo che riprende il primo capitolo.
```

- `#tema` assegna l'annotazione a un tema. `#tema/sottotema` la mette in un sotto-tema.
  Un'annotazione con più temi compare sotto ciascuno.
- I temi non vengono mai scritti nel testo del libro: nella copia resta solo il commento.
- Nell'indice trattini e trattini bassi diventano spazi: `#arte-greca` si legge «arte
  greca».
- Una riga `# Titolo`, con lo spazio dopo il cancelletto, dà il titolo alla voce
  dell'indice. Senza, il titolo è la prima riga del commento oppure l'inizio del passo.
- Le annotazioni senza tema vanno in «Altre annotazioni». Se nessuna nota ha un tema,
  l'indice è ordinato per capitolo.

Puoi scegliere quali annotazioni mettere nell'indice (tutte, quelle con un tema, quelle
con una nota) e se ordinare i temi alfabeticamente o nell'ordine del libro. Nell'indice
del libro compaiono i temi e, se vuoi, anche i sotto-temi (opzione *Sotto-temi nell'indice
del libro*).

Se usi già un modo per scrivere `#tema` nelle note, per esempio una patch utente di
KOReader, Parergon lo riconosce: la convenzione è la stessa.

## Limiti noti

- Un passo che continua in un altro capitolo, cioè in un altro file del libro, non viene
  scritto. I passi su più paragrafi dello stesso capitolo invece sì.
- Due evidenziazioni sovrapposte: viene scritta la prima (a parità di inizio, la più
  lunga), l'altra viene saltata e indicata nel riepilogo. Se una è tutta dentro l'altra e ha
  una nota o dei temi, la nota e i temi si conservano: la nota compare dopo la fine
  dell'evidenziazione più lunga.
- Se un passo compare più volte nello stesso paragrafo e la posizione è incerta, Parergon
  preferisce saltarlo piuttosto che sottolineare il punto sbagliato.
- Un'evidenziazione il cui testo è stato modificato in KOReader può non essere ritrovata.
- I lettori che non usano il motore di KOReader possono mostrare gli stili in modo un po'
  diverso. Per i lettori in bianco e nero di Kobo e PocketBook conviene l'opzione *Grigio
  uniforme*.

Ogni annotazione saltata è elencata, con il motivo, nel riepilogo e nell'analisi.

## Licenza

Copyright © 2026 Antonio Vigilante.

[GNU Affero General Public License v3.0](parergon.koplugin/LICENSE) o successiva, la
stessa di KOReader.
