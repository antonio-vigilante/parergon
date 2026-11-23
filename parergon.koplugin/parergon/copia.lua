--[[--
Creazione della copia consolidata dell'EPUB (fase 3: evidenziazioni permanenti).

Sequenza:
  1. analisi delle annotazioni (analisi.lua): file e segmenti di byte;
  2. controllo DRM;
  3. per ogni file XHTML: forme/colori, sovrapposizioni, inserimenti, verifica;
  4. foglio di stile parergon.css, voce nel manifest, titolo (e identificatore);
  5. scrittura dello zip su un file temporaneo: mimetype per primo, voci non
     modificate copiate byte per byte, voci modificate ricompresse;
  6. verifica del file scritto; solo allora rinomina al nome definitivo.

L'originale viene soltanto letto. Le annotazioni di KOReader non vengono toccate
e non vengono riportate nella copia (i loro indirizzi non sarebbero più validi).

Modulo in Lua puro: file system e compressione arrivano dall'esterno.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local analisi = require("parergon/analisi")
local crc32 = require("parergon/crc32")
local epub = require("parergon/epub")
local pacchetto = require("parergon/pacchetto")
local riscrivi = require("parergon/riscrivi")
local stile = require("parergon/stile")
local toc = require("parergon/toc")
local xmltok = require("parergon/xmltok")
local zip = require("parergon/zip")
local frontespizio = require("parergon/frontespizio")
local indice = require("parergon/indice")
local note = require("parergon/note")
local testo = require("parergon/testo")
local zipscrivi = require("parergon/zipscrivi")
local _ = require("parergon/i18n")

local M = {}

-- Tipi di file già compressi: si salvano senza deflate se dovessero essere riscritti.
local GIA_COMPRESSI = { jpg = true, jpeg = true, png = true, gif = true, webp = true,
    mp3 = true, mp4 = true, m4a = true, woff = true, woff2 = true, otf = false, ttf = false }

local function compressibile(nome)
    local est = nome:match("%.([%w]+)$")
    return not (est and GIA_COMPRESSI[est:lower()])
end

--- Nome libero nella cartella `base` (parergon.css, parergon-2.css, ...).
local function nomeLibero(arch, base, radice, est)
    local nome = base .. radice .. "." .. est
    local n = 1
    while arch.perNome[nome] do
        n = n + 1
        nome = base .. radice .. "-" .. n .. "." .. est
    end
    return nome
end

local function idLibero(libro, radice)
    local id, n = radice, 1
    while libro.perId[id] do n = n + 1 id = radice .. "-" .. n end
    return id
end

--- Percorso della copia: «cartella/Titolo (suffisso).epub».
function M.percorsoCopia(originale, suffisso)
    local cartella, nome = originale:match("^(.*[/\\])([^/\\]+)$")
    if not cartella then cartella, nome = "", originale end
    local base = nome:gsub("%.[Ee][Pp][Uu][Bb]$", "")
    return cartella .. base .. " (" .. suffisso .. ").epub"
end

--[[--
Verifica un archivio appena scritto.
@return true, oppure false e motivo
]]
function M.verificaArchivio(percorso, attese)
    local arch, err = zip.apri(percorso)
    if not arch then return false, err end
    local primo = arch.voci[1]
    if not primo or primo.nome ~= "mimetype" or primo.metodo ~= 0 then
        return false, _("the mimetype file is not the first, uncompressed entry")
    end
    if zip.leggiNonCompresso(arch, "mimetype") ~= "application/epub+zip" then
        return false, _("invalid mimetype content")
    end
    if #arch.voci ~= attese then
        return false, _.trf("unexpected number of entries: %d instead of %d", #arch.voci, attese)
    end
    for __, v in ipairs(arch.voci) do
        local dati, derr = zip.datiGrezzi(arch, v)
        if not dati then return false, v.nome .. ": " .. tostring(derr) end
        if v.est_locale ~= 0 and v.nome == "mimetype" then
            return false, _("the mimetype entry has an extra field")
        end
        if v.metodo == 0 and crc32.calcola(dati) ~= v.crc then
            return false, _.trf("wrong checksum for %s", v.nome)
        end
    end
    return true
end

--[[--
Crea la copia consolidata.
@param p tabella:
  originale    — percorso dell'EPUB originale
  lettore      — lettore del contenuto (main.lua o test)
  annotazioni  — annotazioni di KOReader
  versione_dom — cre_dom_version
  prefisso     — funzione facoltativa (vedi analisi.lua)
  imp          — impostazioni di stile (stile.risolvi)
  destinazione — percorso della copia
  comprimi     — funzione di deflate grezzo, o nil
  suffisso     — testo da aggiungere al titolo, per esempio " (annotated)"
  rinomina     — funzione(da, a) facoltativa (predefinita: os.remove + os.rename)
  opzioni      — { evidenziazioni = bool, note = bool, filtro = "tutte" | "con_nota",
                   note_modo = "testo" | "comparsa", corsivo = bool,
                   indice = bool, indice_criterio = "tutte" | "con_tema" | "con_nota",
                   indice_ordine = "alfabetico" | "posizione",
                   indice_toc_sottotemi = bool (sotto-temi anche nella TOC; predefinito no),
                   frase_lettore = testo della nota di lettura nel frontespizio, o nil }
                 (predefinito: tutto attivo, tutte le annotazioni, note nel testo in corsivo)
@return rapporto { destinazione, consolidate, evidenziazioni, note, escluse,
                   saltate = { {ann, codice, motivo} }, nuovo_id }
        oppure nil e messaggio d'errore
]]
function M.crea(p)
    if p.destinazione == p.originale then
        return nil, _("the copy cannot have the same name as the original")
    end
    local opz = p.opzioni or {}
    local con_evid = opz.evidenziazioni ~= false
    local con_note = opz.note ~= false
    local solo_con_nota = opz.filtro == "con_nota"
    local a_comparsa = opz.note_modo == "comparsa" -- note a comparsa invece che nel testo
    local con_indice = opz.indice == true

    local arch, aerr = zip.apri(p.originale)
    if not arch then return nil, aerr end
    for __, v in ipairs(arch.voci) do
        if v.flag % 2 == 1 then return nil, pacchetto.messaggioDrm() end -- voce ZIP cifrata
    end
    local cifr = pacchetto.cifratura(p.lettore, arch)
    if cifr.drm then return nil, pacchetto.messaggioDrm() end

    local rapporto = { destinazione = p.destinazione, consolidate = 0, evidenziazioni = 0, note = 0,
        escluse = 0, saltate = {}, a_comparsa = opz.note_modo == "comparsa" }
    local function salta(e, codice, motivo)
        rapporto.saltate[#rapporto.saltate + 1] = { ann = e.ann, codice = codice, motivo = motivo }
    end

    -- quali annotazioni entrano: filtro "solo con una nota"; segnalibri di pagina con nota
    local scelte = {}
    for __, a in ipairs(p.annotazioni) do
        local n = note.analizza(a)
        if a.drawer then
            if solo_con_nota and n.vuota then
                rapporto.escluse = rapporto.escluse + 1
            else
                scelte[#scelte + 1] = a
            end
        elseif con_note and not n.vuota then
            -- segnalibro di pagina con nota: nessun passo a cui agganciarla (per ora)
            salta({ ann = a }, "segnalibro", _("page bookmark: notes without a highlighted passage are not supported yet"))
        end
    end

    local ris, err = analisi.analizza{
        lettore = p.lettore, annotazioni = scelte,
        versione_dom = p.versione_dom, prefisso = p.prefisso,
    }
    if not ris then return nil, err end
    local libro = ris.libro
    -- EPUB 2 (XHTML 1.1): niente <section>, epub:type né role, né nelle pagine aggiunte
    -- né nei richiami delle note; KOReader riconosce comunque i richiami [n] come note
    local epub2 = tostring(libro.versione or "2.0"):sub(1, 1) == "2"

    -- foglio di stile: nella cartella dell'OPF
    local css_nome = nomeLibero(arch, libro.base, "parergon", "css")
    local css_id = idLibero(libro, "parergon-css")

    -- raggruppa per file
    local perFile, ordineFile = {}, {}
    for i, e in ipairs(ris.esiti) do
        if e.esito.ok then
            local f = e.voce.percorso
            if cifr.offuscati[f] then
                salta(e, "cifrato", _("the file is encrypted"))
            else
                if not perFile[f] then perFile[f] = {} ordineFile[#ordineFile + 1] = f end
                e.ordine = i
                table.insert(perFile[f], e)
            end
        else
            salta(e, e.esito.codice or "assente", e.esito.motivo)
        end
    end

    -- pagina «Note del lettore» (solo per le note a comparsa)
    local pagina_nome = nomeLibero(arch, libro.base, "parergon-notes", "xhtml")
    local pagina_id = idLibero(libro, "parergon-notes")
    local voci_pagina, num_nota = {}, 0
    local voci_indice = {} -- annotazioni scritte nella copia, per l'indice personale

    local modificati, usate, giaUsata = {}, {}, {}
    local usa_note, usa_richiami = false, false
    local contatore = 0
    for __, f in ipairs(ordineFile) do
        local src = p.lettore.leggi(f)
        local doc = src and xmltok.analizza(src)
        local accettate = perFile[f]
        if con_evid then
            -- le sovrapposizioni contano solo se si avvolge il testo
            local scartate
            accettate, scartate = riscrivi.senzaSovrapposizioni(perFile[f])
            -- un'evidenziazione tutta dentro un'altra non si avvolge una seconda volta, ma
            -- la sua nota e i suoi temi si conservano (libro reale: un passo lungo del cap. 5
            -- conteneva una sottolineatura con #tempo-pieno). La nota va dopo la fine di
            -- quella che la contiene: dentro sarebbe sottolineata anche lei.
            local assorbite = {}
            for __, s in ipairs(scartate) do
                if s.codice == "contenuta" and s.contenitore and (con_note or con_indice)
                        and not note.analizza(s.ann).vuota then
                    s.assorbita = true
                    assorbite[#assorbite + 1] = s
                else
                    salta(s, s.codice, s.motivo)
                end
            end
            if #assorbite > 0 then
                for __, s in ipairs(assorbite) do accettate[#accettate + 1] = s end
                table.sort(accettate, function(a, b)
                    if a.esito.inizio ~= b.esito.inizio then return a.esito.inizio < b.esito.inizio end
                    if a.esito.fine ~= b.esito.fine then return a.esito.fine > b.esito.fine end
                    return (a.ordine or 0) < (b.ordine or 0)
                end)
            end
        end
        local inserimenti, efficaci, evid_f, note_f, assorbite_f = {}, {}, 0, 0, 0
        local voci_f, num_iniziale = {}, num_nota
        for __, e in ipairs(accettate) do
            contatore = contatore + 1
            e.id = "parergon-" .. contatore
            local scritto = false
            -- dove va la nota: dopo il passo, o dopo l'evidenziazione che lo contiene
            local esito_nota = e.assorbita and e.contenitore.esito or e.esito
            if con_evid and not e.assorbita then
                local forma, colore = stile.risolvi(e.ann, p.imp)
                local chiave = forma .. "|" .. colore
                if not giaUsata[chiave] then
                    giaUsata[chiave] = true
                    usate[#usate + 1] = { forma, colore }
                end
                for __, ins in ipairs(riscrivi.avvolgi(e.esito.segmenti, stile.classe(forma, colore), e.id, contatore)) do
                    inserimenti[#inserimenti + 1] = ins
                end
                evid_f = evid_f + 1
                scritto = true
            end
            if con_note and a_comparsa then
                local x = note.xhtml(note.analizza(e.ann).corpo, true)
                if x then
                    num_nota = num_nota + 1
                    local id_r, id_n = "parergon-r-" .. num_nota, "parergon-n-" .. num_nota
                    inserimenti[#inserimenti + 1] = riscrivi.richiamo(esito_nota, num_nota,
                        epub.relativo(f, pagina_nome) .. "#" .. id_n, id_r, contatore, epub2)
                    local passo = testo.primiCaratteri(testo.normalizza(e.ann.text), 120)
                    voci_f[#voci_f + 1] = {
                        numero = num_nota, id = id_n, corpo = x,
                        ritorno = epub.relativo(pagina_nome, f) .. "#" .. id_r,
                        passo = passo .. (testo.lunghezza(testo.normalizza(e.ann.text)) > 120 and "…" or ""),
                        capitolo = e.ann.chapter,
                    }
                    note_f = note_f + 1
                    scritto = true
                end
            elseif con_note then
                local x = note.xhtml(note.analizza(e.ann).corpo)
                if x then
                    inserimenti[#inserimenti + 1] = riscrivi.nota(esito_nota, x, contatore)
                    note_f = note_f + 1
                    scritto = true
                end
            end
            if con_indice then
                -- l'indice ha bisogno di un'àncora sul passo: con le evidenziazioni è
                -- l'id del primo span, altrimenti uno span vuoto (scritto per esteso:
                -- crengine legge i file con un parser HTML, che non capisce <span/>)
                if not con_evid or e.assorbita then
                    inserimenti[#inserimenti + 1] = { pos = e.esito.segmenti[1].s,
                        testo = '<span id="' .. e.id .. '"></span>', peso = 2, ordine = contatore }
                end
                scritto = true
            end
            if scritto then
                efficaci[#efficaci + 1] = e
                if e.assorbita then assorbite_f = assorbite_f + 1 end
            end
        end
        if #voci_f > 0 and not epub2 then
            -- epub:type richiede il prefisso dichiarato (i file EPUB 2 di solito non lo hanno)
            local d = riscrivi.dichiaraEpub(doc)
            if d then inserimenti[#inserimenti + 1] = d end
        end
        if #inserimenti > 0 then
            local link, lerr = riscrivi.collegaCss(doc, epub.relativo(f, css_nome))
            local nuovo, verr
            if link then
                inserimenti[#inserimenti + 1] = link
                nuovo = riscrivi.applica(src, inserimenti)
                local ok
                ok, verr = riscrivi.verifica(src, nuovo)
                if not ok then nuovo = nil end
            else
                verr = lerr
            end
            if nuovo then
                modificati[f] = nuovo
                rapporto.consolidate = rapporto.consolidate + #efficaci
                rapporto.evidenziazioni = rapporto.evidenziazioni + evid_f
                rapporto.note = rapporto.note + note_f
                rapporto.assorbite = (rapporto.assorbite or 0) + assorbite_f
                if note_f > 0 then
                    if a_comparsa then usa_richiami = true else usa_note = true end
                end
                for __, v in ipairs(voci_f) do voci_pagina[#voci_pagina + 1] = v end
                if con_indice then
                    for __, e in ipairs(efficaci) do
                        voci_indice[#voci_indice + 1] = { id = e.id, file = f, ann = e.ann }
                    end
                end
            else
                -- il file resta invariato: i numeri delle sue note tornano disponibili
                num_nota = num_iniziale
                for __, e in ipairs(efficaci) do
                    salta(e, "struttura", _.trf("the file could not be modified safely (%s)", tostring(verr)))
                end
            end
        end
    end
    local lingua = pacchetto.lingua(libro)
    local nuovi = {} -- file da aggiungere all'archivio, in ordine: { nome, contenuto }
    local ins_opf = {}
    local voci_manifest = {}
    local rami_toc = {} -- voci da aggiungere in fondo alla TOC (nav e ncx)
    local spine_ordine = 0
    local function inFondoAlloSpine(id)
        spine_ordine = spine_ordine + 1
        local s = pacchetto.voceSpine(libro, id)
        s.ordine = spine_ordine -- più pagine nuove: restano nell'ordine in cui sono aggiunte
        ins_opf[#ins_opf + 1] = s
    end

    -- indice personale: pagina in fondo al libro e ramo separato nella TOC
    local usa_indice = false
    if con_indice and #voci_indice > 0 then
        local struttura = indice.costruisci(voci_indice, { criterio = opz.indice_criterio, ordine = opz.indice_ordine })
        if struttura.n > 0 then
            local nome = nomeLibero(arch, libro.base, "parergon-index", "xhtml")
            local id = idLibero(libro, "parergon-index")
            local titolo = _("Personal index")
            local xhtml, gruppi = indice.pagina(struttura, {
                titolo = titolo, lingua = lingua, css = epub.relativo(nome, css_nome),
                nome_pagina = nome, relativo = epub.relativo,
                sottotemi_toc = opz.indice_toc_sottotemi == true, epub2 = epub2,
            })
            nuovi[#nuovi + 1] = { nome, xhtml }
            voci_manifest[#voci_manifest + 1] = { id = id, href = epub.relativo(libro.opf, nome), tipo = "application/xhtml+xml" }
            inFondoAlloSpine(id)
            local ramo = { titolo = titolo, pagina = nome, figli = {} }
            local function ramoDi(g)
                local r = { titolo = g.titolo, pagina = nome, frammento = g.href, figli = {} }
                for __, f in ipairs(g.figli or {}) do r.figli[#r.figli + 1] = ramoDi(f) end
                return r
            end
            for __, g in ipairs(gruppi) do ramo.figli[#ramo.figli + 1] = ramoDi(g) end
            rami_toc[#rami_toc + 1] = ramo
            rapporto.indice = struttura.n
            rapporto.indice_gruppi = #gruppi
            usa_indice = true
        end
    end

    if #voci_pagina > 0 then
        nuovi[#nuovi + 1] = { pagina_nome, note.pagina{
            titolo = _("Reader's notes"),
            lingua = lingua, epub2 = epub2,
            css = epub.relativo(pagina_nome, css_nome),
            voci = voci_pagina,
        } }
        voci_manifest[#voci_manifest + 1] = { id = pagina_id, href = epub.relativo(libro.opf, pagina_nome),
            tipo = "application/xhtml+xml" }
        -- in fondo allo spine, come pagina di note finali
        inFondoAlloSpine(pagina_id)
        rami_toc[#rami_toc + 1] = { titolo = _("Reader's notes"), pagina = pagina_nome }
    end

    -- nota di lettura nel frontespizio (o in una pagina dedicata dopo la copertina)
    local usa_lettore = false
    if type(opz.frase_lettore) == "string" and opz.frase_lettore:match("%S") then
        local frase = opz.frase_lettore:match("^%s*(.-)%s*$")
        local dove = frontespizio.trova(libro, p.lettore)
        local fatto = false
        if dove.frontespizio and not cifr.offuscati[dove.frontespizio] then
            local f = dove.frontespizio
            local src = modificati[f] or p.lettore.leggi(f)
            local ins = src and frontespizio.inserimento(src, frase)
            if ins then
                local lista = { ins }
                local rel = epub.relativo(f, css_nome)
                if not src:find('href="' .. rel .. '"', 1, true) then
                    local link = riscrivi.collegaCss(xmltok.analizza(src), rel)
                    if link then lista[#lista + 1] = link end
                end
                local nuovo = riscrivi.applica(src, lista)
                if riscrivi.verifica(src, nuovo) then
                    modificati[f] = nuovo
                    rapporto.lettore = { dove = "frontespizio", file = f }
                    fatto = true
                end
            end
        end
        if not fatto then
            local nome = nomeLibero(arch, libro.base, "parergon-reader", "xhtml")
            local id = idLibero(libro, "parergon-reader")
            nuovi[#nuovi + 1] = { nome, frontespizio.pagina(frase, {
                titolo = frase, lingua = lingua, css = epub.relativo(nome, css_nome), epub2 = epub2 }) }
            voci_manifest[#voci_manifest + 1] = { id = id, href = epub.relativo(libro.opf, nome), tipo = "application/xhtml+xml" }
            ins_opf[#ins_opf + 1] = pacchetto.voceSpineDopo(libro, id, dove.copertina)
            rapporto.lettore = { dove = "pagina", file = nome, dopo_copertina = dove.copertina ~= nil }
        end
        usa_lettore = true
    end

    -- TOC: ramo separato in fondo, in nav.xhtml e in toc.ncx (le voci dell'autore restano intatte)
    if #rami_toc > 0 then
        local function vociPer(da)
            local function converti(r)
                local v = { titolo = r.titolo, href = epub.relativo(da, r.pagina) .. (r.frammento or ""), figli = {} }
                for __, f in ipairs(r.figli or {}) do v.figli[#v.figli + 1] = converti(f) end
                return v
            end
            local out = {}
            for __, r in ipairs(rami_toc) do out[#out + 1] = converti(r) end
            return out
        end
        if libro.nav then
            local n = libro.nav.percorso
            local src = modificati[n] or p.lettore.leggi(n)
            local ins = src and toc.nav(src, vociPer(n))
            if ins then
                local nuovo = riscrivi.applica(src, { ins })
                if riscrivi.verifica(src, nuovo) then modificati[n] = nuovo rapporto.toc_nav = true end
            end
        end
        if libro.ncx then
            local n = libro.ncx.percorso
            local src = modificati[n] or p.lettore.leggi(n)
            local ins = src and toc.ncx(src, vociPer(n))
            if ins then
                local nuovo = riscrivi.applica(src, ins)
                if riscrivi.verifica(src, nuovo) then modificati[n] = nuovo rapporto.toc_ncx = true end
            end
        end
    end

    local serve_css = #usate > 0 or usa_note or usa_richiami or usa_indice or usa_lettore
    -- OPF: voce del CSS, titolo distinto, marcatore, identificatore derivato se possibile
    if serve_css then
        table.insert(voci_manifest, 1, { id = css_id, href = epub.relativo(libro.opf, css_nome), tipo = "text/css" })
    end
    if #voci_manifest > 0 then
        ins_opf[#ins_opf + 1] = pacchetto.voceManifest(libro, voci_manifest)
    end
    local t = p.suffisso and pacchetto.suffissoTitolo(libro, p.suffisso)
    if t then ins_opf[#ins_opf + 1] = t end
    local id_originale = pacchetto.valoreIdentificatore(libro)
    -- marcatore "questa è una copia di Parergon" (una sola volta)
    if not pacchetto.marcatore(libro) then
        local m = pacchetto.voceMarcatore(libro, id_originale or "")
        if m then ins_opf[#ins_opf + 1] = m end
    end
    local offuscamento = next(cifr.offuscati) ~= nil
    if not offuscamento then
        -- derivato dall'originale: stabile fra una rigenerazione e l'altra
        local nome_file = p.originale:match("([^/\\]+)$") or p.originale
        rapporto.nuovo_id = pacchetto.uuidDerivato(id_originale or ("file:" .. nome_file))
        local idi = pacchetto.nuovoIdentificatore(libro, rapporto.nuovo_id)
        if idi then
            ins_opf[#ins_opf + 1] = idi
            -- toc.ncx deve riportare lo stesso identificatore (dtb:uid)
            if libro.ncx then
                local ncx = modificati[libro.ncx.percorso] or p.lettore.leggi(libro.ncx.percorso)
                local u = ncx and pacchetto.uidNcx(ncx, rapporto.nuovo_id)
                if u then modificati[libro.ncx.percorso] = riscrivi.applica(ncx, { u }) end
            end
        else
            rapporto.nuovo_id = nil
        end
    end
    local opf_nuovo = riscrivi.applica(libro.opf_src, ins_opf)
    local okopf, eopf = riscrivi.verifica(libro.opf_src, opf_nuovo)
    if not okopf then return nil, _.trf("the OPF file could not be modified safely (%s)", tostring(eopf)) end
    modificati[libro.opf] = opf_nuovo

    -- la struttura modificata deve restare leggibile come EPUB
    local controllo = epub.leggi({ leggi = function(n)
        return modificati[n] or p.lettore.leggi(n)
    end })
    if not controllo then return nil, _("the modified OPF file cannot be read back") end

    -- scrittura
    local tmp = p.destinazione .. ".tmp"
    local w, werr = zipscrivi.nuovo(tmp, { comprimi = p.comprimi })
    if not w then return nil, _.trf("cannot create the copy: %s", tostring(werr)) end
    local ok, errScrittura = pcall(function()
        w:aggiungi("mimetype", "application/epub+zip", false)
        for __, v in ipairs(arch.voci) do
            if v.nome ~= "mimetype" then
                local nuovo = modificati[v.nome]
                if nuovo then
                    w:aggiungi(v.nome, nuovo, compressibile(v.nome))
                else
                    local grezzi = assert(zip.datiGrezzi(arch, v))
                    w:copia(v, grezzi)
                end
            end
        end
        if serve_css then
            w:aggiungi(css_nome, stile.css(usate, {
                note = usa_note, corsivo = opz.corsivo ~= false,
                richiami = usa_richiami, richiamo = p.imp and p.imp.richiamo,
                pagina_note = #voci_pagina > 0, indice = usa_indice, lettore = usa_lettore,
            }), true)
        end
        for __, n in ipairs(nuovi) do w:aggiungi(n[1], n[2], true) end
        w:chiudi()
    end)
    if not ok then
        w:annulla()
        return nil, _.trf("error while writing the copy: %s", tostring(errScrittura))
    end
    local attese = 1 + #arch.voci - (arch.perNome["mimetype"] and 1 or 0) + (serve_css and 1 or 0) + #nuovi
    local okv, everifica = M.verificaArchivio(tmp, attese)
    if not okv then
        os.remove(tmp)
        return nil, _.trf("the copy failed verification: %s", tostring(everifica))
    end

    -- rinomina (su FAT e su Windows rename non sovrascrive: si cancella prima la
    -- vecchia copia consolidata, mai l'originale)
    local rinomina = p.rinomina or function(da, a)
        os.remove(a)
        return os.rename(da, a)
    end
    local okr, errr = rinomina(tmp, p.destinazione)
    if not okr then
        os.remove(tmp)
        return nil, _.trf("cannot rename the copy: %s", tostring(errr))
    end
    return rapporto
end

--- Riepilogo testuale: conteggi e motivi raggruppati.
function M.riepilogo(rapporto)
    local righe = {
        _.trf("Highlights written into the copy: %d", rapporto.evidenziazioni or rapporto.consolidate),
        rapporto.a_comparsa and _.trf("Pop-up notes (with a page of reader's notes): %d", rapporto.note or 0)
            or _.trf("Notes written into the text: %d", rapporto.note or 0),
    }
    if (rapporto.assorbite or 0) > 0 then
        righe[#righe + 1] = _.trf("Highlights inside another one (note and themes kept): %d", rapporto.assorbite)
    end
    if rapporto.indice then
        righe[#righe + 1] = _.trf("Personal index: %d entries in %d groups", rapporto.indice, rapporto.indice_gruppi or 0)
    end
    if rapporto.lettore then
        righe[#righe + 1] = rapporto.lettore.dove == "frontespizio"
            and _("Reading note: added to the title page")
            or _("Reading note: on a new page (title page not identified with certainty)")
    end
    if (rapporto.escluse or 0) > 0 then
        righe[#righe + 1] = _.trf("Not included (no note): %d", rapporto.escluse)
    end
    righe[#righe + 1] = _.trf("Skipped: %d", #rapporto.saltate)
    local perMotivo, ordine = {}, {}
    for __, s in ipairs(rapporto.saltate) do
        if not perMotivo[s.motivo] then perMotivo[s.motivo] = 0 ordine[#ordine + 1] = s.motivo end
        perMotivo[s.motivo] = perMotivo[s.motivo] + 1
    end
    for __, m in ipairs(ordine) do
        righe[#righe + 1] = "  • " .. m .. ": " .. perMotivo[m]
    end
    return table.concat(righe, "\n")
end

return M
