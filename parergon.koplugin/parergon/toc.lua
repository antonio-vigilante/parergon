--[[--
Rami aggiunti alla TOC del libro: nav.xhtml (EPUB 3) e toc.ncx (EPUB 2).

Si aggiunge sempre in FONDO, come ramo separato, senza toccare le voci
dell'autore. Si aggiornano entrambi i file quando esistono, perché alcune
applicazioni leggono solo l'uno o l'altro.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local xmltok = require("parergon/xmltok")
local testo = require("parergon/testo")

local M = {}

local function rientroDi(src, pos)
    local inizio = src:sub(1, pos - 1):match(".*\n()") or 1
    return src:sub(inizio, pos - 1):match("^([ \t]*)") or ""
end

--- Elemento <nav> con epub:type="toc".
local function navToc(doc)
    for __, n in ipairs(xmltok.tutti(doc.radice, function(e) return e.nome == "nav" end)) do
        local t = xmltok.attr(n).type or ""
        if (" " .. t .. " "):find(" toc ", 1, true) then return n end
    end
end

--[[--
Inserimento in nav.xhtml: nuove voci <li> in fondo all'<ol> principale del nav "toc".
@param src contenuto di nav.xhtml
@param voci { {titolo, href, figli = { ... } } } (figli a qualsiasi profondità)
@return inserimento, oppure nil se il nav non ha la struttura attesa
]]
function M.nav(src, voci)
    local doc = xmltok.analizza(src)
    if not doc then return nil end
    local nav = navToc(doc)
    if not nav then return nil end
    local ol
    for __, f in ipairs(nav.figli) do if f.tipo == "el" and f.nome == "ol" then ol = f break end end
    if not ol or ol.vuoto then return nil end
    local ultimo
    for __, f in ipairs(ol.figli) do if f.tipo == "el" and f.nome == "li" then ultimo = f end end
    local r = ultimo and rientroDi(src, ultimo.s) or "  "
    local prefisso = ol.qnome:match("^(.-:)") or ""
    local function tag(nome) return prefisso .. nome end
    local righe = {}
    local function voce(v, rientro)
        local a = "<" .. tag("a") .. ' href="' .. testo.escapeXml(v.href) .. '">' .. testo.escapeXml(v.titolo) .. "</" .. tag("a") .. ">"
        if v.figli and #v.figli > 0 then
            righe[#righe + 1] = rientro .. "<" .. tag("li") .. ">" .. a
            righe[#righe + 1] = rientro .. "  <" .. tag("ol") .. ">"
            for __, f in ipairs(v.figli) do voce(f, rientro .. "    ") end
            righe[#righe + 1] = rientro .. "  </" .. tag("ol") .. ">"
            righe[#righe + 1] = rientro .. "</" .. tag("li") .. ">"
        else
            righe[#righe + 1] = rientro .. "<" .. tag("li") .. ">" .. a .. "</" .. tag("li") .. ">"
        end
    end
    for __, v in ipairs(voci) do voce(v, r) end
    local pos = ol.ie + 1
    local riga_propria = src:sub(1, pos - 1):match("\n([ \t]*)$")
    if riga_propria then
        return { pos = pos - #riga_propria, testo = table.concat(righe, "\n") .. "\n", peso = 2, ordine = 0 }
    end
    for k, x in ipairs(righe) do righe[k] = x:gsub("^[ \t]+", "") end
    return { pos = pos, testo = table.concat(righe, ""), peso = 2, ordine = 0 }
end

--[[--
Inserimenti in toc.ncx: nuovi <navPoint> in fondo a <navMap>, con playOrder
successivi al massimo esistente e id univoci; dtb:depth portato almeno a 2.
@return lista di inserimenti, oppure nil se manca navMap
]]
function M.ncx(src, voci)
    local doc = xmltok.analizza(src)
    if not doc then return nil end
    local navmap = xmltok.trova(doc.radice, "navmap")
    if not navmap or navmap.vuoto then return nil end
    local max = 0
    for v in src:gmatch('playOrder%s*=%s*["\'](%d+)["\']') do
        if tonumber(v) > max then max = tonumber(v) end
    end
    local usati = {}
    for v in src:gmatch('id%s*=%s*["\']([^"\']+)["\']') do usati[v] = true end
    local n = 0
    local function nuovoId()
        repeat n = n + 1 until not usati["parergon-np-" .. n]
        return "parergon-np-" .. n
    end
    local ultimo
    for __, f in ipairs(navmap.figli) do if f.tipo == "el" and f.nome == "navpoint" then ultimo = f end end
    local r = ultimo and rientroDi(src, ultimo.s) or "    "
    local prefisso = navmap.qnome:match("^(.-:)") or ""
    local function punto(v, rientro, figli)
        max = max + 1
        local s = rientro .. "<" .. prefisso .. 'navPoint id="' .. nuovoId() .. '" playOrder="' .. max .. '">'
            .. "<" .. prefisso .. "navLabel><" .. prefisso .. "text>" .. testo.escapeXml(v.titolo) .. "</"
            .. prefisso .. "text></" .. prefisso .. "navLabel><" .. prefisso .. 'content src="' .. testo.escapeXml(v.href) .. '"/>'
        if figli and #figli > 0 then
            local dentro = {}
            for __, f in ipairs(figli) do dentro[#dentro + 1] = punto(f, rientro .. "  ", f.figli) end
            return s .. "\n" .. table.concat(dentro, "\n") .. "\n" .. rientro .. "</" .. prefisso .. "navPoint>"
        end
        return s .. "</" .. prefisso .. "navPoint>"
    end
    local righe = {}
    for __, v in ipairs(voci) do righe[#righe + 1] = punto(v, r, v.figli) end
    local ins = {}
    local pos = navmap.ie + 1
    local riga_propria = src:sub(1, pos - 1):match("\n([ \t]*)$")
    if riga_propria then
        ins[#ins + 1] = { pos = pos - #riga_propria, testo = table.concat(righe, "\n") .. "\n", peso = 2, ordine = 0 }
    else
        ins[#ins + 1] = { pos = pos, testo = table.concat(righe, ""), peso = 2, ordine = 0 }
    end
    -- dtb:depth: almeno la profondità del nuovo ramo (2, oppure 3 con i sotto-temi)
    local function profondita(lista)
        local massimo = 0
        for __, v in ipairs(lista) do
            local d = 1 + profondita(v.figli or {})
            if d > massimo then massimo = d end
        end
        return massimo
    end
    local serve = profondita(voci)
    for __, m in ipairs(xmltok.tutti(doc.radice, function(e) return e.nome == "meta" end)) do
        local a = xmltok.attr(m)
        if a.name == "dtb:depth" and (tonumber(a.content) or 0) < serve then
            local tagtxt = src:sub(m.s, m.is - 1)
            local x, y = tagtxt:find('content%s*=%s*["\'][^"\']*["\']')
            if x then
                ins[#ins + 1] = { pos = m.s + x - 1, fino = m.s + y - 1, testo = 'content="' .. serve .. '"', peso = 2, ordine = 0 }
            end
        end
    end
    return ins
end

--[[--
Landmark del nav (epub:type) → percorso del file, per esempio "titlepage", "cover".
@param nav_src contenuto di nav.xhtml
@param nav_percorso percorso interno di nav.xhtml (per risolvere gli href)
@param risolvi function(base, href) → percorso
]]
function M.landmark(nav_src, nav_percorso, tipo, risolvi)
    local doc = nav_src and xmltok.analizza(nav_src)
    if not doc then return nil end
    for __, n in ipairs(xmltok.tutti(doc.radice, function(e) return e.nome == "nav" end)) do
        local t = xmltok.attr(n).type or ""
        if (" " .. t .. " "):find(" landmarks ", 1, true) then
            for __, a in ipairs(xmltok.tutti(n, function(e) return e.nome == "a" end)) do
                local at = xmltok.attr(a)
                if at.href and (" " .. (at.type or "") .. " "):find(" " .. tipo .. " ", 1, true) then
                    return risolvi(nav_percorso:match("^(.*/)") or "", at.href)
                end
            end
        end
    end
end

return M
