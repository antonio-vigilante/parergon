--[[
Annotazioni di prova per test/libro-prova, scritte come le produrrebbe KOReader
(XPointer con DOM 20260812: indici [1] espliciti).

Spine del libro di prova: 1 copertina, 2 frontespizio, 3 cap1, 4 cap2.

Ogni voce ha un campo `atteso`:
  ok        — true se deve essere trovata
  segmenti  — numero di segmenti attesi (nodi di testo attraversati)
  passo     — testo normalizzato che deve risultare sottolineato
  metodo    — sottostringa attesa nel metodo, in inglese (facoltativa)
  ricerca   — true se deve essere trovata con la ricerca nel file
  codice    — codice del motivo dello scarto (se ok = false)
]]
local C1 = "/body/DocFragment[3]/body/section[1]/"
local C2 = "/body/DocFragment[4]/body/div[1]/"

return {
    {
        nome = "passo semplice",
        pos0 = C1 .. "p[1]/text()[1].48", pos1 = C1 .. "p[1]/text()[1].68",
        text = "per una selva oscura", note = "Inizio celebre", drawer = "underscore", color = "red",
        atteso = { ok = true, segmenti = 1, passo = "per una selva oscura", metodo = "text confirmed" },
    },
    {
        nome = "passo che attraversa un corsivo",
        pos0 = C1 .. "p[2]/i[1]/text()[1].0", pos1 = C1 .. "p[2]/text()[2].11",
        text = "cammino della vita", drawer = "lighten", color = "yellow",
        atteso = { ok = true, segmenti = 2, passo = "cammino della vita" },
    },
    {
        nome = "entità e spazio non separabile",
        pos0 = C1 .. "p[3]/text()[1].0", pos1 = C1 .. "p[3]/text()[1].33",
        text = "L\u{2019}uomo & la natura\u{A0}: un rapporto", drawer = "lighten", color = "yellow",
        atteso = { ok = true, segmenti = 1, passo = "L\u{2019}uomo & la natura : un rapporto" },
    },
    {
        nome = "testo ripetuto, seconda occorrenza scelta per posizione",
        pos0 = C1 .. "p[4]/text()[1].21", pos1 = C1 .. "p[4]/text()[1].29",
        text = "una rosa", note = "la seconda", drawer = "strikeout", color = "gray",
        atteso = { ok = true, segmenti = 1, passo = "una rosa", metodo = "chosen by position", da = 22 },
    },
    {
        nome = "testo ripetuto con posizione lontana: ambiguo",
        pos0 = C1 .. "p[4]/text()[1].45", pos1 = C1 .. "p[4]/text()[1].53",
        text = "una rosa", drawer = "lighten",
        atteso = { ok = false, codice = "ambiguo" },
    },
    {
        nome = "spazi irregolari e a capo nel sorgente",
        pos0 = C1 .. "p[5]/text()[1].20", pos1 = C1 .. "p[5]/text()[1].70",
        text = "scritto su più righe nel sorgente, con spazi irregolari", drawer = "lighten",
        atteso = { ok = true, segmenti = 1, passo = "scritto su più righe nel sorgente, con spazi irregolari" },
    },
    {
        nome = "nodo di spazi iniziale scartato da crengine (text()[1] dopo <b>)",
        pos0 = C1 .. "p[6]/text()[1].7", pos1 = C1 .. "p[6]/text()[1].20",
        text = "testo normale", drawer = "underscore",
        atteso = { ok = true, segmenti = 1, passo = "testo normale" },
    },
    {
        nome = "trattino morbido nel sorgente",
        pos0 = C1 .. "p[7]/text()[1].3", pos1 = C1 .. "p[7]/text()[1].25",
        text = "sottolineatura nascosta", drawer = "lighten",
        atteso = { ok = true, segmenti = 1, passo = "sottolineatura nascosta" },
    },
    {
        nome = "passo che attraversa un <br/>",
        pos0 = C1 .. "p[8]/text()[1].6", pos1 = C1 .. "p[8]/text()[2].12",
        text = "riga\nseconda riga", drawer = "lighten",
        atteso = { ok = true, segmenti = 2, passo = "riga seconda riga" },
    },
    {
        nome = "tre paragrafi, quello in mezzo intero",
        pos0 = C1 .. "p[8]/text()[2].13", pos1 = C1 .. "p[10]/text()[1].8",
        text = "del verso.\nQuesto paragrafo finisce qui.\nE questo", drawer = "lighten",
        atteso = { ok = true, segmenti = 3, passo = "del verso. Questo paragrafo finisce qui. E questo",
                   metodo = "across paragraphs" },
    },
    {
        nome = "dal titolo all'epigrafe (contenitori annidati, commento in mezzo)",
        pos0 = C2 .. "h2[1]/text()[1].9", pos1 = C2 .. "div[1]/p[1]/text()[1].9",
        text = "secondo\nChi legge", drawer = "underscore",
        atteso = { ok = true, segmenti = 2, passo = "secondo Chi legge", metodo = "across paragraphs" },
    },
    {
        nome = "più paragrafi, testo che non corrisponde",
        pos0 = C1 .. "p[9]/text()[1].18", pos1 = C1 .. "p[10]/text()[1].10",
        text = "finisce qui.\nE quello", drawer = "lighten",
        atteso = { ok = false, codice = "assente" },
    },
    {
        nome = "più paragrafi in ordine rovesciato",
        pos0 = C1 .. "p[10]/text()[1].0", pos1 = C1 .. "p[9]/text()[1].10",
        text = "finisce qui.\nE questo", drawer = "lighten",
        atteso = { ok = false, codice = "paragrafi" },
    },
    {
        nome = "testo assente",
        pos0 = C1 .. "p[1]/text()[1].0", pos1 = C1 .. "p[1]/text()[1].10",
        text = "frase che non esiste", drawer = "lighten",
        atteso = { ok = false, codice = "assente" },
    },
    {
        nome = "percorso sbagliato ma testo unico: ricerca nel file",
        pos0 = C1 .. "p[99]/text()[1].40", pos1 = C1 .. "p[99]/text()[1].54",
        text = "Gertrude Stein", drawer = "lighten",
        atteso = { ok = true, segmenti = 1, passo = "Gertrude Stein", ricerca = true },
    },
    {
        nome = "XPointer vecchio stile (senza [1])",
        pos0 = "/body/DocFragment[3]/body/section/p[1]/text().4",
        pos1 = "/body/DocFragment[3]/body/section/p[1]/text().20",
        text = "mezzo del cammin", drawer = "lighten",
        atteso = { ok = true, segmenti = 1, passo = "mezzo del cammin" },
    },
    {
        nome = "paragrafo dentro div annidati",
        pos0 = C2 .. "div[1]/p[1]/text()[1].10", pos1 = C2 .. "div[1]/p[1]/text()[1].25",
        text = "vive mille vite", drawer = "underscore",
        atteso = { ok = true, segmenti = 1, passo = "vive mille vite" },
    },
    {
        nome = "passo che attraversa il richiamo di nota (<sup><a>)",
        pos0 = C2 .. "p[1]/text()[2].11", pos1 = C2 .. "p[1]/text()[3].12",
        text = "una nota1 a piè di", drawer = "lighten",
        atteso = { ok = true, segmenti = 3, passo = "una nota1 a piè di" },
    },
    {
        nome = "segnalibro di pagina (senza drawer): ignorato",
        page = C1 .. "p[1]/text()[1].0", text = "in Capitolo primo",
        atteso = { ignorata = true },
    },
}
