--[[--
Note del lettore: pulizia, titolo per l'indice e testo da inserire nel libro.

Convenzione (docs/03-decisioni.md):
  # Titolo della voce dell'indice
  resto della nota, che va nel testo tra parentesi quadre

Se la prima riga non vuota inizia con "#", quella riga (senza "#") è il titolo
per l'indice personale e NON va nel testo. Il resto della nota, se c'è, va nel testo.

Formati delle note di KOReader (campo note_format): nil = testo semplice,
"html" oppure "md". Per html e md si conserva solo il testo.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local testo = require("parergon/testo")

local M = {}

--- Toglie spazi iniziali e finali (anche a capo).
local function taglia(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Testo semplice da una nota HTML: gli a capo dei blocchi restano a capo.
function M.daHtml(s)
    s = s:gsub("\r", "")
    s = s:gsub("<[Bb][Rr]%s*/?>", "\n")
    s = s:gsub("</[Pp]%s*>", "\n"):gsub("</[Dd][Ii][Vv]%s*>", "\n"):gsub("</[Ll][Ii]%s*>", "\n")
    s = s:gsub("</?[Hh]%d%s*>", "\n")
    s = s:gsub("<!%-%-.-%-%->", "")
    s = s:gsub("<[^>]*>", "")
    return testo.decodificaEntita(s)
end

--- Testo semplice da una nota Markdown: si tolgono i segni di formattazione più comuni.
function M.daMarkdown(s)
    local righe = {}
    for riga in (s:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
        riga = riga:gsub("^%s*>%s?", "")             -- citazioni
        riga = riga:gsub("^%s*[-*+]%s+", "• ")        -- elenchi puntati
        riga = riga:gsub("!%[([^%]]*)%]%b()", "%1")   -- immagini
        riga = riga:gsub("%[([^%]]*)%]%b()", "%1")    -- link
        riga = riga:gsub("%*%*(.-)%*%*", "%1"):gsub("__(.-)__", "%1")
        riga = riga:gsub("%*(.-)%*", "%1"):gsub("`(.-)`", "%1")
        righe[#righe + 1] = riga
    end
    return table.concat(righe, "\n")
end

-- Tema: "#" seguito da caratteri che non sono spazi (#liberta, #viaggi/mare).
-- È lo stesso criterio della patch utente "Indice tematico" (2-indice-tematico.lua,
-- TAG_PATTERN), così i temi creati con la patch vengono riconosciuti.
M.TEMA = "#([^%s#]+)"

--- Divide "digitale," in "digitale" e ",": la punteggiatura finale non è del tema.
function M.separaPunteggiatura(grezzo)
    local coda = ""
    while true do
        local c = grezzo:match("[%.,;:!%?%)%]\"']$")
        if grezzo:sub(-1) == "*" then
            -- asterisco finale: refuso (visto su un libro reale, "#logica-della-carenza*").
            -- Non è del tema e non resta nel testo.
            grezzo = grezzo:sub(1, -2)
        elseif c then
            coda = c .. coda
            grezzo = grezzo:sub(1, -2)
        elseif grezzo:sub(-2) == "»" then
            coda = "»" .. coda
            grezzo = grezzo:sub(1, -3)
        else
            break
        end
    end
    return grezzo, coda
end

--[[--
Analizza la nota di un'annotazione.

Due usi di "#", distinti come in Markdown:
  #tema      (attaccato)   — tema dell'indice tematico; non va mai nel testo del libro
  # Titolo   (con spazio)  — titolo della voce dell'indice personale; non va nel testo

@return { titolo = testo o nil, temi = { "tema", ... }, corpo = testo (eventualmente ""),
          vuota = bool }
]]
function M.analizza(ann)
    local n = ann.note
    if type(n) ~= "string" then return { corpo = "", temi = {}, vuota = true } end
    if ann.note_format == "html" then n = M.daHtml(n)
    elseif ann.note_format == "md" then n = M.daMarkdown(n) end
    n = n:gsub("\r", "")
    -- temi: raccolti senza doppioni, nell'ordine in cui compaiono, e tolti dal testo.
    -- La punteggiatura finale ("#digitale," a fine inciso) non fa parte del nome
    -- e resta nel testo.
    local temi, visti = {}, {}
    n = n:gsub("[ \t]*#([^%s#]+)", function(grezzo)
        local nome, coda = M.separaPunteggiatura(grezzo)
        if nome ~= "" and not visti[nome] then visti[nome] = true temi[#temi + 1] = nome end
        if nome == "" then return nil end -- "#" seguito da sola punteggiatura: lascia com'è
        return coda
    end)
    -- righe rimaste vuote dopo aver tolto i temi
    local righe = {}
    for riga in (n .. "\n"):gmatch("(.-)\n") do
        righe[#righe + 1] = taglia(riga)
    end
    n = taglia(table.concat(righe, "\n"):gsub("\n\n\n+", "\n\n"))
    local titolo
    local prima, resto = n:match("^([^\n]*)\n?(.*)$")
    if prima and prima:match("^#+%s") then
        titolo = taglia(prima:gsub("^#+", ""))
        if titolo == "" then titolo = nil end
        n = taglia(resto)
    elseif prima and prima:match("^#+$") then
        n = taglia(resto) -- "#" isolato: niente titolo
    end
    local vuota = n == "" and not titolo and #temi == 0
    return { titolo = titolo, temi = temi, corpo = n, vuota = vuota }
end

--[[--
XHTML del corpo della nota.
Gli a capo diventano <br/>; più righe vuote di seguito valgono un solo a capo.
@param corpo testo della nota
@param senza_parentesi true per non racchiuderla fra parentesi quadre (pagina delle note)
@return stringa XHTML, oppure nil se il corpo è vuoto
]]
function M.xhtml(corpo, senza_parentesi)
    if not corpo or corpo == "" then return nil end
    local righe = {}
    for riga in (corpo .. "\n"):gmatch("(.-)\n") do
        riga = taglia(riga)
        if riga ~= "" then righe[#righe + 1] = testo.escapeXml(riga) end
    end
    if #righe == 0 then return nil end
    local x = table.concat(righe, "<br/>")
    if senza_parentesi then return x end
    return "[" .. x .. "]"
end

--[[--
Pagina XHTML «Note del lettore» per le note a comparsa.

Ogni voce ha l'id a cui punta il richiamo nel testo e, come primo elemento,
il numero [n] che è anche il link di ritorno al passo (role="doc-backlink").

Le singole voci NON portano epub:type="endnote" / role="doc-endnote": lo stile
facoltativo di KOReader "In-page EPUB footnotes" (css_tweaks.lua) rimpicciolisce
e azzera i margini di quegli elementi, rendendo la pagina poco leggibile. La
finestrella di KOReader non ne ha bisogno: si basa sul richiamo nel testo
(epub:type="noteref"). La sezione resta marcata come "endnotes".

In EPUB 2 (XHTML 1.1) la sezione è un <div> e non porta epub:type né role, che non
esistono in quella versione.

@param p { titolo, lingua, css (href relativo), epub2 = bool,
           voci = { {numero, id, ritorno, corpo, passo, capitolo} } }
]]
function M.pagina(p)
    local righe = testo.inizioPagina{ titolo = p.titolo, css = p.css, lingua = p.lingua,
        epub2 = p.epub2, ns_epub = true }
    local sezione = p.epub2 and "div" or "section"
    righe[#righe + 1] = p.epub2 and '  <div class="parergon-notes">'
        or '  <section class="parergon-notes" epub:type="endnotes" role="doc-endnotes">'
    righe[#righe + 1] = '    <h1 class="parergon-notes-title">' .. testo.escapeXml(p.titolo) .. "</h1>"
    for __, v in ipairs(p.voci) do
        righe[#righe + 1] = '    <div class="parergon-endnote" id="' .. v.id .. '">'
        righe[#righe + 1] = '      <p><a class="parergon-backlink" href="' .. testo.escapeXml(v.ritorno)
            .. '"' .. (p.epub2 and "" or ' role="doc-backlink"') .. '>[' .. v.numero .. "]</a> " .. v.corpo .. "</p>"
        if v.passo and v.passo ~= "" then
            local riga = "«" .. testo.escapeXml(v.passo) .. "»"
            if v.capitolo and v.capitolo ~= "" then riga = riga .. " — " .. testo.escapeXml(v.capitolo) end
            righe[#righe + 1] = '      <p class="parergon-endnote-passage">' .. riga .. "</p>"
        end
        righe[#righe + 1] = "    </div>"
    end
    righe[#righe + 1] = "  </" .. sezione .. ">"
    righe[#righe + 1] = "</body>"
    righe[#righe + 1] = "</html>"
    righe[#righe + 1] = ""
    return table.concat(righe, "\n")
end

return M
