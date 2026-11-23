--[[--
Struttura di un EPUB: container.xml, OPF (manifest, spine, guide), nav e NCX.

Lavora su un "lettore" astratto:
  lettore.leggi(nome_nel_zip) → contenuto (stringa) oppure nil, errore
così da poter essere usato sul dispositivo (archiver/crengine) e nei test
(cartella sul disco o zip non compresso).

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local xmltok = require("parergon/xmltok")
local testo = require("parergon/testo")
local _ = require("parergon/i18n")

local M = {}

-- Versione DOM di crengine da cui ogni elemento dello spine produce un DocFragment
-- (crengine epubfmt.cpp: "relaxed_spine"). Prima contavano solo gli XHTML.
M.DOM_SPINE_RILASSATO = 20240114

-- ---------------------------------------------------------------------------
-- Percorsi
-- ---------------------------------------------------------------------------

--- Cartella di un percorso interno ("OEBPS/text/a.xhtml" → "OEBPS/text/").
function M.cartella(p)
    return p:match("^(.*/)") or ""
end

--- Decodifica i caratteri %XX di un URL.
function M.decodificaUrl(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

--- Risolve un href relativo rispetto alla cartella `base`, normalizzando "." e "..".
function M.risolvi(base, href)
    href = M.decodificaUrl(testo.decodificaEntita(href)):gsub("#.*$", ""):gsub("%?.*$", "")
    local parti = {}
    local completo = href:sub(1, 1) == "/" and href:sub(2) or (base .. href)
    for p in completo:gmatch("[^/]+") do
        if p == ".." then
            if #parti > 0 then parti[#parti] = nil end
        elseif p ~= "." then
            parti[#parti + 1] = p
        end
    end
    return table.concat(parti, "/")
end

--- Percorso relativo da un file `da` a un file `a` (entrambi interni all'archivio).
function M.relativo(da, a)
    local pd, pa = {}, {}
    for p in M.cartella(da):gmatch("[^/]+") do pd[#pd + 1] = p end
    for p in a:gmatch("[^/]+") do pa[#pa + 1] = p end
    local i = 1
    while i <= #pd and i < #pa and pd[i] == pa[i] do i = i + 1 end
    local r = {}
    for __ = i, #pd do r[#r + 1] = ".." end
    for k = i, #pa do r[#r + 1] = pa[k] end
    return table.concat(r, "/")
end

-- ---------------------------------------------------------------------------
-- OPF
-- ---------------------------------------------------------------------------

--[[--
Legge l'EPUB e ne restituisce la struttura.
@return {
  opf = percorso dell'OPF, opf_src = contenuto, opf_doc = albero,
  versione = "2.0"/"3.0"...,
  manifest = { {id, href, percorso, tipo, proprieta} }, perId = {}, perPercorso = {},
  spine = { {idref, lineare, voce} },  -- voce = elemento del manifest (nil se idref non esiste)
  ncx = voce del manifest o nil, nav = voce del manifest o nil,
  guide = { {tipo, href, percorso} },
}
oppure nil e messaggio
]]
function M.leggi(lettore)
    local cont, err = lettore.leggi("META-INF/container.xml")
    if not cont then return nil, _.trf("META-INF/container.xml is missing (%s)", tostring(err)) end
    local cdoc, cerr = xmltok.analizza(cont)
    if not cdoc then return nil, _.trf("container.xml cannot be read: %s", cerr) end
    local opf
    for __, rf in ipairs(xmltok.tutti(cdoc.radice, function(el) return el.nome == "rootfile" end)) do
        local a = xmltok.attr(rf)
        if not opf or a["media-type"] == "application/oebps-package+xml" then
            opf = a["full-path"]
        end
    end
    if not opf then return nil, _("container.xml does not point to the OPF file") end
    opf = M.risolvi("", opf)

    local src, oerr = lettore.leggi(opf)
    if not src then return nil, _.trf("OPF file missing: %s (%s)", opf, tostring(oerr)) end
    local doc, derr = xmltok.analizza(src)
    if not doc then return nil, _.trf("OPF file cannot be read: %s", derr) end

    local base = M.cartella(opf)
    local libro = {
        opf = opf, opf_src = src, opf_doc = doc, base = base,
        manifest = {}, perId = {}, perPercorso = {}, spine = {}, guide = {},
    }
    local pkg = xmltok.trova(doc.radice, "package")
    libro.versione = pkg and xmltok.attr(pkg).version or "2.0"

    local manifest = xmltok.trova(doc.radice, "manifest")
    if not manifest then return nil, _("the OPF file has no manifest") end
    for __, it in ipairs(manifest.figli) do
        if it.tipo == "el" and it.nome == "item" then
            local a = xmltok.attr(it)
            if a.id and a.href then
                local v = {
                    id = a.id, href = a.href, percorso = M.risolvi(base, a.href),
                    tipo = a["media-type"] or "", proprieta = a.properties or "", el = it,
                }
                libro.manifest[#libro.manifest + 1] = v
                if not libro.perId[v.id] then libro.perId[v.id] = v end -- come crengine: vale il primo
                libro.perPercorso[v.percorso] = v
                if (" " .. v.proprieta .. " "):find(" nav ", 1, true) then libro.nav = v end
            end
        end
    end

    local spine = xmltok.trova(doc.radice, "spine")
    if not spine then return nil, _("the OPF file has no spine") end
    libro.spine_el = spine
    local tocid = xmltok.attr(spine).toc
    if tocid then libro.ncx = libro.perId[tocid] end
    if not libro.ncx then
        for __, v in ipairs(libro.manifest) do
            if v.tipo == "application/x-dtbncx+xml" then libro.ncx = v break end
        end
    end
    for __, ir in ipairs(spine.figli) do
        if ir.tipo == "el" and ir.nome == "itemref" then
            local a = xmltok.attr(ir)
            libro.spine[#libro.spine + 1] = {
                idref = a.idref, lineare = (a.linear or ""):lower() ~= "no",
                voce = a.idref and libro.perId[a.idref], el = ir,
            }
        end
    end

    local guide = xmltok.trova(doc.radice, "guide")
    if guide then
        for __, r in ipairs(guide.figli) do
            if r.tipo == "el" and r.nome == "reference" then
                local a = xmltok.attr(r)
                if a.href then
                    libro.guide[#libro.guide + 1] = {
                        tipo = (a.type or ""):lower(), href = a.href,
                        percorso = M.risolvi(base, a.href), titolo = a.title,
                    }
                end
            end
        end
    end
    return libro
end

--[[--
Elenco dei DocFragment come li costruisce crengine, nell'ordine.
Riproduce epubfmt.cpp:
  - un itemref il cui idref non esiste nel manifest viene scartato (non conta);
  - con DOM >= 20240114 ogni altro itemref produce un DocFragment;
  - con DOM precedenti solo quelli con media-type application/xhtml+xml.
@param versione_dom  cre_dom_version del libro (nil = la più recente)
@return lista: frammenti[N] = voce del manifest
]]
function M.frammenti(libro, versione_dom)
    local rilassato = (versione_dom or math.huge) >= M.DOM_SPINE_RILASSATO
    local out = {}
    for __, s in ipairs(libro.spine) do
        if s.voce then
            if rilassato or s.voce.tipo == "application/xhtml+xml" then
                out[#out + 1] = s.voce
            end
        end
    end
    return out
end

return M
