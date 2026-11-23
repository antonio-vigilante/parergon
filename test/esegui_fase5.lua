--[[
Test della fase 5 (indice personale, TOC, nota di lettura), fuori dal dispositivo.

Uso (dalla cartella del progetto):
    python test/crea_epub.py && python test/crea_epub.py --store
    luajit test/esegui_fase5.lua

Produce anche, per la verifica visiva sul dispositivo (in italiano):
    test/uscita/Indice personale (annotated).epub
]]

package.path = "parergon.koplugin/?.lua;test/?.lua;" .. package.path

local i18n = require("parergon/i18n")
i18n.configura{ modo = "en", cartella = "parergon.koplugin/" }
local copia = require("parergon/copia")
local data = require("parergon/data")
local frontespizio = require("parergon/frontespizio")
local epub = require("parergon/epub")
local indice = require("parergon/indice")
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
local function lettoreCartella(radice, sostituzioni)
    return { leggi = function(nome)
        if sostituzioni and sostituzioni[nome] then return sostituzioni[nome] end
        local f = io.open(radice .. "/" .. nome, "rb")
        if not f then return nil, "assente" end
        local s = f:read("*a") f:close() return s
    end }
end
local function leggiFile(p)
    local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s
end
local function verificaPython(percorso)
    local r = os.execute('python test/verifica_epub.py "' .. percorso .. '"')
    return r == 0 or r == true
end
local USCITA = "test/uscita/"
os.execute(package.config:sub(1, 1) == "\\" and 'mkdir "test\\uscita" 2>nul' or "mkdir -p test/uscita")

local C1 = "/body/DocFragment[3]/body/section[1]/"
local C2 = "/body/DocFragment[4]/body/div[1]/"

-- annotazioni con temi (come li scrive la patch «Indice tematico»)
local base = {
    { drawer = "underscore", color = "red", text = "per una selva oscura", chapter = "Capitolo primo",
      note = "#viaggi/mare\nInizio celebre",
      pos0 = C1 .. "p[1]/text()[1].48", pos1 = C1 .. "p[1]/text()[1].68" },
    { drawer = "lighten", text = "cammino della vita", chapter = "Capitolo primo",
      note = "# Il tema del viaggio\n#viaggi\nRitorna nel capitolo 3.",
      pos0 = C1 .. "p[2]/i[1]/text()[1].0", pos1 = C1 .. "p[2]/text()[2].11" },
    { drawer = "lighten", text = "Gertrude Stein", chapter = "Capitolo primo", note = "#arte #viaggi",
      pos0 = C1 .. "p[4]/text()[1].40", pos1 = C1 .. "p[4]/text()[1].54" },
    { drawer = "lighten", text = "testo normale", chapter = "Capitolo primo", note = "Una nota senza temi",
      pos0 = C1 .. "p[6]/text()[1].7", pos1 = C1 .. "p[6]/text()[1].20" },
    { drawer = "lighten", text = "vive mille vite", chapter = "Capitolo secondo",
      pos0 = C2 .. "div[1]/p[1]/text()[1].10", pos1 = C2 .. "div[1]/p[1]/text()[1].25" },
}

-- ---------------------------------------------------------------------------
sezione("data.lua")
-- ---------------------------------------------------------------------------
local function quando(m) return os.time{ year = 2026, month = m, day = 15, hour = 12 } end
uguale(data.meseAnno("it", quando(11)), "nel novembre 2026", "novembre")
uguale(data.meseAnno("it", quando(4)), "nell'aprile 2026", "aprile, con elisione")
uguale(data.meseAnno("it", quando(8)), "nell'agosto 2026", "agosto, con elisione")
uguale(data.meseAnno("it", quando(10)), "nell'ottobre 2026", "ottobre, con elisione")
uguale(data.meseAnno("en", quando(11)), "in November 2026", "inglese")
uguale(data.meseAnno("de", quando(1)), "in January 2026", "lingua senza tabella: inglese")

-- ---------------------------------------------------------------------------
sezione("indice.lua — struttura")
-- ---------------------------------------------------------------------------
do
    local voci = {}
    for i, a in ipairs(base) do voci[i] = { id = "m" .. i, file = "OEBPS/testo/cap1.xhtml", ann = a } end
    local s = indice.costruisci(voci, {})
    local nomi = {}
    for __, g in ipairs(s.gruppi) do nomi[#nomi + 1] = g.nome end
    uguale(table.concat(nomi, ","), "arte,viaggi,Other annotations", "temi in ordine alfabetico, poi le altre")
    local viaggi = s.gruppi[2]
    uguale(#viaggi.voci, 2, "voci direttamente sotto #viaggi")
    uguale(viaggi.figli[1] and viaggi.figli[1].nome, "mare", "sotto-tema viaggi/mare")
    uguale(indice.totale(viaggi), 3, "il conteggio del tema include i sotto-temi")
    uguale(viaggi.voci[1].titolo, "Il tema del viaggio", "titolo dalla riga «# Titolo»")
    uguale(viaggi.figli[1].voci[1].titolo, "Inizio celebre", "titolo dal commento")
    uguale(s.gruppi[1].voci[1].titolo, "Gertrude Stein", "senza commento: titolo dal passo")
    uguale(#s.gruppi[3].voci, 2, "due annotazioni senza tema")
    local p = indice.costruisci(voci, { ordine = "posizione" })
    uguale(p.gruppi[1].nome, "viaggi", "ordine del libro: viaggi compare per primo")
    local t = indice.costruisci(voci, { criterio = "con_tema" })
    uguale(t.n, 3, "solo con un tema")
    verifica(t.gruppi[#t.gruppi].nome ~= "Other annotations", "  niente «altre annotazioni»")
    local n = indice.costruisci(voci, { criterio = "con_nota" })
    uguale(n.n, 4, "solo con una nota")
    -- nessun tema: per capitolo
    local senza = {}
    for i, a in ipairs({ base[4], base[5] }) do senza[i] = { id = "x" .. i, file = "f", ann = a } end
    local c = indice.costruisci(senza, {})
    verifica(c.per_capitolo, "senza temi: raggruppato per capitolo")
    uguale(c.gruppi[1].nome .. "|" .. c.gruppi[2].nome, "Capitolo primo|Capitolo secondo", "  gruppi = capitoli")
end

-- ---------------------------------------------------------------------------
sezione("indice.lua — nomi dei temi leggibili")
-- ---------------------------------------------------------------------------
uguale(indice.nomeVisibile("arte-greca"), "arte greca", "trattino → spazio")
uguale(indice.nomeVisibile("arte_greca"), "arte greca", "trattino basso → spazio")
uguale(indice.nomeVisibile("storia--_antica"), "storia antica", "più separatori di fila → uno spazio")
uguale(indice.nomeVisibile("-arte-"), "arte", "separatori agli estremi tolti")
uguale(indice.nomeVisibile("-"), "-", "solo separatori: resta com'è")
uguale(indice.nomeVisibile("Arte"), "Arte", "maiuscole conservate")
do
    local function v(i, nota)
        return { id = "t" .. i, file = "f", ann = { drawer = "lighten", text = "passo " .. i, chapter = "C",
            note = nota, pos0 = "a", pos1 = "b" } }
    end
    local s = indice.costruisci({ v(1, "#arte/arte-greca"), v(2, "#arte/arte_greca"), v(3, "#storia_antica") }, {})
    uguale(#s.gruppi, 2, "due temi di primo livello")
    uguale(s.gruppi[2].nome, "storia antica", "tema di primo livello leggibile")
    local arte = s.gruppi[1]
    uguale(#arte.figli, 1, "#arte-greca e #arte_greca: un solo sotto-tema")
    uguale(arte.figli[1] and arte.figli[1].nome, "arte greca", "sotto-tema leggibile")
    uguale(arte.figli[1] and #arte.figli[1].voci, 2, "  con entrambe le voci")
end

-- ---------------------------------------------------------------------------
sezione("copia.lua — indice personale e TOC")
-- ---------------------------------------------------------------------------
local function crea(annotazioni, opzioni, nome, lettore, suffisso)
    local dest = USCITA .. (nome or "fase5.epub")
    local r, e = copia.crea{
        originale = "test/libro-prova-store.epub", lettore = lettore or lettoreCartella("test/libro-prova"),
        annotazioni = annotazioni, opzioni = opzioni, destinazione = dest, suffisso = suffisso or " (annotated)",
    }
    assert(r, e)
    local arch = assert(zip.apri(dest))
    return r, function(n) return zip.leggiNonCompresso(arch, n) or lettoreCartella("test/libro-prova").leggi(n) end, dest
end

do
    local r, leggi, dest = crea(base, { indice = true, note_modo = "comparsa" })
    uguale(r.indice, 5, "cinque voci nell'indice")
    uguale(r.indice_gruppi, 3, "tre gruppi di primo livello")
    local pagina = leggi("OEBPS/parergon-index.xhtml")
    verifica(pagina, "pagina dell'indice presente")
    verifica(pagina:find('<h2 class="parergon-index-group" id="parergon-g-2">viaggi <span class="parergon-index-count">(3)</span></h2>', 1, true),
        "gruppo con conteggio")
    verifica(pagina:find('<h3 class="parergon-index-group" id="parergon-g-3">mare', 1, true), "sotto-tema un livello sotto")
    verifica(pagina:find('<a href="testo/cap1.xhtml#parergon-2">Il tema del viaggio</a>', 1, true), "voce con link all'àncora")
    verifica(pagina:find("«cammino della vita» — Capitolo primo", 1, true), "passo e capitolo")
    verifica(pagina:find('<p class="parergon-index-note">Ritorna nel capitolo 3.</p>', 1, true),
        "commento sotto la voce (il titolo viene da «# Titolo»)")
    local nav = leggi("OEBPS/nav.xhtml")
    local orig_nav = leggiFile("test/libro-prova/OEBPS/nav.xhtml")
    verifica(nav:find('<li><a href="testo/cap3.xhtml">Campionario</a></li>\n      <li><a href="parergon-index.xhtml">Personal index</a>', 1, true),
        "nav: ramo «Indice personale» dopo le voci dell'autore")
    verifica(nav:find('<li><a href="parergon-index.xhtml#parergon-g-1">arte</a></li>', 1, true), "nav: i temi come sotto-voci")
    verifica(nav:find('<li><a href="parergon-notes.xhtml">Reader\'s notes</a></li>', 1, true), "nav: anche la pagina delle note")
    local _, n_landmarks = nav:gsub("epub:type=\"landmarks\"", "")
    uguale(n_landmarks, 1, "nav: landmarks intatti")
    verifica(nav:find(orig_nav:match("(<li><a href=\"testo/frontespizio.xhtml\">Frontespizio</a></li>)"), 1, true),
        "nav: voci dell'autore intatte")
    local ncx = leggi("OEBPS/toc.ncx")
    verifica(ncx:find('<navPoint id="parergon-np-1" playOrder="5"><navLabel><text>Personal index</text></navLabel><content src="parergon-index.xhtml"/>', 1, true),
        "ncx: navPoint con playOrder successivo")
    verifica(ncx:find('playOrder="6"><navLabel><text>arte</text>', 1, true), "ncx: temi come figli")
    verifica(ncx:find('<meta name="dtb:depth" content="2"/>', 1, true), "ncx: dtb:depth portato a 2")
    local opf = leggi("OEBPS/content.opf")
    verifica(opf:find('<itemref idref="parergon-index"/>\n    <itemref idref="parergon-notes"/>\n  </spine>', 1, true),
        "spine: indice e poi note, in fondo")
    verifica(verificaPython(dest), "EPUB valido: tutti i link dell'indice e della TOC arrivano a destinazione")
    verifica(not nav:find(">mare<", 1, true) and not ncx:find(">mare<", 1, true),
        "predefinito: niente sotto-temi nella TOC")
    print("\n" .. copia.riepilogo(r))
end

do
    -- opzione: sotto-temi anche nella TOC
    local r, leggi, dest = crea(base, { indice = true, indice_toc_sottotemi = true })
    local nav = leggi("OEBPS/nav.xhtml")
    verifica(nav:find('<li><a href="parergon-index.xhtml#parergon-g-2">viaggi</a>\n'
        .. '            <ol>\n'
        .. '              <li><a href="parergon-index.xhtml#parergon-g-3">mare</a></li>\n'
        .. '            </ol>\n'
        .. '          </li>', 1, true), "nav: sotto-tema dentro il suo tema")
    verifica(nav:find('<li><a href="parergon-index.xhtml#parergon-g-1">arte</a></li>', 1, true),
        "nav: tema senza sotto-temi resta una voce semplice")
    local ncx = leggi("OEBPS/toc.ncx")
    verifica(ncx:find('<text>mare</text></navLabel><content src="parergon-index.xhtml#parergon-g-3"/></navPoint>\n'
        .. '      </navPoint>', 1, true), "ncx: sotto-tema come figlio del tema")
    verifica(ncx:find('<meta name="dtb:depth" content="3"/>', 1, true), "ncx: dtb:depth portato a 3")
    verifica(verificaPython(dest), "EPUB valido con i sotto-temi nella TOC")
end

do
    -- solo indice: niente evidenziazioni né note, ma le àncore ci sono
    local r, leggi, dest = crea(base, { indice = true, evidenziazioni = false, note = false })
    uguale(r.indice, 5, "solo indice: cinque voci")
    local cap1 = leggi("OEBPS/testo/cap1.xhtml")
    verifica(cap1:find('mi ritrovai <span id="parergon-1"></span>per una selva oscura.', 1, true),
        "àncora vuota (scritta per esteso) davanti al passo")
    verifica(not cap1:find("parergon-hl", 1, true), "nessuna evidenziazione")
    verifica(verificaPython(dest), "EPUB valido, link alle àncore risolti")
end

do
    -- libro reale: una sottolineatura con un tema dentro un passo più lungo.
    -- Non si avvolge due volte, ma nota e tema restano; la nota va dopo il passo lungo.
    local ann = {
        { drawer = "lighten", text = "mi ritrovai per una selva oscura", note = "Commento del passo lungo",
          pos0 = C1 .. "p[1]/text()[1].36", pos1 = C1 .. "p[1]/text()[1].68" },
        { drawer = "underscore", text = "per una selva", note = "#viaggi\nDentro l'altra",
          pos0 = C1 .. "p[1]/text()[1].48", pos1 = C1 .. "p[1]/text()[1].61" },
        { drawer = "underscore", text = "una selva", -- contenuta e senza nota: saltata
          pos0 = C1 .. "p[1]/text()[1].52", pos1 = C1 .. "p[1]/text()[1].61" },
    }
    local r, leggi, dest = crea(ann, { indice = true })
    uguale(r.evidenziazioni, 1, "contenute: una sola evidenziazione scritta")
    uguale(r.assorbite, 1, "  quella con la nota è conservata")
    uguale(#r.saltate, 1, "  quella senza nota è saltata")
    uguale(r.saltate[1] and r.saltate[1].codice, "contenuta", "  come «contenuta»")
    uguale(r.note, 2, "  entrambe le note scritte")
    uguale(r.indice, 2, "  due voci nell'indice")
    local cap1 = leggi("OEBPS/testo/cap1.xhtml")
    verifica(cap1:find('<span class="parergon-hl-yellow" id="parergon-1">mi ritrovai <span id="parergon-2"></span>per una selva oscura</span>'
        .. ' <span class="parergon-note">[Commento del passo lungo]</span> <span class="parergon-note">[Dentro l\'altra]</span>', 1, true),
        "  àncora dentro il passo, note dopo la sua fine, nell'ordine")
    verifica(leggi("OEBPS/parergon-index.xhtml"):find('href="testo/cap1.xhtml#parergon-2"', 1, true),
        "  la voce del tema porta al passo contenuto")
    verifica(verificaPython(dest), "  EPUB valido")
    os.remove(dest)
end

-- ---------------------------------------------------------------------------
sezione("frontespizio.lua — nota di lettura")
-- ---------------------------------------------------------------------------
local FRASE = "Letto e annotato da Maria Rossi nel novembre 2026"
do
    local r, leggi, dest = crea(base, { evidenziazioni = false, note = false, frase_lettore = FRASE })
    uguale(r.lettore and r.lettore.dove, "frontespizio", "frontespizio trovato dai landmarks")
    local f = leggi("OEBPS/testo/frontespizio.xhtml")
    verifica(f:find('<p>Edizioni di prova, 2026</p>\n  </section>\n  <p class="parergon-reader">' .. FRASE .. "</p>\n</body>", 1, true),
        "paragrafo in fondo al frontespizio, prima di </body>")
    verifica(f:find('href="../parergon.css"', 1, true), "frontespizio collegato al CSS")
    verifica(leggi("OEBPS/parergon.css"):find(".parergon-reader { text-align: center", 1, true), "stile centrato e corsivo")
    verifica(verificaPython(dest), "EPUB valido")
end

do
    -- libro senza landmarks né guide: pagina nuova (dopo la copertina, se nota; altrimenti all'inizio)
    local opf = leggiFile("test/libro-prova/OEBPS/content.opf"):gsub("<guide>.-</guide>", "")
    local nav = leggiFile("test/libro-prova/OEBPS/nav.xhtml"):gsub('<nav epub:type="landmarks".-</nav>', "")
    local lett = lettoreCartella("test/libro-prova", { ["OEBPS/content.opf"] = opf, ["OEBPS/nav.xhtml"] = nav })
    local libro = assert(epub.leggi(lett))
    local dove = frontespizio.trova(libro, lett)
    uguale(dove.frontespizio, nil, "senza indicazioni il frontespizio non viene indovinato")
    local r, leggi, dest = crea(base, { evidenziazioni = false, note = false, frase_lettore = FRASE }, nil, lett)
    uguale(r.lettore.dove, "pagina", "pagina dedicata")
    verifica(leggi("OEBPS/content.opf"):find('<spine toc="ncx">\n    <itemref idref="parergon-reader"/>\n    <itemref idref="copertina" linear="yes"/>', 1, true),
        "senza copertina nota: la pagina va all'inizio dello spine")
    verifica(leggi("OEBPS/parergon-reader.xhtml"):find(FRASE, 1, true), "pagina con la frase")
    verifica(not leggi("OEBPS/testo/frontespizio.xhtml"):find("parergon-reader", 1, true), "il frontespizio incerto non viene toccato")
    verifica(verificaPython(dest), "EPUB valido")
    -- con la copertina indicata nella guide (ma senza frontespizio): subito dopo la copertina
    local opf2 = leggiFile("test/libro-prova/OEBPS/content.opf"):gsub('    <reference type="title%-page"[^\n]*\n', "")
    local lett2 = lettoreCartella("test/libro-prova", { ["OEBPS/content.opf"] = opf2, ["OEBPS/nav.xhtml"] = nav })
    local r2, leggi2, dest2 = crea(base, { evidenziazioni = false, note = false, frase_lettore = FRASE }, nil, lett2)
    uguale(r2.lettore.dove, "pagina", "frontespizio non indicato: pagina dedicata")
    verifica(leggi2("OEBPS/content.opf"):find('<itemref idref="copertina" linear="yes"/>\n    <itemref idref="parergon-reader"/>', 1, true),
        "pagina subito dopo la copertina")
    verifica(verificaPython(dest2), "EPUB valido")
    os.remove(USCITA .. "fase5.epub")
end

-- ---------------------------------------------------------------------------
sezione("file per la prova sul dispositivo (in italiano)")
-- ---------------------------------------------------------------------------
do
    i18n.configura{ modo = "it" }
    local r, leggi, dest = crea(base, { indice = true, note_modo = "testo", frase_lettore = FRASE },
        "Indice personale (annotated).epub", nil, " — indice personale")
    verifica(leggi("OEBPS/parergon-index.xhtml"):find("<title>Indice personale</title>", 1, true), "pagina in italiano")
    verifica(leggi("OEBPS/parergon-index.xhtml"):find(">Altre annotazioni <", 1, true), "«Altre annotazioni»")
    verifica(verificaPython(dest), "EPUB valido")
    print("\n" .. copia.riepilogo(r))
    -- sotto-temi leggibili e nella TOC
    local sotto = {}
    for i, a in ipairs(base) do
        local c = {}
        for k, x in pairs(a) do c[k] = x end
        sotto[i] = c
    end
    sotto[1].note = "#viaggi/mare_aperto\nInizio celebre"
    sotto[3].note = "#arte/arte-moderna #viaggi"
    local r2, leggi2, dest2 = crea(sotto, { indice = true, indice_toc_sottotemi = true },
        "Sotto-temi nella TOC (annotated).epub", nil, " — sotto-temi nella TOC")
    verifica(leggi2("OEBPS/nav.xhtml"):find(">mare aperto</a>", 1, true), "«mare aperto» nella TOC")
    verifica(leggi2("OEBPS/parergon-index.xhtml"):find(">arte moderna <", 1, true), "«arte moderna» nell'indice")
    verifica(verificaPython(dest2), "EPUB valido")
    print("\n" .. copia.riepilogo(r2))
    i18n.configura{ modo = "en" }
end

print(string.format("\n%d superati, %d falliti", superati, falliti))
os.exit(falliti == 0 and 0 or 1)
