--[[--
Gestione del testo: UTF-8, entità, normalizzazione con mappa verso i byte del sorgente.

Modulo in Lua puro (nessuna dipendenza da KOReader), testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local M = {}

-- ---------------------------------------------------------------------------
-- UTF-8
-- ---------------------------------------------------------------------------

--- Restituisce la lunghezza in byte del carattere UTF-8 che inizia con il byte `b`.
local function lunghezzaUtf8(b)
    if b < 0x80 then return 1
    elseif b >= 0xF0 then return 4
    elseif b >= 0xE0 then return 3
    elseif b >= 0xC0 then return 2
    end
    return 1 -- byte di continuazione isolato: lo trattiamo come un carattere a sé
end
M.lunghezzaUtf8 = lunghezzaUtf8

--- Codifica un punto di codice Unicode in UTF-8.
function M.codificaUtf8(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    elseif cp < 0x110000 then
        return string.char(0xF0 + math.floor(cp / 0x40000),
                           0x80 + math.floor(cp / 0x1000) % 0x40,
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    end
    return "\239\191\189" -- U+FFFD carattere sostitutivo
end

--- Numero di caratteri UTF-8 in una stringa.
function M.lunghezza(s)
    local n, i, len = 0, 1, #s
    while i <= len do
        i = i + lunghezzaUtf8(s:byte(i))
        n = n + 1
    end
    return n
end

--- Primi `n` caratteri (non byte) di una stringa UTF-8.
function M.primiCaratteri(s, n)
    local i, len, k = 1, #s, 0
    while i <= len and k < n do
        i = i + lunghezzaUtf8(s:byte(i))
        k = k + 1
    end
    return s:sub(1, i - 1), i <= len
end

-- ---------------------------------------------------------------------------
-- Entità
-- ---------------------------------------------------------------------------

-- Entità XML predefinite più le entità HTML più frequenti nei libri.
-- crengine riconosce l'insieme completo di HTML; qui teniamo quelle che compaiono
-- realmente negli EPUB. Un'entità sconosciuta resta com'è (e il confronto
-- probabilmente fallirà, con segnalazione nel rapporto: nessun danno).
local ENTITA = {
    amp = 38, lt = 60, gt = 62, quot = 34, apos = 39,
    nbsp = 0xA0, shy = 0xAD, ensp = 0x2002, emsp = 0x2003, thinsp = 0x2009,
    zwnj = 0x200C, zwj = 0x200D, lrm = 0x200E, rlm = 0x200F,
    ndash = 0x2013, mdash = 0x2014, lsquo = 0x2018, rsquo = 0x2019, sbquo = 0x201A,
    ldquo = 0x201C, rdquo = 0x201D, bdquo = 0x201E, laquo = 0xAB, raquo = 0xBB,
    lsaquo = 0x2039, rsaquo = 0x203A, hellip = 0x2026, bull = 0x2022, middot = 0xB7,
    prime = 0x2032, Prime = 0x2033, dagger = 0x2020, Dagger = 0x2021, permil = 0x2030,
    copy = 0xA9, reg = 0xAE, trade = 0x2122, deg = 0xB0, sect = 0xA7, para = 0xB6,
    iexcl = 0xA1, iquest = 0xBF, cent = 0xA2, pound = 0xA3, euro = 0x20AC, yen = 0xA5,
    times = 0xD7, divide = 0xF7, plusmn = 0xB1, frac12 = 0xBD, frac14 = 0xBC, frac34 = 0xBE,
    sup1 = 0xB9, sup2 = 0xB2, sup3 = 0xB3, ordf = 0xAA, ordm = 0xBA, micro = 0xB5,
    Agrave = 0xC0, Aacute = 0xC1, Acirc = 0xC2, Atilde = 0xC3, Auml = 0xC4, Aring = 0xC5,
    AElig = 0xC6, Ccedil = 0xC7, Egrave = 0xC8, Eacute = 0xC9, Ecirc = 0xCA, Euml = 0xCB,
    Igrave = 0xCC, Iacute = 0xCD, Icirc = 0xCE, Iuml = 0xCF, Ntilde = 0xD1,
    Ograve = 0xD2, Oacute = 0xD3, Ocirc = 0xD4, Otilde = 0xD5, Ouml = 0xD6, Oslash = 0xD8,
    Ugrave = 0xD9, Uacute = 0xDA, Ucirc = 0xDB, Uuml = 0xDC, Yacute = 0xDD, szlig = 0xDF,
    agrave = 0xE0, aacute = 0xE1, acirc = 0xE2, atilde = 0xE3, auml = 0xE4, aring = 0xE5,
    aelig = 0xE6, ccedil = 0xE7, egrave = 0xE8, eacute = 0xE9, ecirc = 0xEA, euml = 0xEB,
    igrave = 0xEC, iacute = 0xED, icirc = 0xEE, iuml = 0xEF, ntilde = 0xF1,
    ograve = 0xF2, oacute = 0xF3, ocirc = 0xF4, otilde = 0xF5, ouml = 0xF6, oslash = 0xF8,
    ugrave = 0xF9, uacute = 0xFA, ucirc = 0xFB, uuml = 0xFC, yacute = 0xFD, yuml = 0xFF,
    OElig = 0x152, oelig = 0x153, Scaron = 0x160, scaron = 0x161, Yuml = 0x178,
    alpha = 0x3B1, beta = 0x3B2, gamma = 0x3B3, delta = 0x3B4, pi = 0x3C0, omega = 0x3C9,
}

--- Prova a decodificare un'entità che inizia alla posizione `i` di `s` (dove s[i] == "&").
-- Restituisce il carattere UTF-8 e la posizione dell'ultimo byte dell'entità, oppure nil.
local function decodificaEntita(s, i, fine)
    local j = s:find(";", i + 1, true)
    if not j or j > fine or j - i > 32 then return nil end
    local corpo = s:sub(i + 1, j - 1)
    local cp
    if corpo:sub(1, 1) == "#" then
        if corpo:sub(2, 2) == "x" or corpo:sub(2, 2) == "X" then
            cp = tonumber(corpo:sub(3), 16)
        else
            cp = tonumber(corpo:sub(2), 10)
        end
    else
        cp = ENTITA[corpo]
    end
    if not cp then return nil end
    return M.codificaUtf8(cp), j
end

--- Decodifica le entità di una stringa (per i valori degli attributi, i titoli, ecc.).
function M.decodificaEntita(s)
    return (s:gsub("&(#?[%w]+);", function(corpo)
        local c = decodificaEntita("&" .. corpo .. ";", 1, #corpo + 2)
        return c or ("&" .. corpo .. ";")
    end))
end

--- Escape per inserire testo in XML (contenuto o attributo).
function M.escapeXml(s)
    return (s:gsub("[&<>\"]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

--[[--
Inizio di una pagina XHTML aggiunta alla copia, fino a <body> compreso.
EPUB 3: DOCTYPE HTML5, lang e xml:lang, prefisso epub se richiesto.
EPUB 2: DOCTYPE XHTML 1.1, solo xml:lang (lang non esiste in XHTML 1.1), niente
prefisso epub, perché epub:type non è ammesso.
@param p { titolo, css (href relativo), lingua, epub2 = bool, ns_epub = bool }
@return lista di righe
]]
function M.inizioPagina(p)
    local e = M.escapeXml
    local lingua = ""
    if p.lingua then
        lingua = (p.epub2 and "" or (' lang="' .. e(p.lingua) .. '"')) .. ' xml:lang="' .. e(p.lingua) .. '"'
    end
    return {
        '<?xml version="1.0" encoding="UTF-8"?>',
        p.epub2 and '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'
            or "<!DOCTYPE html>",
        '<html xmlns="http://www.w3.org/1999/xhtml"'
            .. ((p.ns_epub and not p.epub2) and ' xmlns:epub="http://www.idpf.org/2007/ops"' or "") .. lingua .. ">",
        "<head>",
        "  <title>" .. e(p.titolo) .. "</title>",
        '  <link rel="stylesheet" type="text/css" href="' .. e(p.css) .. '"/>',
        "</head>",
        "<body>",
    }
end

-- ---------------------------------------------------------------------------
-- Normalizzazione
-- ---------------------------------------------------------------------------

-- Caratteri considerati "spazio" nel confronto (in UTF-8).
local SPAZI = {
    [" "] = true, ["\t"] = true, ["\n"] = true, ["\r"] = true, ["\f"] = true,
    ["\194\160"] = true,                         -- U+00A0 spazio non separabile
    ["\225\154\128"] = true,                     -- U+1680
    ["\226\128\128"] = true, ["\226\128\129"] = true, ["\226\128\130"] = true, -- U+2000..
    ["\226\128\131"] = true, ["\226\128\132"] = true, ["\226\128\133"] = true,
    ["\226\128\134"] = true, ["\226\128\135"] = true, ["\226\128\136"] = true,
    ["\226\128\137"] = true, ["\226\128\138"] = true,                         -- ..U+200A
    ["\226\128\168"] = true, ["\226\128\169"] = true, -- U+2028, U+2029
    ["\226\128\175"] = true,                     -- U+202F spazio stretto non separabile
    ["\226\129\159"] = true,                     -- U+205F
    ["\227\128\128"] = true,                     -- U+3000
}

-- Caratteri ignorati del tutto nel confronto: trattino morbido, spazi a larghezza zero.
local IGNORATI = {
    ["\194\173"] = true,     -- U+00AD trattino morbido
    ["\226\128\139"] = true, -- U+200B spazio a larghezza zero
    ["\226\129\160"] = true, -- U+2060 word joiner
    ["\239\187\191"] = true, -- U+FEFF
}

--[[--
Normalizza una sequenza di frammenti di testo del sorgente, conservando la mappa
carattere normalizzato → byte d'origine.

@param src  stringa sorgente (l'intero file XHTML)
@param frammenti  lista di { s = inizio, e = fine (inclusi), nodo = qualunque valore }
@return tabella con:
  testo  — stringa normalizzata (UTF-8, spazi compressi, entità risolte)
  cs, ce — per ogni carattere k: primo e ultimo byte nel sorgente
  nodo   — per ogni carattere k: il nodo di testo da cui proviene
  byte2car — per ogni byte iniziale di carattere nel testo normalizzato: indice k
  inizioNodo — per ogni nodo: indice del suo primo carattere normalizzato
]]
function M.normalizzaFrammenti(src, frammenti)
    local pezzi, cs, ce, nodi, byte2car, inizioNodo = {}, {}, {}, {}, {}, {}
    local k, pos = 0, 1          -- k = numero di caratteri emessi; pos = byte successivo nel testo
    local ultimoSpazio = true    -- comprime anche gli spazi a inizio blocco

    local function emetti(c, s, e, nodo)
        k = k + 1
        pezzi[k] = c
        cs[k], ce[k], nodi[k] = s, e, nodo
        byte2car[pos] = k
        pos = pos + #c
    end

    for _, f in ipairs(frammenti) do
        if inizioNodo[f.nodo] == nil then inizioNodo[f.nodo] = k + 1 end
        if f.spazio then
            -- frammento sintetico (per esempio <br/>): vale come uno spazio,
            -- mappato sui byte del tag
            if not ultimoSpazio then
                emetti(" ", f.s, f.e, f.nodo)
                ultimoSpazio = true
            end
        end
        local i, fine = f.s, f.spazio and f.s - 1 or f.e
        while i <= fine do
            local b = src:byte(i)
            local c, j
            if b == 38 then -- "&"
                c, j = decodificaEntita(src, i, fine)
            end
            if not c then
                j = i + lunghezzaUtf8(b) - 1
                c = src:sub(i, j)
            end
            if SPAZI[c] then
                if not ultimoSpazio then
                    emetti(" ", i, j, f.nodo)
                    ultimoSpazio = true
                else
                    -- spazio compresso: estende la fine dello spazio precedente,
                    -- così l'intervallo di byte copre l'intera sequenza
                    if k > 0 and pezzi[k] == " " and nodi[k] == f.nodo then ce[k] = j end
                end
            elseif not IGNORATI[c] then
                emetti(c, i, j, f.nodo)
                ultimoSpazio = false
            end
            i = j + 1
        end
    end
    return {
        testo = table.concat(pezzi),
        cs = cs, ce = ce, nodo = nodi,
        byte2car = byte2car,
        inizioNodo = inizioNodo,
        n = k,
    }
end

--- Normalizza un testo semplice (per esempio il testo di un'annotazione).
-- @param taglia se vero (predefinito) toglie gli spazi iniziali e finali
function M.normalizza(s, taglia)
    if not s then return "" end
    local r = M.normalizzaFrammenti(s, { { s = 1, e = #s, nodo = 1 } }).testo
    if taglia ~= false then
        r = r:gsub("^ +", ""):gsub(" +$", "")
    end
    return r
end

--- Trova tutte le occorrenze (non sovrapposte) di `ago` in `norm.testo`.
-- @return lista di { da = indice del primo carattere, a = indice dell'ultimo }
function M.trovaOccorrenze(norm, ago)
    local risultati = {}
    if ago == "" then return risultati end
    local init = 1
    while true do
        local s, e = norm.testo:find(ago, init, true)
        if not s then break end
        local da = norm.byte2car[s]
        -- e è l'ultimo byte del match: il carattere che lo contiene inizia
        -- al più 3 byte prima
        local a
        for d = 0, 3 do
            a = norm.byte2car[e - d]
            if a then break end
        end
        if da and a then
            table.insert(risultati, { da = da, a = a })
        end
        init = e + 1
    end
    return risultati
end

return M
