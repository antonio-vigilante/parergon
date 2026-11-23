--[[--
Nota di lettura nel frontespizio ("Letto e annotato da … nel novembre 2026").

Ricerca del frontespizio, solo da indicazioni esplicite del libro:
  1. nav.xhtml, landmarks: epub:type="titlepage";
  2. OPF, guide: type="title-page" (o "titlepage").
Il file deve essere nello spine. Se il frontespizio non si trova con certezza,
si crea una piccola pagina dedicata subito dopo la copertina (landmark "cover"
o guide type="cover"), oppure all'inizio del libro: non si toccano pagine incerte.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local epub = require("parergon/epub")
local testo = require("parergon/testo")
local toc = require("parergon/toc")
local xmltok = require("parergon/xmltok")

local M = {}

--- Itemref dello spine che punta al file `percorso`.
local function itemrefDi(libro, percorso)
    for __, s in ipairs(libro.spine) do
        if s.voce and s.voce.percorso == percorso then return s end
    end
end

--- Percorso indicato da landmark (nav) o guide (OPF) per uno dei tipi dati.
local function indicato(libro, lettore, tipo_nav, tipi_guide)
    if libro.nav then
        local p = toc.landmark(lettore.leggi(libro.nav.percorso), libro.nav.percorso, tipo_nav, epub.risolvi)
        if p then return p end
    end
    for __, g in ipairs(libro.guide) do
        for __, t in ipairs(tipi_guide) do
            if g.tipo == t then return g.percorso end
        end
    end
end

--[[--
@return {
  frontespizio = percorso del file (se trovato con certezza e nello spine) oppure nil,
  copertina    = itemref della copertina (se trovata) oppure nil,
}
]]
function M.trova(libro, lettore)
    local r = {}
    local f = indicato(libro, lettore, "titlepage", { "title-page", "titlepage" })
    if f and itemrefDi(libro, f) and (libro.perPercorso[f] or {}).tipo == "application/xhtml+xml" then
        r.frontespizio = f
    end
    local c = indicato(libro, lettore, "cover", { "cover" })
    local ir = c and itemrefDi(libro, c)
    if ir then r.copertina = ir.el end
    return r
end

--- Paragrafo della nota di lettura.
function M.paragrafo(frase)
    return '<p class="parergon-reader">' .. testo.escapeXml(frase) .. "</p>"
end

--- Inserimento del paragrafo prima di </body> nel frontespizio.
function M.inserimento(src, frase)
    local doc = xmltok.analizza(src)
    local body = doc and xmltok.trova(doc.radice, "body")
    if not body or body.vuoto or not body.tok_chiude then return nil end
    local pos = body.ie + 1
    local riga_propria = src:sub(1, pos - 1):match("\n([ \t]*)$")
    if riga_propria then
        return { pos = pos - #riga_propria, testo = riga_propria .. "  " .. M.paragrafo(frase) .. "\n", peso = 2, ordine = 0 }
    end
    return { pos = pos, testo = M.paragrafo(frase), peso = 2, ordine = 0 }
end

--- Pagina dedicata, quando il frontespizio non si trova con certezza.
function M.pagina(frase, p)
    local righe = testo.inizioPagina{ titolo = p.titolo, css = p.css, lingua = p.lingua, epub2 = p.epub2 }
    for __, r in ipairs({
        '  <div class="parergon-reader-page">',
        "    " .. M.paragrafo(frase),
        "  </div>",
        "</body>",
        "</html>",
        "",
    }) do righe[#righe + 1] = r end
    return table.concat(righe, "\n")
end

return M
