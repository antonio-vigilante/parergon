--[[
Test eseguibili fuori dal dispositivo.

Uso (dalla cartella del progetto):
    python test/crea_epub.py && python test/crea_epub.py --store
    luajit test/esegui.lua

Non richiede KOReader: verifica i moduli in Lua puro del plugin.
]]

package.path = "parergon.koplugin/?.lua;test/?.lua;" .. package.path

local i18n = require("parergon/i18n")
i18n.configura{ modo = "en", cartella = "parergon.koplugin/" }
local analisi = require("parergon/analisi")
local corrisp = require("parergon/corrisp")
local epub = require("parergon/epub")
local testo = require("parergon/testo")
local xmltok = require("parergon/xmltok")
local xpointer = require("parergon/xpointer")
local zip = require("parergon/zip")

-- ---------------------------------------------------------------------------
-- Mini-framework
-- ---------------------------------------------------------------------------
local superati, falliti = 0, 0
local gruppo = ""

local function sezione(nome) gruppo = nome print("\n## " .. nome) end

local function verifica(cond, descr, dettaglio)
    if cond then
        superati = superati + 1
        print("  ok   " .. descr)
    else
        falliti = falliti + 1
        print("  FAIL " .. descr .. (dettaglio and ("\n       " .. tostring(dettaglio)) or ""))
    end
end

local function uguale(a, b, descr)
    verifica(a == b, descr, "atteso: " .. tostring(b) .. "\n       ottenuto: " .. tostring(a))
end

local function leggiFile(p)
    local f = assert(io.open(p, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

--- Lettore che legge dalla cartella sorgente del libro di prova.
local function lettoreCartella(radice)
    return {
        leggi = function(nome)
            local f = io.open(radice .. "/" .. nome, "rb")
            if not f then return nil, "assente" end
            local s = f:read("*a")
            f:close()
            return s
        end,
    }
end

--- Lettore da zip non compresso (usa solo zip.lua, come sul dispositivo per le voci "store").
local function lettoreZip(percorso)
    local arch = assert(zip.apri(percorso))
    return { leggi = function(nome) return zip.leggiNonCompresso(arch, nome) end }, arch
end

-- ---------------------------------------------------------------------------
sezione("testo.lua")
-- ---------------------------------------------------------------------------
uguale(testo.decodificaEntita("L&#8217;uomo &amp; &nbsp;&#x2014;&ignota;"),
    "L\u{2019}uomo & \u{A0}\u{2014}&ignota;", "decodifica entità numeriche, nominate e sconosciute")
uguale(testo.normalizza("  a \n\t b\u{A0}c  "), "a b c", "comprime spazi, NBSP e taglia i bordi")
uguale(testo.normalizza("sotto\u{AD}linea"), "sottolinea", "ignora il trattino morbido")
uguale(testo.normalizza("sotto&shy;linea"), "sottolinea", "ignora &shy;")
uguale(testo.lunghezza("perché è"), 8, "conta i caratteri UTF-8")
do
    local src = "<p>ab &amp; cd</p>"
    local n = testo.normalizzaFrammenti(src, { { s = 4, e = 14, nodo = "t" } })
    uguale(n.testo, "ab & cd", "normalizzazione con mappa")
    uguale(src:sub(n.cs[4], n.ce[4]), "&amp;", "un'entità mappa sull'intera sequenza di byte")
    local occ = testo.trovaOccorrenze(n, "& cd")
    uguale(#occ, 1, "trova un'occorrenza")
    uguale(occ[1].da, 4, "indice iniziale in caratteri")
    uguale(occ[1].a, 7, "indice finale in caratteri")
end
do
    local n = testo.normalizzaFrammenti("è è è", { { s = 1, e = #"è è è", nodo = 1 } })
    local occ = testo.trovaOccorrenze(n, "è")
    uguale(#occ, 3, "occorrenze multiple con caratteri multibyte")
    uguale(occ[3].da, 5, "indice corretto dopo caratteri multibyte")
end

-- ---------------------------------------------------------------------------
sezione("xmltok.lua")
-- ---------------------------------------------------------------------------
do
    local src = [==[<?xml version="1.0"?><!DOCTYPE html [<!ENTITY x "y>">]><html><!-- <p>no</p> --><body a='1>2' b="c"><p>x<br/>y<br></br></p><![CDATA[<b>]]></body></html>]==]
    local doc = assert(xmltok.analizza(src))
    uguale(doc.anomalie, 0, "documento con DOCTYPE, commento, CDATA, attributi con '>' e <br></br>")
    local body = xmltok.trova(doc.radice, "body")
    uguale(xmltok.attr(body).a, "1>2", "attributo con '>' tra virgolette")
    local p = xmltok.trova(doc.radice, "p")
    uguale(#p.figli, 4, "il commento non crea nodi; <br/> e <br></br> sono vuoti")
    verifica(xmltok.trova(doc.radice, "b") == nil, "il contenuto di CDATA non diventa un elemento")
end
do
    local ok = xmltok.bilanciato("<a><b></a></b>")
    verifica(not ok, "rileva tag non bilanciati")
    verifica(xmltok.bilanciato("<a><b/></a>"), "accetta tag bilanciati")
    verifica(not xmltok.bilanciato("<a><b>"), "rileva elementi non chiusi")
end
do
    local doc = assert(xmltok.analizza('<svg:svg xmlns:svg="x"><svg:rect/></svg:svg>'))
    uguale(doc.radice.figli[1].nome, "svg", "nome locale senza prefisso")
    uguale(doc.anomalie, 0, "chiusura con prefisso")
end

-- ---------------------------------------------------------------------------
sezione("xpointer.lua")
-- ---------------------------------------------------------------------------
do
    local x = assert(xpointer.analizza("/body/DocFragment[12]/body/div[2]/p[5]/text()[3].17"))
    uguale(x.frammento, 12, "DocFragment")
    uguale(#x.passi, 2, "passi dopo il body")
    uguale(x.passi[2].nome .. x.passi[2].indice, "p5", "nome e indice")
    uguale(x.testo, 3, "text()[k]")
    uguale(x.offset, 17, "offset")
    local y = assert(xpointer.analizza("/body/DocFragment[3]/body/section/p/text().4"))
    uguale(y.passi[1].indice, 1, "indice [1] implicito")
    uguale(y.testo, 1, "text() implicito")
    local z = assert(xpointer.analizza("/body/DocFragment[3]/body/autoBoxing/p[2].0"))
    uguale(#z.passi, 1, "salta i nodi di impaginazione (autoBoxing)")
    uguale(z.testo, nil, "XPointer su elemento")
    uguale(z.offset, 0, "offset su elemento")
    verifica(xpointer.analizza({ page = 1 }) == nil, "rifiuta posizioni PDF (tabelle)")
    verifica(xpointer.analizza("/html/body") == nil, "rifiuta percorsi senza DocFragment")
    uguale(xpointer.indiceBlocco(x.passi), 2, "blocco più interno")
end

-- ---------------------------------------------------------------------------
sezione("epub.lua")
-- ---------------------------------------------------------------------------
uguale(epub.risolvi("OEBPS/testo/", "../stile/a%20b.css#x"), "OEBPS/stile/a b.css", "risolve href relativi")
uguale(epub.relativo("OEBPS/testo/cap1.xhtml", "OEBPS/parergon.css"), "../parergon.css", "percorso relativo")
uguale(epub.relativo("OEBPS/cap1.xhtml", "OEBPS/x/y.css"), "x/y.css", "percorso relativo in sottocartella")
do
    local libro = assert(epub.leggi(lettoreCartella("test/libro-prova")))
    uguale(libro.opf, "OEBPS/content.opf", "trova l'OPF da container.xml")
    uguale(#libro.spine, 5, "spine")
    uguale(libro.nav and libro.nav.percorso, "OEBPS/nav.xhtml", "trova nav.xhtml")
    uguale(libro.ncx and libro.ncx.percorso, "OEBPS/toc.ncx", "trova toc.ncx")
    uguale(epub.frammenti(libro)[3].percorso, "OEBPS/testo/cap1.xhtml", "DocFragment[3] = cap1")
    uguale(#libro.guide, 3, "guide")
end
do
    -- spine con un idref inesistente e un elemento non XHTML
    local opf = [[<package version="3.0"><manifest>
      <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
      <item id="s" href="s.svg" media-type="image/svg+xml"/>
      <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
    </manifest><spine><itemref idref="a"/><itemref idref="manca"/><itemref idref="s"/><itemref idref="b"/></spine></package>]]
    local lettore = { leggi = function(n)
        if n == "META-INF/container.xml" then return '<container><rootfiles><rootfile full-path="o.opf"/></rootfiles></container>' end
        if n == "o.opf" then return opf end
    end }
    local libro = assert(epub.leggi(lettore))
    local nuovo = epub.frammenti(libro, 20260812)
    local vecchio = epub.frammenti(libro, 20200824)
    uguale(#nuovo, 3, "DOM recente: idref inesistente scartato, SVG conta")
    uguale(nuovo[3].percorso, "b.xhtml", "DOM recente: b è il DocFragment 3")
    uguale(#vecchio, 2, "DOM < 20240114: contano solo gli XHTML")
    uguale(vecchio[2].percorso, "b.xhtml", "DOM vecchio: b è il DocFragment 2")
end

-- ---------------------------------------------------------------------------
sezione("zip.lua")
-- ---------------------------------------------------------------------------
do
    local arch = assert(zip.apri("test/libro-prova-store.epub"))
    uguale(arch.voci[1].nome, "mimetype", "mimetype è la prima voce")
    uguale(zip.leggiNonCompresso(arch, "mimetype"), "application/epub+zip", "legge il mimetype")
    uguale(zip.leggiNonCompresso(arch, "OEBPS/testo/cap1.xhtml"),
        leggiFile("test/libro-prova/OEBPS/testo/cap1.xhtml"), "contenuto identico al sorgente")
    local def = assert(zip.apri("test/libro-prova.epub"))
    uguale(def.perNome["OEBPS/testo/cap1.xhtml"].metodo, 8, "riconosce le voci compresse (deflate)")
    uguale(def.perNome["mimetype"].metodo, 0, "mimetype non compresso")
    verifica(zip.apri("test/esegui.lua") == nil, "rifiuta un file che non è uno zip")
end

-- ---------------------------------------------------------------------------
sezione("corrisp.lua — annotazioni di prova")
-- ---------------------------------------------------------------------------
local prove = require("annotazioni_prova")
local lettore = lettoreZip("test/libro-prova-store.epub")
local libro = assert(epub.leggi(lettore))
local frammenti = epub.frammenti(libro)
for _, a in ipairs(prove) do
    if not a.atteso.ignorata then
        local x0 = assert(xpointer.analizza(a.pos0))
        local src = lettore.leggi(frammenti[x0.frammento].percorso)
        local doc = assert(xmltok.analizza(src))
        local r = corrisp.trova(doc, a)
        local at = a.atteso
        if at.ok then
            verifica(r.ok, a.nome, r.motivo)
            if r.ok then
                uguale(r.passo, at.passo, "  testo trovato")
                uguale(#r.segmenti, at.segmenti, "  numero di segmenti")
                -- il testo dei segmenti, decodificato, deve formare il passo
                local pezzi = {}
                for _, s in ipairs(r.segmenti) do pezzi[#pezzi + 1] = src:sub(s.s, s.e) end
                -- (confronto senza spazi: i segmenti possono essere separati da tag o <br/>)
                local function compatta(t) return (testo.normalizza(t):gsub(" ", "")) end
                uguale(compatta(testo.decodificaEntita(table.concat(pezzi))),
                    compatta(at.passo), "  i byte dei segmenti contengono il passo")
                for _, s in ipairs(r.segmenti) do
                    verifica(not src:sub(s.s, s.e):find("[<>]"), "  il segmento non contiene tag")
                end
                if at.metodo then
                    verifica(r.metodo:find(at.metodo, 1, true), "  metodo: " .. at.metodo, r.metodo)
                end
                uguale(r.ricerca, at.ricerca == true, "  trovata con la ricerca nel file: " .. tostring(at.ricerca == true))
            end
        else
            verifica(not r.ok, a.nome, "trovata invece di essere saltata")
            if not r.ok then
                uguale(r.codice, at.codice, "  codice del motivo")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
sezione("analisi.lua — rapporto completo")
-- ---------------------------------------------------------------------------
do
    local ris = assert(analisi.analizza{ lettore = lettore, annotazioni = prove })
    uguale(#ris.esiti, #prove - 1, "i segnalibri senza drawer sono esclusi")
    local attese_ok = 0
    for _, a in ipairs(prove) do if a.atteso.ok then attese_ok = attese_ok + 1 end end
    uguale(ris.trovate, attese_ok, "numero di corrispondenze certe")
    local rapporto = analisi.rapporto(ris, 20260812)
    verifica(rapporto:find("OEBPS/testo/cap1.xhtml, line", 1, true), "il rapporto indica file e riga")
    verifica(rapporto:find("SKIPPED: text not found in the paragraph", 1, true), "il rapporto indica il motivo")
    local f = io.open("test/rapporto-prova.txt", "wb")
    f:write(rapporto)
    f:close()
    print("  (rapporto scritto in test/rapporto-prova.txt)")
end

-- ---------------------------------------------------------------------------
sezione("dati reali — Kindle, KOReader con DOM 20240114 (22/11/2026)")
-- ---------------------------------------------------------------------------
do
    local reali = {
        { drawer = "underscore", color = "gray",
          text = "Questo paragrafo è scritto su più righe nel sorgente, con spazi irregolari.",
          pos0 = "/body/DocFragment[3]/body/section/p[5]/text().0",
          pos1 = "/body/DocFragment[3]/body/section/p[5]/text().75" },
        { drawer = "lighten", color = "gray", note = "Esempio di nota.",
          text = "La sottolineatura nascosta non deve ingannare.\nPrima riga",
          pos0 = "/body/DocFragment[3]/body/section/p[7]/text().0",
          pos1 = "/body/DocFragment[3]/body/section/p[8]/text()[1].10" },
    }
    -- seconda prova sul Kindle (stesso giorno): corsivo, testo ripetuto, grassetto iniziale, <br/>
    local seconda = {
        { drawer = "underscore", text = "cammino della vita", atteso = "cammino della vita", segmenti = 2,
          pos0 = "/body/DocFragment[3]/body/section/p[2]/i/text().0",
          pos1 = "/body/DocFragment[3]/body/section/p[2]/text()[2].11" },
        { drawer = "underscore", text = "una rosa", atteso = "una rosa", segmenti = 1, da = 22,
          pos0 = "/body/DocFragment[3]/body/section/p[4]/text().21",
          pos1 = "/body/DocFragment[3]/body/section/p[4]/text().29" },
        { drawer = "underscore", text = "Grassetto e poi testo normale", atteso = "Grassetto e poi testo normale",
          segmenti = 2,
          pos0 = "/body/DocFragment[3]/body/section/p[6]/b/text().0",
          pos1 = "/body/DocFragment[3]/body/section/p[6]/text().20" },
        { drawer = "underscore", text = "Prima riga\nseconda riga del verso.", atteso = "Prima riga seconda riga del verso.",
          segmenti = 2,
          pos0 = "/body/DocFragment[3]/body/section/p[8]/text()[1].0",
          pos1 = "/body/DocFragment[3]/body/section/p[8]/text()[2].23" },
    }
    local ris2 = assert(analisi.analizza{ lettore = lettore, annotazioni = seconda, versione_dom = 20240114 })
    uguale(ris2.trovate, 4, "Kindle, seconda prova: tutte trovate")
    for i, e in ipairs(ris2.esiti) do
        uguale(e.esito.passo, seconda[i].atteso, "  passo " .. i)
        uguale(#e.esito.segmenti, seconda[i].segmenti, "  segmenti " .. i)
    end
    verifica(ris2.esiti[2].esito.metodo:find("chosen by position", 1, true), "  «una rosa»: scelta per posizione")
    -- In p[6] crengine scrive "text()" senza indice: c'è un solo nodo di testo, quindi
    -- il nodo di soli spazi prima di <b> è stato davvero scartato (regola di testoK).
    -- L'offset 20 è la lunghezza di " e poi testo normale": pos1 è esclusivo.

    local ris = assert(analisi.analizza{ lettore = lettore, annotazioni = reali, versione_dom = 20240114 })
    local e1, e2 = ris.esiti[1].esito, ris.esiti[2].esito
    verifica(e1.ok, "paragrafo su più righe: trovato", e1.motivo)
    uguale(e1.passo, "Questo paragrafo è scritto su più righe nel sorgente, con spazi irregolari.",
        "  passo completo")
    verifica(e2.ok, "due paragrafi (dati reali): trovata", e2.motivo)
    uguale(e2.passo, "La sottolineatura nascosta non deve ingannare. Prima riga", "  passo su due paragrafi")
    uguale(e2.segmenti and #e2.segmenti, 2, "  un segmento per paragrafo")
    -- L'offset di fine (75) coincide con la lunghezza del testo a spazi compressi:
    -- in crengine gli offset contano caratteri dopo la compressione degli spazi,
    -- e pos1 indica la posizione dopo l'ultimo carattere.
    local norm = corrisp.testoNodo(lettore.leggi("OEBPS/testo/cap1.xhtml") and
        e1.blocco and assert(xmltok.analizza(lettore.leggi("OEBPS/testo/cap1.xhtml"))).src, e1.blocco)
    uguale(norm.n, 75, "  offset di crengine = caratteri a spazi compressi (pos1 esclusivo)")
end

-- frammento inesistente
do
    local ris = analisi.analizza{ lettore = lettore, annotazioni = {
        { drawer = "lighten", text = "x", pos0 = "/body/DocFragment[9]/body/p[1]/text()[1].0",
          pos1 = "/body/DocFragment[9]/body/p[1]/text()[1].1" } } }
    verifica(ris.esiti[1].esito.motivo:find("DocFragment[9]", 1, true), "DocFragment fuori dallo spine")
end


-- ---------------------------------------------------------------------------
sezione("i18n.lua — traduzioni")
-- ---------------------------------------------------------------------------
do
    local po = i18n.leggiPo("parergon.koplugin/locales/it.po")
    verifica(po and po["Language"] == "Lingua", "legge il catalogo italiano")
    i18n.configura{ modo = "it" }
    uguale(i18n("Language"), "Lingua", "modo italiano")
    uguale(i18n.trf("Skipped: %d", 3), "Saltate: 3", "traduzione con parametri")
    uguale(i18n("frase senza traduzione"), "frase senza traduzione", "senza traduzione resta l'inglese")
    i18n.configura{ modo = "auto", lingua_koreader = function() return "it_IT" end }
    uguale(i18n.lingua(), "it", "automatica: segue KOReader (it_IT)")
    uguale(i18n("Language"), "Lingua", "automatica in italiano")
    i18n.configura{ lingua_koreader = function() return "de" end }
    uguale(i18n("Language"), "Language", "lingua senza catalogo: inglese")
    i18n.configura{ lingua_koreader = function() return "C" end }
    uguale(i18n.lingua(), "en", "lingua C di KOReader: inglese")
    i18n.configura{ modo = "en" }
    uguale(i18n("Language"), "Language", "modo inglese forzato")
    -- un motivo di scarto in italiano
    i18n.configura{ modo = "it" }
    local rovescio
    for _, a in ipairs(prove) do if a.nome == "più paragrafi in ordine rovesciato" then rovescio = a end end
    local r = corrisp.trova(assert(xmltok.analizza(lettore.leggi("OEBPS/testo/cap1.xhtml"))), rovescio)
    uguale(r.motivo, "attraversa più paragrafi, in un ordine inatteso", "motivo tradotto")
    uguale(r.codice, "paragrafi", "il codice non cambia con la lingua")
    i18n.configura{ modo = "en" }
end

print(string.format("\n%d superati, %d falliti", superati, falliti))
os.exit(falliti == 0 and 0 or 1)
