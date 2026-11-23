--[[
Test della fase 3 (scrittura della copia con le evidenziazioni), fuori dal dispositivo.

Uso (dalla cartella del progetto):
    python test/crea_epub.py && python test/crea_epub.py --store
    luajit test/esegui_fase3.lua

Produce anche, per la verifica visiva sul dispositivo:
    test/uscita/Libro di prova (annotato).epub
    test/uscita/Campionario colori (annotato).epub
    test/uscita/Campionario grigio (annotato).epub
]]

package.path = "parergon.koplugin/?.lua;test/?.lua;" .. package.path

local i18n = require("parergon/i18n")
i18n.configura{ modo = "en", cartella = "parergon.koplugin/" }
local copia = require("parergon/copia")
local crc32 = require("parergon/crc32")
local epub = require("parergon/epub")
local riscrivi = require("parergon/riscrivi")
local stile = require("parergon/stile")
local testo = require("parergon/testo")
local xmltok = require("parergon/xmltok")
local zip = require("parergon/zip")
local zipscrivi = require("parergon/zipscrivi")

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
local function scriviFile(p, s)
    local f = assert(io.open(p, "wb")) f:write(s) f:close()
end

os.execute(package.config:sub(1, 1) == "\\" and 'mkdir "test\\uscita" 2>nul' or "mkdir -p test/uscita")
local USCITA = "test/uscita/"

--- Deflate grezzo calcolato da Python (zlib con wbits = -15), solo per i test.
local function comprimiPython(dati)
    local a, b = USCITA .. "tmp-in.bin", USCITA .. "tmp-out.bin"
    scriviFile(a, dati)
    local ok = os.execute('python -c "import zlib,sys; d=open(sys.argv[1],\'rb\').read(); '
        .. 'c=zlib.compressobj(6, zlib.DEFLATED, -15); open(sys.argv[2],\'wb\').write(c.compress(d)+c.flush())" '
        .. a .. " " .. b)
    if ok ~= 0 and ok ~= true then return nil end
    local r = leggiFile(b)
    os.remove(a) os.remove(b)
    return r
end

local function verificaPython(percorso)
    local r = os.execute('python test/verifica_epub.py "' .. percorso .. '"')
    return r == 0 or r == true
end

local function lettoreCartella(radice)
    return { leggi = function(nome)
        local f = io.open(radice .. "/" .. nome, "rb")
        if not f then return nil, "assente" end
        local s = f:read("*a") f:close() return s
    end }
end

-- ---------------------------------------------------------------------------
sezione("crc32.lua")
-- ---------------------------------------------------------------------------
uguale(crc32.calcola("The quick brown fox jumps over the lazy dog"), 0x414FA339, "valore noto")
uguale(crc32.calcola(""), 0, "stringa vuota")
uguale(crc32.calcola("fox jumps over the lazy dog", crc32.calcola("The quick brown ")), 0x414FA339, "calcolo a pezzi")

-- ---------------------------------------------------------------------------
sezione("zipscrivi.lua")
-- ---------------------------------------------------------------------------
do
    local p = USCITA .. "prova.zip"
    local w = assert(zipscrivi.nuovo(p, { comprimi = comprimiPython }))
    w:aggiungi("mimetype", "application/epub+zip", false)
    w:aggiungi("testo/è.txt", string.rep("ripetuto ", 200), true)
    w:aggiungi("vuoto.txt", "", true)
    w:chiudi()
    local arch = assert(zip.apri(p))
    uguale(#arch.voci, 3, "tre voci")
    uguale(arch.voci[1].metodo, 0, "mimetype non compresso")
    uguale(arch.perNome["testo/è.txt"].metodo, 8, "testo ripetuto compresso")
    verifica(arch.perNome["testo/è.txt"].flag >= 2048, "nome UTF-8 segnalato (bit 11)")
    local ok = os.execute('python -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); '
        .. 'assert z.testzip() is None; assert z.read(\'testo/\\u00e8.txt\')==b\'ripetuto \'*200" ' .. p)
    verifica(ok == 0 or ok == true, "Python legge l'archivio e verifica i CRC")
end

-- ---------------------------------------------------------------------------
sezione("stile.lua")
-- ---------------------------------------------------------------------------
for __, c in ipairs(stile.ORDINE_COLORI) do
    local l = stile.luma(stile.sfondo(stile.COLORI[c]))
    verifica(math.abs(l - stile.LUMA_SFONDO) < 0.01, string.format("sfondo %s: luminanza %.3f ≈ 0.80", c, l))
    verifica(stile.luma(stile.linea(stile.COLORI[c])) <= stile.LUMA_LINEA + 0.01, "linea " .. c .. " abbastanza scura")
end
do
    local f, c = stile.risolvi({ drawer = "lighten", color = "yellow" }, {})
    uguale(f .. "/" .. c, "highlight/yellow", "lighten → evidenziazione")
    f = stile.risolvi({ drawer = "underscore" }, {})
    uguale(f, "solid", "underscore → continua")
    f = stile.risolvi({ drawer = "strikeout" }, {})
    uguale(f, "wavy", "strikeout (ondulata di Readest) → zigzag")
    f = stile.risolvi({ drawer = "lighten", color = "gray" }, { forma = "dashed" })
    uguale(f, "dashed", "forma generale")
    f = stile.risolvi({ drawer = "lighten", color = "gray" }, { forma = "dashed", per_colore = { gray = "wavy" } })
    uguale(f, "wavy", "la mappatura per colore prevale sulla generale")
    f = stile.risolvi({ drawer = "lighten", color = "gray", parergon_forma = "solid" }, { per_colore = { gray = "wavy" } })
    uguale(f, "solid", "la scelta per annotazione prevale su tutto")
    f, c = stile.risolvi({ drawer = "lighten", color = "blue" }, { colori = "gray" })
    uguale(c, "mono", "grigio uniforme")
    uguale(stile.nomeColore("#123456"), "gray", "colore personalizzato sconosciuto → grigio")
    local css = stile.css({ { "highlight", "yellow" }, { "wavy", "mono" } })
    verifica(css:find(".parergon-hl-yellow { background-color: #", 1, true), "regola di base dello sfondo")
    verifica(css:find("-cr-only-if: never; background-color: rgba(", 1, true), "regola web dello sfondo")
    verifica(css:find("border-bottom: 0.12em dotted currentColor", 1, true), "zigzag in KOReader: puntinato")
    verifica(css:find("underline wavy currentColor", 1, true), "zigzag nei motori web: ondulato")
end

-- ---------------------------------------------------------------------------
sezione("riscrivi.lua")
-- ---------------------------------------------------------------------------
do
    local src = "<p>abc def ghi</p>"
    -- due evidenziazioni adiacenti: "abc" (byte 4-6) e " def" (byte 7-10)
    local ins = {}
    for __, x in ipairs(riscrivi.avvolgi({ { s = 4, e = 6 } }, "a", "m1", 1)) do ins[#ins + 1] = x end
    for __, x in ipairs(riscrivi.avvolgi({ { s = 7, e = 10 } }, "b", nil, 2)) do ins[#ins + 1] = x end
    local r = riscrivi.applica(src, ins)
    uguale(r, '<p><span class="a" id="m1">abc</span><span class="b"> def</span> ghi</p>', "adiacenti: chiusura prima dell'apertura")
    verifica(riscrivi.verifica(src, r), "risultato bilanciato")
    verifica(not riscrivi.verifica(src, "<p><span>abc</p>"), "rileva un peggioramento")
    local voci = {
        { esito = { inizio = 10, fine = 20 }, ordine = 1 },
        { esito = { inizio = 15, fine = 30 }, ordine = 2 },
        { esito = { inizio = 31, fine = 40 }, ordine = 3 },
    }
    local acc, sc = riscrivi.senzaSovrapposizioni(voci)
    uguale(#acc, 2, "sovrapposizioni: due accettate")
    uguale(sc[1].codice, "sovrapposta", "la sovrapposta è scartata con codice")
    -- dati reali: lo stesso passo ripetuto con fini sempre più avanti (18 copie nel sidecar)
    local copie = {}
    for k, f in ipairs({ 296, 309, 312, 479, 474 }) do
        copie[k] = { esito = { inizio = 100, fine = 100 + f }, ordine = k }
    end
    copie[#copie + 1] = { esito = { inizio = 101, fine = 300 }, ordine = 9 } -- senza la prima parola
    acc, sc = riscrivi.senzaSovrapposizioni(copie)
    uguale(#acc, 1, "copie dello stesso passo: ne resta una")
    uguale(acc[1].esito.fine, 579, "  la più lunga")
    uguale(#sc, 5, "  le altre scartate")
    local tutte_contenute = true
    for __, s in ipairs(sc) do if s.codice ~= "contenuta" then tutte_contenute = false end end
    verifica(tutte_contenute, "  con il codice «contenuta»")
end

-- ---------------------------------------------------------------------------
sezione("copia.lua — libro di prova")
-- ---------------------------------------------------------------------------
local prove = require("annotazioni_prova")
local originale = "test/libro-prova.epub"   -- compresso: le voci intatte vanno copiate byte per byte
local prima = leggiFile(originale)
local dest = USCITA .. "Libro di prova (annotated).epub"
local rap, err = copia.crea{
    originale = originale, lettore = lettoreCartella("test/libro-prova"), annotazioni = prove,
    imp = {}, destinazione = dest, comprimi = comprimiPython, suffisso = " (annotated)",
    opzioni = { note = false }, -- fase 3: solo evidenziazioni (le note hanno i loro test)
}
verifica(rap, "copia creata", err)
if rap then
    uguale(rap.consolidate, 14, "evidenziazioni scritte")
    uguale(#rap.saltate, 4, "annotazioni saltate (come nell'analisi)")
    uguale(leggiFile(originale), prima, "l'originale è identico byte per byte")
    verifica(verificaPython(dest), "verifica indipendente con Python (ZIP, mimetype, XML, manifest)")
    local arch = assert(zip.apri(dest))
    local orig = assert(zip.apri(originale))
    uguale(arch.voci[1].nome, "mimetype", "mimetype per primo")
    -- le voci non modificate sono identiche (stessi dati compressi e CRC)
    local img_o, img_c = orig.perNome["OEBPS/immagini/copertina.svg"], arch.perNome["OEBPS/immagini/copertina.svg"]
    uguale(zip.datiGrezzi(arch, img_c), zip.datiGrezzi(orig, img_o), "voce non modificata copiata byte per byte")
    uguale(img_c.crc, img_o.crc, "  stesso CRC")
    -- contenuto (le voci compresse si leggono via Python)
    local function estrai(nome)
        local out = USCITA .. "estratto.tmp"
        os.execute('python -c "import zipfile,sys; open(sys.argv[3],\'wb\').write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))" "'
            .. dest .. '" ' .. nome .. " " .. out)
        local s = leggiFile(out) os.remove(out) return s
    end
    local cap1 = estrai("OEBPS/testo/cap1.xhtml")
    verifica(cap1:find('<span class="parergon-ul-solid-red" id="parergon-2">per una selva oscura</span>', 1, true),
        "sottolineatura continua rossa con id")
    verifica(cap1:find('<i><span class="parergon-hl-yellow" id="parergon-3">cammino</span></i><span class="parergon-hl-yellow"> della vita</span>', 1, true),
        "passo nel corsivo: due segmenti, XHTML valido")
    verifica(cap1:find('<link rel="stylesheet" type="text/css" href="../parergon.css"/>', 1, true), "collegamento al CSS")
    verifica(cap1:find("L&#8217;uomo &amp; la natura&#160;", 1, true), "entità del sorgente intatte")
    -- fuori dalle aggiunte il file è identico all'originale
    local senza = cap1:gsub('<span class="parergon[^"]*"[^>]*>', ""):gsub("</span>", "")
        :gsub('<link rel="stylesheet" type="text/css" href="../parergon.css"/>\n', "")
    uguale(senza, leggiFile("test/libro-prova/OEBPS/testo/cap1.xhtml"), "togliendo le aggiunte si riottiene l'originale")
    verifica(cap1:find('<span class="parergon-hl-yellow" id="parergon-11">del verso.</span></p>\n'
        .. '    <p><span class="parergon-hl-yellow">Questo paragrafo finisce qui.</span></p>\n'
        .. '    <p><span class="parergon-hl-yellow">E questo</span> comincia dopo.</p>', 1, true),
        "tre paragrafi: uno span per paragrafo, niente span fra un blocco e l'altro")
    local cap2 = estrai("OEBPS/testo/cap2.xhtml")
    verifica(cap2:find('<h2>Capitolo <span class="parergon-ul-solid-yellow" id="parergon-12">secondo</span></h2>\n'
        .. '    <div class="citazione">\n'
        .. '      <p class="epigrafe"><span class="parergon-ul-solid-yellow">Chi legge</span>', 1, true),
        "dal titolo all'epigrafe: i contenitori restano fuori dagli span")
    local opf = estrai("OEBPS/content.opf")
    verifica(opf:find('<item id="parergon-css" href="parergon.css" media-type="text/css"/>', 1, true), "CSS nel manifest")
    verifica(opf:find("<dc:title>Libro di prova per Parergon (annotated)</dc:title>", 1, true), "titolo distinto")
    verifica(rap.nuovo_id and opf:find(rap.nuovo_id, 1, true), "nuovo identificatore nell'OPF")
    verifica(not opf:find('<dc:identifier id="bookid">urn:uuid:6f1c2a52', 1, true),
        "vecchio identificatore sostituito in dc:identifier (resta solo nel marcatore)")
    local ncx = estrai("OEBPS/toc.ncx")
    verifica(ncx:find('content="' .. tostring(rap.nuovo_id) .. '"', 1, true), "dtb:uid aggiornato in toc.ncx")
    local css = estrai("OEBPS/parergon.css")
    verifica(css:find("parergon-ul-wavy-gray", 1, true), "CSS con le classi usate")
    print("\n" .. copia.riepilogo(rap))
end

-- ---------------------------------------------------------------------------
sezione("copia.lua — identificatore stabile e marcatore")
-- ---------------------------------------------------------------------------
do
    local pacchetto = require("parergon/pacchetto")
    local a = pacchetto.uuidDerivato("urn:uuid:6f1c2a52-3c1e-4c8e-9a51-0c6b3f0a2026")
    uguale(a, pacchetto.uuidDerivato("urn:uuid:6f1c2a52-3c1e-4c8e-9a51-0c6b3f0a2026"), "derivato: deterministico")
    verifica(a ~= pacchetto.uuidDerivato("isbn:9788845292613"), "derivato: cambia con la sorgente")
    verifica(a:match("^urn:uuid:%x%x%x%x%x%x%x%x%-%x%x%x%x%-8%x%x%x%-[89ab]%x%x%x%-%x+$") and #a == 45,
        "formato UUID versione 8", a)
    -- due rigenerazioni della copia danno lo stesso identificatore
    local d2 = USCITA .. "Seconda (annotated).epub"
    local r2 = assert(copia.crea{ originale = originale, lettore = lettoreCartella("test/libro-prova"),
        annotazioni = prove, destinazione = d2, suffisso = " (annotated)" })
    uguale(r2.nuovo_id, rap and rap.nuovo_id, "rigenerando la copia l'identificatore non cambia")
    -- il marcatore viene scritto e riconosciuto
    local arch2 = assert(zip.apri(d2))
    -- le voci modificate sono non compresse (nessun deflate qui); le altre sono quelle dell'originale
    local l2 = { leggi = function(n)
        return zip.leggiNonCompresso(arch2, n) or lettoreCartella("test/libro-prova").leggi(n)
    end }
    local libro2 = assert(epub.leggi(l2))
    uguale(pacchetto.marcatore(libro2), "urn:uuid:6f1c2a52-3c1e-4c8e-9a51-0c6b3f0a2026",
        "la copia porta il marcatore con l'identificatore dell'originale")
    local libro_o = assert(epub.leggi(lettoreCartella("test/libro-prova")))
    uguale(pacchetto.marcatore(libro_o), nil, "l'originale non ha il marcatore")
    -- consolidare la copia non duplica il marcatore
    local d3 = USCITA .. "Terza (annotated).epub"
    assert(copia.crea{ originale = d2, lettore = l2, annotazioni = {}, destinazione = d3, suffisso = " (annotated)" })
    local arch3 = assert(zip.apri(d3))
    local opf3 = zip.leggiNonCompresso(arch3, "OEBPS/content.opf")
    local _, quanti = opf3:gsub('name="parergon:source"', "")
    uguale(quanti, 1, "marcatore presente una sola volta")
    verifica(verificaPython(d3), "copia di una copia: EPUB valido")
    os.remove(d2) os.remove(d3)
end

do
    local r2, e2 = copia.crea{ originale = originale, destinazione = originale, lettore = lettoreCartella("test/libro-prova"),
        annotazioni = prove }
    verifica(not r2 and e2:find("same name", 1, true), "rifiuta di sovrascrivere l'originale")
end

-- ---------------------------------------------------------------------------
sezione("copia.lua — DRM e offuscamento")
-- ---------------------------------------------------------------------------
do
    -- EPUB con encryption.xml non di offuscamento: deve essere rifiutato
    local p = USCITA .. "drm.epub"
    local w = assert(zipscrivi.nuovo(p))
    w:aggiungi("mimetype", "application/epub+zip", false)
    for __, n in ipairs({ "META-INF/container.xml", "OEBPS/content.opf", "OEBPS/testo/cap1.xhtml" }) do
        w:aggiungi(n, leggiFile("test/libro-prova/" .. n), false)
    end
    w:aggiungi("META-INF/encryption.xml", [[<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/><enc:CipherData><enc:CipherReference URI="OEBPS/testo/cap1.xhtml"/></enc:CipherData></enc:EncryptedData></encryption>]], false)
    w:chiudi()
    local arch = assert(zip.apri(p))
    local r, e = copia.crea{ originale = p, destinazione = USCITA .. "drm (c).epub", annotazioni = prove,
        lettore = { leggi = function(n) return zip.leggiNonCompresso(arch, n) end } }
    verifica(not r and e:find("DRM", 1, true), "libro con DRM rifiutato", e)
end

-- ---------------------------------------------------------------------------
sezione("campionari per la verifica visiva")
-- ---------------------------------------------------------------------------
do
    local src = leggiFile("test/libro-prova/OEBPS/testo/cap3.xhtml")
    local doc = assert(xmltok.analizza(src))
    local section = xmltok.trova(doc.radice, "section")
    local colori = stile.ORDINE_COLORI
    local parole = { { "evidenziato", "highlight" }, { "continuo", "solid" }, { "tratteggiato", "dashed" }, { "ondulato", "wavy" } }
    local ann = {}
    local k = 0
    for __, el in ipairs(section.figli) do
        if el.tipo == "el" and el.nome == "p" then
            k = k + 1
            local t = src:sub(el.is, el.ie)
            local function xp(off) return string.format("/body/DocFragment[5]/body/section/p[%d]/text().%d", k, off) end
            local function aggiungi(frase, forma, colore)
                local i = assert(t:find(frase, 1, true))
                local off = testo.lunghezza(t:sub(1, i - 1))
                ann[#ann + 1] = { drawer = "lighten", color = colore, parergon_forma = forma, text = frase,
                    pos0 = xp(off), pos1 = xp(off + testo.lunghezza(frase)) }
            end
            if k <= #colori then
                for __, pf in ipairs(parole) do aggiungi(pf[1], pf[2], colori[k]) end
            elseif k == #colori + 1 then
                aggiungi(t:match("^(.-)%.$"), "highlight", "yellow")
            else
                aggiungi(t:match("^(.-)%.$"), "wavy", "gray")
            end
        end
    end
    uguale(#ann, 38, "annotazioni del campionario")
    for __, var in ipairs({ { "colori", "keep" }, { "grigio", "gray" } }) do
        local d = USCITA .. "Campionario " .. var[1] .. " (annotated).epub"
        local r, e = copia.crea{ originale = "test/libro-prova-store.epub", lettore = lettoreCartella("test/libro-prova"),
            annotazioni = ann, imp = { colori = var[2] }, destinazione = d, comprimi = comprimiPython,
            suffisso = " — campionario " .. var[1] }
        verifica(r and r.consolidate == 38, "campionario " .. var[1] .. ": 38 evidenziazioni", e or (r and copia.riepilogo(r)))
        verifica(r and verificaPython(d), "campionario " .. var[1] .. ": EPUB valido")
    end
end


-- nota su un passo che attraversa più paragrafi: va dopo la fine del passo, nell'ultimo
do
    local multi
    for __, a in ipairs(prove) do if a.nome == "tre paragrafi, quello in mezzo intero" then multi = a end end
    local con_nota = {}
    for k, x in pairs(multi) do con_nota[k] = x end
    con_nota.note = "Su tre paragrafi"
    local d = USCITA .. "multi.epub"
    local r = assert(copia.crea{ originale = originale, lettore = lettoreCartella("test/libro-prova"),
        annotazioni = { con_nota }, destinazione = d, suffisso = " (annotated)" })
    uguale(r.consolidate, 1, "nota su più paragrafi: scritta")
    local s = assert(zip.apri(d))
    local x = zip.leggiNonCompresso(s, "OEBPS/testo/cap1.xhtml")
    if not x then
        local out = USCITA .. "estratto.tmp"
        os.execute('python -c "import zipfile,sys; open(sys.argv[3],\'wb\').write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))" "'
            .. d .. '" OEBPS/testo/cap1.xhtml ' .. out)
        x = leggiFile(out) os.remove(out)
    end
    verifica(x:find('>E questo</span> <span class="parergon-note">', 1, true), "  la nota segue la fine del passo")
    verifica(verificaPython(d), "  EPUB valido")
    os.remove(d)
end
print(string.format("\n%d superati, %d falliti", superati, falliti))
os.exit(falliti == 0 and 0 or 1)
