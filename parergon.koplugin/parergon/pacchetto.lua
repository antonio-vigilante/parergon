--[[--
Modifiche ai file di pacchetto dell'EPUB: OPF (manifest, titolo, identificatore)
e toc.ncx (dtb:uid). Tutte chirurgiche, come in riscrivi.lua.

Perché si cambia il titolo (e, quando possibile, l'identificatore):
il server di sincronizzazione di Readest collega i libri sia con l'impronta del
file sia con un "meta hash" calcolato da titolo, autori e identificatore
(readest_syncconfig.lua, computeMetadataHashInfo; sync.ts: book_hash OR meta_hash).
Una copia con gli stessi metadati riceverebbe le annotazioni dell'originale, con
indirizzi ormai sbagliati per la copia. Un titolo diverso basta a separarle.

L'identificatore si cambia solo se il libro non usa l'offuscamento dei font:
la chiave di offuscamento IDPF/Adobe è ricavata proprio dall'identificatore.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local xmltok = require("parergon/xmltok")
local testo = require("parergon/testo")
local _ = require("parergon/i18n")

local M = {}

-- Algoritmi di encryption.xml che sono solo offuscamento dei font (non DRM).
M.OFFUSCAMENTO = {
    ["http://www.idpf.org/2008/embedding"] = true,
    ["http://ns.adobe.com/pdf/enc#RC"] = true,
}

--[[--
Esamina META-INF/encryption.xml e META-INF/rights.xml.
@param lettore lettore dell'EPUB
@param arch archivio (per sapere quali voci esistono)
@return { drm = bool, offuscati = { [percorso] = true } }
]]
function M.cifratura(lettore, arch)
    local r = { drm = false, offuscati = {} }
    if arch.perNome["META-INF/rights.xml"] then r.drm = true end
    if not arch.perNome["META-INF/encryption.xml"] then return r end
    local src = lettore.leggi("META-INF/encryption.xml")
    local doc = src and xmltok.analizza(src)
    if not doc then r.drm = true return r end -- illeggibile: per prudenza lo trattiamo come DRM
    for __, ed in ipairs(xmltok.tutti(doc.radice, function(el) return el.nome == "encrypteddata" end)) do
        local metodo = xmltok.trova(ed, "encryptionmethod")
        local rif = xmltok.trova(ed, "cipherreference")
        local alg = metodo and xmltok.attr(metodo).Algorithm
        local uri = rif and xmltok.attr(rif).URI
        if alg and M.OFFUSCAMENTO[alg] then
            if uri then r.offuscati[testo.decodificaEntita(uri)] = true end
        else
            r.drm = true
        end
    end
    return r
end

--- Rientro (spazi iniziali) della riga che contiene il byte `pos`.
local function rientroDi(src, pos)
    local inizio = src:sub(1, pos - 1):match(".*\n()") or 1
    return src:sub(inizio, pos - 1):match("^([ \t]*)") or ""
end

--- Inserimento di nuove voci <item> prima di </manifest>.
function M.voceManifest(libro, items)
    local man = xmltok.trova(libro.opf_doc.radice, "manifest")
    local src = libro.opf_src
    local ultimo
    for __, f in ipairs(man.figli) do if f.tipo == "el" and f.nome == "item" then ultimo = f end end
    local rientro = ultimo and rientroDi(src, ultimo.s) or "    "
    local prefisso = (man.qnome:match("^(.-:)") or "")
    local righe = {}
    for __, it in ipairs(items) do
        local attr = string.format('id="%s" href="%s" media-type="%s"',
            testo.escapeXml(it.id), testo.escapeXml(it.href), testo.escapeXml(it.tipo))
        if it.proprieta then attr = attr .. ' properties="' .. testo.escapeXml(it.proprieta) .. '"' end
        righe[#righe + 1] = rientro .. "<" .. prefisso .. "item " .. attr .. "/>"
    end
    -- Se </manifest> sta su una riga propria, le nuove voci diventano righe intere
    -- inserite all'inizio di quella riga; altrimenti vanno subito prima del tag.
    local pos = man.ie + 1
    local riga_propria = src:sub(1, pos - 1):match("\n([ \t]*)$")
    if riga_propria then
        return { pos = pos - #riga_propria, testo = table.concat(righe, "\n") .. "\n", peso = 2, ordine = 0 }
    end
    for k, r in ipairs(righe) do righe[k] = r:gsub("^[ \t]+", "") end
    return { pos = pos, testo = table.concat(righe, ""), peso = 2, ordine = 0 }
end

--- Inserimento di un <itemref> in fondo allo spine.
function M.voceSpine(libro, idref)
    local spine = libro.spine_el
    local src = libro.opf_src
    local ultimo
    for __, f in ipairs(spine.figli) do if f.tipo == "el" and f.nome == "itemref" then ultimo = f end end
    local prefisso = spine.qnome:match("^(.-:)") or ""
    local tag = "<" .. prefisso .. 'itemref idref="' .. testo.escapeXml(idref) .. '"/>'
    local pos = spine.ie + 1
    local riga_propria = src:sub(1, pos - 1):match("\n([ \t]*)$")
    if riga_propria then
        local rientro = ultimo and rientroDi(src, ultimo.s) or (riga_propria .. "  ")
        return { pos = pos - #riga_propria, testo = rientro .. tag .. "\n", peso = 2, ordine = 0 }
    end
    return { pos = pos, testo = tag, peso = 2, ordine = 0 }
end

--[[--
Inserimento di un <itemref> subito dopo un itemref esistente (per esempio la
copertina), oppure all'inizio dello spine se `dopo` è nil.
]]
function M.voceSpineDopo(libro, idref, dopo)
    local src = libro.opf_src
    local spine = libro.spine_el
    local prefisso = spine.qnome:match("^(.-:)") or ""
    local tag = "<" .. prefisso .. 'itemref idref="' .. testo.escapeXml(idref) .. '"/>'
    local riferimento = dopo
    if not riferimento then
        for __, f in ipairs(spine.figli) do if f.tipo == "el" and f.nome == "itemref" then riferimento = f break end end
        if not riferimento then return M.voceSpine(libro, idref) end
        -- prima del primo itemref, con lo stesso rientro
        local r = rientroDi(src, riferimento.s)
        local inizio_riga = src:sub(1, riferimento.s - 1):match(".*\n()") or riferimento.s
        if src:sub(inizio_riga, riferimento.s - 1):match("^[ \t]*$") then
            return { pos = inizio_riga, testo = r .. tag .. "\n", peso = 2, ordine = 0 }
        end
        return { pos = riferimento.s, testo = tag, peso = 2, ordine = 0 }
    end
    -- dopo l'itemref indicato: a capo con lo stesso rientro, se è su una riga propria
    local r = rientroDi(src, riferimento.s)
    if src:sub(riferimento.e + 1, riferimento.e + 1) == "\n" then
        return { pos = riferimento.e + 2, testo = r .. tag .. "\n", peso = 2, ordine = 0 }
    end
    return { pos = riferimento.e + 1, testo = tag, peso = 2, ordine = 0 }
end

--- Lingua del libro (primo dc:language), se indicata.
function M.lingua(libro)
    local meta = xmltok.trova(libro.opf_doc.radice, "metadata")
    local l = meta and xmltok.trova(meta, "language")
    if not l or l.vuoto then return nil end
    local v = testo.decodificaEntita(libro.opf_src:sub(l.is, l.ie)):match("^%s*(.-)%s*$")
    return v ~= "" and v or nil
end

--- Inserimento del suffisso nel primo dc:title (prima del tag di chiusura).
function M.suffissoTitolo(libro, suffisso)
    local meta = xmltok.trova(libro.opf_doc.radice, "metadata")
    local titolo = meta and xmltok.trova(meta, "title")
    if not titolo or titolo.vuoto then return nil end
    return { pos = titolo.ie + 1, testo = testo.escapeXml(suffisso), peso = 2, ordine = 0 }
end

--- Elemento dc:identifier indicato da unique-identifier.
function M.identificatore(libro)
    local pkg = xmltok.trova(libro.opf_doc.radice, "package")
    local uid = pkg and xmltok.attr(pkg)["unique-identifier"]
    local meta = xmltok.trova(libro.opf_doc.radice, "metadata")
    if not meta then return nil end
    local primo
    for __, el in ipairs(xmltok.tutti(meta, function(e) return e.nome == "identifier" end)) do
        primo = primo or el
        if uid and xmltok.attr(el).id == uid then return el end
    end
    return primo
end

--- Sostituzione del contenuto di dc:identifier.
function M.nuovoIdentificatore(libro, nuovo)
    local el = M.identificatore(libro)
    if not el or el.vuoto then return nil end
    return { pos = el.is, fino = el.ie, testo = testo.escapeXml(nuovo), peso = 2, ordine = 0 }
end

--- Valore attuale di dc:identifier (testo decodificato).
function M.valoreIdentificatore(libro)
    local el = M.identificatore(libro)
    if not el or el.vuoto then return nil end
    return testo.decodificaEntita(libro.opf_src:sub(el.is, el.ie)):match("^%s*(.-)%s*$")
end

--- Sostituzione dell'attributo content di <meta name="dtb:uid"> in toc.ncx.
function M.uidNcx(src_ncx, nuovo)
    local doc = xmltok.analizza(src_ncx)
    if not doc then return nil end
    for __, m in ipairs(xmltok.tutti(doc.radice, function(e) return e.nome == "meta" end)) do
        if xmltok.attr(m).name == "dtb:uid" then
            local tag = src_ncx:sub(m.s, m.is - 1)
            local a, b = tag:find('content%s*=%s*"[^"]*"')
            if not a then a, b = tag:find("content%s*=%s*'[^']*'") end
            if a then
                return { pos = m.s + a - 1, fino = m.s + b - 1,
                         testo = 'content="' .. testo.escapeXml(nuovo) .. '"', peso = 2, ordine = 0 }
            end
        end
    end
end

--[[--
Identificatore urn:uuid della copia, DERIVATO da quello dell'originale.

Deterministico: rigenerando la copia si ottiene sempre lo stesso identificatore,
così Readest e le altre applicazioni riconoscono le versioni successive della
copia come lo stesso libro (progressi, posto in libreria). È comunque diverso
da quello dell'originale, quindi le annotazioni delle due versioni non si mescolano.

I 128 bit vengono da quattro CRC-32 con sali diversi: non è crittografia, serve
solo un valore stabile e ben distribuito. Formato UUID versione 8 (RFC 9562,
"definito dall'applicazione").
@param sorgente identificatore dell'originale (o un altro testo stabile)
]]
function M.uuidDerivato(sorgente)
    local crc32 = require("parergon/crc32")
    local h = ""
    for i = 1, 4 do
        h = h .. string.format("%08x", crc32.calcola("parergon|" .. i .. "|" .. sorgente))
    end
    -- versione 8 nella 13ª cifra, variante RFC (10xx) nella 17ª
    local w = tonumber(h:sub(17, 17), 16)
    h = h:sub(1, 12) .. "8" .. h:sub(14, 16) .. string.format("%x", 8 + w % 4) .. h:sub(18)
    return "urn:uuid:" .. h:sub(1, 8) .. "-" .. h:sub(9, 12) .. "-" .. h:sub(13, 16)
        .. "-" .. h:sub(17, 20) .. "-" .. h:sub(21, 32)
end

-- Marcatore che identifica una copia prodotta da Parergon (meta in stile OPF 2,
-- ammesso anche in EPUB 3). Il valore è l'identificatore dell'originale.
M.MARCATORE = "parergon:source"

--- Valore del marcatore, se il libro è già una copia prodotta da Parergon.
function M.marcatore(libro)
    local meta = xmltok.trova(libro.opf_doc.radice, "metadata")
    if not meta then return nil end
    for __, m in ipairs(xmltok.tutti(meta, function(e) return e.nome == "meta" end)) do
        local a = xmltok.attr(m)
        if a.name == M.MARCATORE then return testo.decodificaEntita(a.content or "") end
    end
end

--- Inserimento del marcatore prima di </metadata>.
function M.voceMarcatore(libro, valore)
    local meta = xmltok.trova(libro.opf_doc.radice, "metadata")
    if not meta or meta.vuoto then return nil end
    local src = libro.opf_src
    local pos = meta.ie + 1
    local prefisso = meta.qnome:match("^(.-:)") or ""
    local tag = "<" .. prefisso .. 'meta name="' .. M.MARCATORE .. '" content="' .. testo.escapeXml(valore) .. '"/>'
    local riga_propria = src:sub(1, pos - 1):match("\n([ \t]*)$")
    if riga_propria then
        local ultimo
        for __, f in ipairs(meta.figli) do if f.tipo == "el" then ultimo = f end end
        local rientro = ultimo and rientroDi(src, ultimo.s) or (riga_propria .. "  ")
        return { pos = pos - #riga_propria, testo = rientro .. tag .. "\n", peso = 2, ordine = 0 }
    end
    return { pos = pos, testo = tag, peso = 2, ordine = 0 }
end

function M.messaggioDrm()
    return _("This book is protected by DRM: Parergon cannot modify it.")
end

return M
