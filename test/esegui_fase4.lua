--[[
Test della fase 4 (note del lettore nel testo), fuori dal dispositivo.

Uso (dalla cartella del progetto):
    python test/crea_epub.py && python test/crea_epub.py --store && python test/crea_epub2.py
    luajit test/esegui_fase4.lua

Produce anche, per la verifica visiva sul dispositivo:
    test/uscita/Note di prova (annotated).epub
    test/uscita/Note a comparsa EPUB 2 (annotated).epub
]]

package.path = "parergon.koplugin/?.lua;test/?.lua;" .. package.path

local i18n = require("parergon/i18n")
i18n.configura{ modo = "en", cartella = "parergon.koplugin/" }
local copia = require("parergon/copia")
local corrisp = require("parergon/corrisp")
local note = require("parergon/note")
local riscrivi = require("parergon/riscrivi")
local xmltok = require("parergon/xmltok")
local zip = require("parergon/zip")

local superati, falliti = 0, 0
local function sezione(nome) print("\n## " .. nome) end
local function verifica(cond, descr, dettaglio)
    if cond then superati = superati + 1 print("  ok   " .. descr)
    else falliti = falliti + 1 print("  FAIL " .. descr .. (dettaglio and ("\n       " .. tostring(dettaglio)) or "")) end
end
local function uguale(a, b, descr)
    verifica(a == b, descr, "atteso: " .. tostring(b) .. "\n       ottenuto: " .. tostring(a))
end
local function leggiFile(p)
    local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s
end
local function lettoreCartella(radice)
    return { leggi = function(nome)
        local f = io.open(radice .. "/" .. nome, "rb")
        if not f then return nil, "assente" end
        local s = f:read("*a") f:close() return s
    end }
end
local USCITA = "test/uscita/"
os.execute(package.config:sub(1, 1) == "\\" and 'mkdir "test\\uscita" 2>nul' or "mkdir -p test/uscita")

--- Copia senza compressione e lettura diretta dei file modificati.
local function crea(annotazioni, opzioni, nome, suffisso)
    local dest = USCITA .. (nome or "fase4.epub")
    local r, e = copia.crea{
        originale = "test/libro-prova-store.epub", lettore = lettoreCartella("test/libro-prova"),
        annotazioni = annotazioni, opzioni = opzioni, destinazione = dest, suffisso = suffisso or " (annotated)",
    }
    assert(r, e)
    local arch = assert(zip.apri(dest))
    return r, function(n) return zip.leggiNonCompresso(arch, n) end, dest
end
local function verificaPython(percorso)
    local r = os.execute('python test/verifica_epub.py "' .. percorso .. '"')
    return r == 0 or r == true
end

local C1 = "/body/DocFragment[3]/body/section[1]/"
local C2 = "/body/DocFragment[4]/body/div[1]/"

-- ---------------------------------------------------------------------------
sezione("note.lua")
-- ---------------------------------------------------------------------------
do
    local n = note.analizza({ note = "  Una nota semplice.  " })
    uguale(n.corpo, "Una nota semplice.", "nota semplice, spazi tolti")
    uguale(n.titolo, nil, "senza titolo")
    n = note.analizza({ note = "# Il tema del viaggio\nL'autore riprende il capitolo 1." })
    uguale(n.titolo, "Il tema del viaggio", "titolo con #")
    uguale(n.corpo, "L'autore riprende il capitolo 1.", "corpo dopo il titolo")
    n = note.analizza({ note = "## Solo titolo" })
    uguale(n.titolo, "Solo titolo", "titolo con ##")
    uguale(n.corpo, "", "nota fatta solo del titolo: nessun corpo")
    verifica(note.analizza({ note = "   \n  " }).vuota, "nota di soli spazi = vuota")
    verifica(note.analizza({}).vuota, "nessuna nota = vuota")
    n = note.analizza({ note = "<p>Prima <b>riga</b></p><p>Seconda &amp; ultima</p>", note_format = "html" })
    uguale(n.corpo, "Prima riga\nSeconda & ultima", "nota HTML: solo testo, paragrafi a capo")
    n = note.analizza({ note = "**Importante**: vedi [qui](http://x) e `codice`\n- punto", note_format = "md" })
    uguale(n.corpo, "Importante: vedi qui e codice\n• punto", "nota Markdown: solo testo")
    uguale(note.xhtml("a < b & c\n\n\nseconda riga"), "[a &lt; b &amp; c<br/>seconda riga]", "XHTML: escape, a capo, righe vuote")
    uguale(note.xhtml(""), nil, "corpo vuoto: niente da inserire")
    n = note.analizza({ note = "riga 1\r\nriga 2" })
    uguale(n.corpo, "riga 1\nriga 2", "a capo Windows")
end

sezione("note.lua — temi della patch «Indice tematico»")
do
    -- note reali trovate sul Kindle (22/11/2026)
    local n = note.analizza({ note = "#Costituzione" })
    uguale(table.concat(n.temi, ","), "Costituzione", "nota fatta solo di un tema")
    uguale(n.corpo, "", "  nessun testo da inserire nel libro")
    uguale(n.titolo, nil, "  un tema non è un titolo")
    verifica(not n.vuota, "  la nota non è vuota (ha un tema)")
    -- formato scritto dalla patch: "#tema\n" davanti alla nota esistente
    n = note.analizza({ note = "#viaggi/mare\n#digitale\nSicuro?" })
    uguale(table.concat(n.temi, ","), "viaggi/mare,digitale", "più temi, anche annidati")
    uguale(n.corpo, "Sicuro?", "  il commento resta, senza i temi")
    n = note.analizza({ note = "Vedi anche #digitale, e #scuola." })
    uguale(n.corpo, "Vedi anche, e.", "tema in mezzo alla frase: tolto dal testo")
    n = note.analizza({ note = "# Il tema del viaggio\n#viaggi\nRitorna nel capitolo 3." })
    uguale(n.titolo, "Il tema del viaggio", "titolo con spazio dopo #")
    uguale(table.concat(n.temi, ","), "viaggi", "  e tema")
    uguale(n.corpo, "Ritorna nel capitolo 3.", "  e commento")
    n = note.analizza({ note = "#a #a #b" })
    uguale(table.concat(n.temi, ","), "a,b", "temi senza doppioni")
    -- nota reale: asterisco finale per errore di battitura
    n = note.analizza({ note = "#logica-della-carenza*" })
    uguale(table.concat(n.temi, ","), "logica-della-carenza", "asterisco finale: non fa parte del tema")
    uguale(n.corpo, "", "  e non resta nel testo")
    n = note.analizza({ note = "Vedi #scuola*, poi" })
    uguale(table.concat(n.temi, ","), "scuola", "asterisco prima della punteggiatura")
    uguale(n.corpo, "Vedi, poi", "  la virgola resta, l'asterisco no")
    n = note.analizza({ note = "#logica-della-carenza #logica-della-carenza*" })
    uguale(#n.temi, 1, "con e senza asterisco: lo stesso tema")
end

-- ---------------------------------------------------------------------------
sezione("riscrivi.puntoNota — dove va la nota")
-- ---------------------------------------------------------------------------
do
    local src = leggiFile("test/libro-prova/OEBPS/testo/cap2.xhtml")
    local doc = assert(xmltok.analizza(src))
    -- il passo finisce dentro un link: la nota va dopo </a>
    local r = corrisp.trova(doc, { text = "con un collegamento",
        pos0 = C2 .. "p[1]/text()[1].13", pos1 = C2 .. "p[1]/a[1]/text()[1].12" })
    assert(r.ok, r.motivo)
    local pos = riscrivi.puntoNota(r)
    uguale(src:sub(pos - 4, pos - 1), "</a>", "passo che finisce in un link: nota dopo </a>")
    -- il passo finisce dentro il richiamo di nota <sup><a>1</a></sup>: nota dopo </sup>
    r = corrisp.trova(doc, { text = "una nota1",
        pos0 = C2 .. "p[1]/text()[2].11", pos1 = C2 .. "p[1]/sup[1]/a[1]/text()[1].1" })
    assert(r.ok, r.motivo)
    pos = riscrivi.puntoNota(r)
    uguale(src:sub(pos - 6, pos - 1), "</sup>", "passo che finisce nel richiamo di nota: nota dopo </sup>")
    -- il passo finisce dentro un corsivo: la nota resta accanto, dentro il corsivo
    local src1 = leggiFile("test/libro-prova/OEBPS/testo/cap1.xhtml")
    local doc1 = assert(xmltok.analizza(src1))
    r = corrisp.trova(doc1, { text = "Il cammino",
        pos0 = C1 .. "p[2]/text()[1].0", pos1 = C1 .. "p[2]/i[1]/text()[1].7" })
    assert(r.ok, r.motivo)
    pos = riscrivi.puntoNota(r)
    uguale(src1:sub(pos, pos + 3), "</i>", "passo che finisce in un corsivo: nota subito dopo il testo")
end

-- ---------------------------------------------------------------------------
sezione("copia.lua — note nel testo")
-- ---------------------------------------------------------------------------
local base = {
    { drawer = "underscore", color = "red", text = "per una selva oscura", note = "Inizio celebre",
      pos0 = C1 .. "p[1]/text()[1].48", pos1 = C1 .. "p[1]/text()[1].68" },
    { drawer = "lighten", color = "yellow", text = "cammino della vita",
      note = "# Il tema del viaggio\nRitorna nel capitolo 3.",
      pos0 = C1 .. "p[2]/i[1]/text()[1].0", pos1 = C1 .. "p[2]/text()[2].11" },
    { drawer = "lighten", text = "Gertrude Stein", note = "# Solo un titolo",
      pos0 = C1 .. "p[4]/text()[1].40", pos1 = C1 .. "p[4]/text()[1].54" },
    { drawer = "lighten", text = "testo normale", note = "Prima riga della nota\nseconda riga < & >",
      pos0 = C1 .. "p[6]/text()[1].7", pos1 = C1 .. "p[6]/text()[1].20" },
    { drawer = "lighten", text = "una nota1 a piè di", note = "<p>Nota in <i>HTML</i></p>", note_format = "html",
      pos0 = C2 .. "p[1]/text()[2].11", pos1 = C2 .. "p[1]/text()[3].12" },
    { drawer = "lighten", text = "vive mille vite",
      pos0 = C2 .. "div[1]/p[1]/text()[1].10", pos1 = C2 .. "div[1]/p[1]/text()[1].25" },
    { page = C1 .. "p[1]/text()[1].0", text = "in Capitolo primo", note = "Nota su un segnalibro" },
    { drawer = "lighten", text = "frase inesistente", note = "Nota persa",
      pos0 = C1 .. "p[1]/text()[1].0", pos1 = C1 .. "p[1]/text()[1].5" },
}

do
    -- titolo distinto, per riconoscerlo sul dispositivo fra gli altri file di prova
    local r, leggi, dest = crea(base, nil, "Note di prova (annotated).epub", " — note di prova")
    uguale(r.evidenziazioni, 6, "evidenziazioni scritte")
    uguale(r.note, 4, "note scritte (il solo titolo # non va nel testo)")
    uguale(#r.saltate, 2, "saltate: il segnalibro e il passo inesistente")
    local codici = {}
    for __, s in ipairs(r.saltate) do codici[s.codice] = true end
    verifica(codici.segnalibro and codici.assente, "motivi: segnalibro di pagina, testo assente")
    local cap1 = leggi("OEBPS/testo/cap1.xhtml")
    verifica(cap1:find('oscura</span> <span class="parergon-note">[Inizio celebre]</span>.', 1, true),
        "nota subito dopo il passo, prima del punto")
    verifica(cap1:find('della vita</span> <span class="parergon-note">[Ritorna nel capitolo 3.]</span>', 1, true),
        "con il titolo #: nel testo va solo il corpo")
    verifica(not cap1:find("Il tema del viaggio", 1, true), "il titolo # non compare nel testo")
    verifica(cap1:find('Gertrude Stein</span>.</p>', 1, true), "nota fatta solo di titolo: nessuna nota nel testo")
    verifica(cap1:find('[Prima riga della nota<br/>seconda riga &lt; &amp; &gt;]', 1, true),
        "nota su due righe, caratteri speciali protetti")
    local cap2 = leggi("OEBPS/testo/cap2.xhtml")
    verifica(cap2:find('a piè di</span> <span class="parergon-note">[Nota in HTML]</span> pagina', 1, true),
        "nota HTML ridotta a testo")
    local css = leggi("OEBPS/parergon.css")
    verifica(css:find(".parergon-note { font-style: italic", 1, true), "CSS della nota: corsivo")
    verifica(css:find(".parergon-note { -cr-only-if: never; color:", 1, true), "CSS della nota: colore per i motori web")
    verifica(verificaPython(dest), "EPUB valido (verifica indipendente)")
    print("\n" .. copia.riepilogo(r))
end

do
    -- solo le annotazioni con una nota
    local r, leggi, dest = crea(base, { filtro = "con_nota" })
    uguale(r.escluse, 1, "esclusa l'annotazione senza nota")
    local cap2 = leggi("OEBPS/testo/cap2.xhtml")
    verifica(not cap2:find("vive mille vite</span>", 1, true), "l'annotazione senza nota non è evidenziata")
    verifica(copia.riepilogo(r):find("Not included (no note): 1", 1, true), "riepilogo: non incluse")
    verifica(verificaPython(dest), "EPUB valido")
end

do
    -- solo le note, senza evidenziazioni
    local r, leggi, dest = crea(base, { evidenziazioni = false })
    uguale(r.evidenziazioni, 0, "nessuna evidenziazione")
    uguale(r.note, 4, "le note ci sono")
    local cap1 = leggi("OEBPS/testo/cap1.xhtml")
    verifica(not cap1:find("parergon-hl", 1, true) and not cap1:find("parergon-ul", 1, true),
        "nessuno span di evidenziazione")
    verifica(cap1:find('oscura <span class="parergon-note">[Inizio celebre]</span>.', 1, true), "nota accanto al passo")
    local css = leggi("OEBPS/parergon.css")
    verifica(css:find("parergon-note", 1, true) and not css:find("parergon-hl", 1, true), "CSS con le sole note")
    verifica(verificaPython(dest), "EPUB valido")
end

do
    -- solo evidenziazioni: nessuna nota, nessuna regola per le note
    local r, leggi = crea(base, { note = false })
    uguale(r.note, 0, "note disattivate")
    verifica(not leggi("OEBPS/testo/cap1.xhtml"):find("parergon-note", 1, true), "nessuna nota nel testo")
    verifica(not leggi("OEBPS/parergon.css"):find("parergon-note", 1, true), "nessuna regola per le note")
    os.remove(USCITA .. "fase4.epub")
end

-- ---------------------------------------------------------------------------
sezione("note a comparsa")
-- ---------------------------------------------------------------------------
do
    -- prefisso epub: dichiarato solo se manca (XHTML EPUB 2)
    local d2 = assert(xmltok.analizza('<html xmlns="http://www.w3.org/1999/xhtml"><body/></html>'))
    local ins = riscrivi.dichiaraEpub(d2)
    uguale(riscrivi.applica(d2.src, { ins }),
        '<html xmlns:epub="http://www.idpf.org/2007/ops" xmlns="http://www.w3.org/1999/xhtml"><body/></html>',
        "dichiara xmlns:epub quando manca")
    local d3 = assert(xmltok.analizza('<html xmlns:epub="http://www.idpf.org/2007/ops"><body/></html>'))
    uguale(riscrivi.dichiaraEpub(d3), nil, "non lo ripete se c'è già")
end

-- i due file per la prova sul dispositivo vengono generati in italiano
i18n.configura{ modo = "it" }
for __, var in ipairs({ { "apice", "Note a comparsa (annotated).epub", " — note a comparsa" },
                        { "linea", "Note a comparsa sulla riga (annotated).epub", " — note a comparsa sulla riga" } }) do
    local dest = USCITA .. var[2]
    local r, e = copia.crea{
        originale = "test/libro-prova-store.epub", lettore = lettoreCartella("test/libro-prova"),
        annotazioni = base, opzioni = { note_modo = "comparsa" }, imp = { richiamo = var[1] },
        destinazione = dest, suffisso = var[3],
    }
    verifica(r, "copia con note a comparsa (" .. var[1] .. ")", e)
    if r then
        local arch = assert(zip.apri(dest))
        local leggi = function(n) return zip.leggiNonCompresso(arch, n) end
        uguale(r.note, 4, "  quattro note a comparsa")
        local cap1 = leggi("OEBPS/testo/cap1.xhtml")
        verifica(cap1:find('oscura</span><a class="parergon-noteref" id="parergon-r-1" href="../parergon-notes.xhtml#parergon-n-1" epub:type="noteref" role="doc-noteref">[1]</a>.', 1, true),
            "  richiamo [1] subito dopo il passo, con epub:type e role")
        verifica(not cap1:find("parergon-note\"", 1, true), "  nessuna nota tra parentesi nel testo")
        local cap2 = leggi("OEBPS/testo/cap2.xhtml")
        verifica(cap2:find('a piè di</span><a class="parergon-noteref" id="parergon-r-4"', 1, true),
            "  numerazione continua fra i capitoli")
        local pagina = leggi("OEBPS/parergon-notes.xhtml")
        verifica(pagina, "  pagina «Note del lettore» presente")
        verifica(pagina:find('<div class="parergon-endnote" id="parergon-n-1">', 1, true),
            "  voce con id (senza role doc-endnote, che KOReader rimpicciolirebbe)")
        verifica(not pagina:find("doc-endnote\"", 1, true), "  nessun role=\"doc-endnote\" sulle voci")
        verifica(pagina:find('href="testo/cap1.xhtml#parergon-r-1" role="doc-backlink">[1]</a> Inizio celebre</p>', 1, true),
            "  numero che riporta al passo, poi la nota")
        verifica(pagina:find("«per una selva oscura»", 1, true), "  il passo citato sotto la nota")
        verifica(pagina:find("Prima riga della nota<br/>seconda riga &lt; &amp; &gt;", 1, true), "  nota su due righe")
        verifica(pagina:find('lang="it"', 1, true), "  lingua del libro")
        verifica(pagina:find("<title>Note del lettore</title>", 1, true), "  titolo della pagina (in italiano)")
        local opf = leggi("OEBPS/content.opf")
        verifica(opf:find('<item id="parergon-notes" href="parergon-notes.xhtml" media-type="application/xhtml+xml"/>', 1, true),
            "  pagina nel manifest")
        verifica(opf:find('    <itemref idref="parergon-notes"/>\n  </spine>', 1, true), "  pagina in fondo allo spine")
        local css = leggi("OEBPS/parergon.css")
        local atteso = var[1] == "linea" and "vertical-align: baseline;" or "vertical-align: super;"
        verifica(css:find(".parergon-noteref { " .. (var[1] == "linea" and "font-size: 0.9em; " or "font-size: 0.8em; ") .. atteso, 1, true),
            "  CSS del richiamo (" .. var[1] .. ")")
        verifica(verificaPython(dest), "  EPUB valido, link di andata e ritorno risolti")
    end
end

i18n.configura{ modo = "en" }

do
    -- note nel testo senza corsivo
    local r, leggi = crea(base, { corsivo = false })
    verifica(leggi("OEBPS/parergon.css"):find(".parergon-note { font-style: normal;", 1, true), "note in tondo")
    os.remove(USCITA .. "fase4.epub")
end

do
    -- senza indicazioni il richiamo sta sulla riga (scelta fatta dopo la prova sul Kindle)
    local r, leggi = crea(base, { note_modo = "comparsa" })
    verifica(leggi("OEBPS/parergon.css"):find(".parergon-noteref { font-size: 0.9em; vertical-align: baseline;", 1, true),
        "richiamo predefinito: sulla riga")
    os.remove(USCITA .. "fase4.epub")
end

-- ---------------------------------------------------------------------------
sezione("libro EPUB 2 (XHTML 1.1): copia valida anche per epubcheck")
-- ---------------------------------------------------------------------------
do
    -- test/crea_epub2.py: stesso libro, pacchetto 2.0, <div> al posto di <section>
    local ann = {}
    for i, a in ipairs(base) do
        local c = {}
        for k, x in pairs(a) do c[k] = type(x) == "string" and x:gsub("section", "div") or x end
        ann[i] = c
    end
    ann[1].note = "#viaggi/mare-aperto\nInizio celebre"
    i18n.configura{ modo = "it" }
    local dest = USCITA .. "Note a comparsa EPUB 2 (annotated).epub"
    local r = assert(copia.crea{
        originale = "test/libro-prova-epub2.epub", lettore = lettoreCartella("test/libro-prova-epub2"),
        annotazioni = ann, destinazione = dest, suffisso = " — note a comparsa, EPUB 2",
        opzioni = { note_modo = "comparsa", indice = true, indice_toc_sottotemi = true,
                    frase_lettore = "Letto da Prova nel novembre 2026" },
    })
    i18n.configura{ modo = "en" }
    uguale(r.note, 4, "quattro note a comparsa (come in EPUB 3)")
    local arch = assert(zip.apri(dest))
    local function leggi(n) return zip.leggiNonCompresso(arch, n) end
    local cap1 = leggi("OEBPS/testo/cap1.xhtml")
    verifica(cap1:find('<a class="parergon-noteref" id="parergon-r-1" href="../parergon-notes.xhtml#parergon-n-1">[1]</a>', 1, true),
        "richiamo senza epub:type né role")
    verifica(not cap1:find("xmlns:epub", 1, true), "nessun prefisso epub aggiunto al capitolo")
    for __, n in ipairs({ "OEBPS/parergon-notes.xhtml", "OEBPS/parergon-index.xhtml" }) do
        local s = leggi(n)
        verifica(s:find('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"', 1, true), n .. ": DOCTYPE XHTML 1.1")
        verifica(not s:find("<section", 1, true) and not s:find("epub:", 1, true) and not s:find("role=", 1, true)
            and not s:find(" lang=", 1, true), n .. ": niente section, epub:type, role, lang")
    end
    verifica(verificaPython(dest), "EPUB valido, link risolti")
end

print(string.format("\n%d superati, %d falliti", superati, falliti))
os.exit(falliti == 0 and 0 or 1)
