--[[--
Forme e colori delle evidenziazioni permanenti, e foglio di stile parergon.css.

Forme (codici interni, usati anche nelle impostazioni):
  "highlight" — evidenziazione con sfondo
  "solid"     — sottolineatura continua
  "dashed"    — sottolineatura tratteggiata
  "wavy"      — sottolineatura a zigzag (puntinata in KOReader: crengine non sa
                disegnare linee ondulate)

Due livelli di regole, separati da "-cr-only-if: never" (estensione di crengine:
le dichiarazioni che seguono vengono ignorate da KOReader, mentre i motori web
ignorano la proprietà sconosciuta e le applicano):
  1. base, per crengine e motori semplici: border-bottom (solid/dashed/dotted) e
     sfondi opachi calibrati per restare visibili in bianco e nero;
  2. motori web (Readest, Apple Books, Calibre...): text-decoration con stile
     e sfondi semitrasparenti, leggibili anche con i temi scuri.

Colori: quelli di KOReader (readerhighlight.lua, BlitBuffer.HIGHLIGHT_COLORS).
In bianco e nero KOReader disegna ogni evidenziazione come un grigio al 20%
(readerview.lua, darkenRect con lighten_factor 0.2): calcoliamo per ogni colore
uno sfondo la cui luminanza in scala di grigi (Rec. 601, la conversione degli
schermi e-ink) sia la stessa, così l'evidenziazione resta visibile.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local M = {}

M.FORME = { "highlight", "solid", "dashed", "wavy" }

-- Stile del bordo usato da crengine per ciascuna sottolineatura (lo zigzag diventa puntinato).
local BORDO = { solid = "solid", dashed = "dashed", wavy = "dotted" }
M.CSS_BORDO = BORDO

-- Colori di KOReader (BlitBuffer.HIGHLIGHT_COLORS), più il grigio.
M.COLORI = {
    red = "#FF3300", orange = "#FF8800", yellow = "#FFFF33", green = "#00AA66",
    olive = "#88FF77", cyan = "#00FFEE", blue = "#0066FF", purple = "#EE00FF",
    gray = "#808080",
}
M.ORDINE_COLORI = { "red", "orange", "yellow", "green", "olive", "cyan", "blue", "purple", "gray" }

-- Luminanza in scala di grigi a cui portare gli sfondi (0.8 = grigio al 20% di KOReader).
M.LUMA_SFONDO = 0.80
-- Luminanza massima delle linee: abbastanza scure da vedersi su e-ink.
M.LUMA_LINEA = 0.45
-- Opacità degli sfondi per i motori web.
M.ALFA_WEB = 0.35

-- Forma predefinita per ciascuno stile di KOReader.
-- "strikeout" corrisponde anche all'ondulata di Readest (readest_syncannotations.lua).
M.DA_KOREADER = {
    lighten = "highlight", invert = "highlight", underscore = "solid", strikeout = "wavy",
}

-- ---------------------------------------------------------------------------
-- Colori
-- ---------------------------------------------------------------------------

local function rgb(hex)
    return tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255
end

local function hex(r, g, b)
    local function c(x) return math.max(0, math.min(255, math.floor(x * 255 + 0.5))) end
    return string.format("#%02X%02X%02X", c(r), c(g), c(b))
end

--- Luminanza Rec. 601 (0..1).
function M.luma(hexcolore)
    local r, g, b = rgb(hexcolore)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

--- Sfondo opaco con la stessa tinta e luminanza `obiettivo`.
function M.sfondo(hexcolore, obiettivo)
    obiettivo = obiettivo or M.LUMA_SFONDO
    local r, g, b = rgb(hexcolore)
    local l = 0.299 * r + 0.587 * g + 0.114 * b
    if l <= obiettivo then
        -- schiarisce verso il bianco: L(mix) = 1 - t (1 - L)
        local t = (1 - obiettivo) / (1 - l)
        return hex(1 + t * (r - 1), 1 + t * (g - 1), 1 + t * (b - 1))
    end
    -- colore troppo chiaro (giallo, verde oliva): lo scurisce verso il nero
    local k = obiettivo / l
    return hex(r * k, g * k, b * k)
end

--- Colore delle linee: la stessa tinta, scurita se necessario.
function M.linea(hexcolore)
    local l = M.luma(hexcolore)
    if l <= M.LUMA_LINEA then return hexcolore:upper() end
    local r, g, b = rgb(hexcolore)
    local k = M.LUMA_LINEA / l
    return hex(r * k, g * k, b * k)
end

--- Colore con trasparenza per i motori web: rgba(r, g, b, a).
function M.rgba(hexcolore, alfa)
    local r, g, b = rgb(hexcolore)
    return string.format("rgba(%d, %d, %d, %.2f)", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), alfa)
end

--- Nome di colore normalizzato: uno di M.COLORI, oppure "gray" se sconosciuto.
function M.nomeColore(colore)
    if type(colore) ~= "string" then return "yellow" end -- predefinito di KOReader
    colore = colore:lower()
    if M.COLORI[colore] then return colore end
    return "gray" -- colori personalizzati non riconosciuti: grigio neutro
end

-- ---------------------------------------------------------------------------
-- Scelta della forma
-- ---------------------------------------------------------------------------

--[[--
Forma e colore di un'annotazione secondo le impostazioni.
@param ann annotazione di KOReader (drawer, color)
@param imp { forma = "koreader" | codice, per_colore = { [nome] = codice }, colori = "keep" | "gray" }
@return forma, nome colore (o "mono" per il grigio uniforme)
Precedenza: forma scelta per la singola annotazione (campo `parergon_forma`)
→ mappatura per colore → forma generale → stile salvato da KOReader.
]]
function M.risolvi(ann, imp)
    imp = imp or {}
    local colore = M.nomeColore(ann.color)
    local forma = ann.parergon_forma
    if forma and not M.CSS_BORDO[forma] and forma ~= "highlight" then forma = nil end
    forma = forma or (imp.per_colore and imp.per_colore[colore])
    if not forma and imp.forma and imp.forma ~= "koreader" then forma = imp.forma end
    if not forma then forma = M.DA_KOREADER[ann.drawer] or "highlight" end
    if imp.colori == "gray" then colore = "mono" end
    return forma, colore
end

--- Classe CSS di una combinazione forma/colore.
function M.classe(forma, colore)
    local prefisso = forma == "highlight" and "parergon-hl" or ("parergon-ul-" .. forma)
    return prefisso .. "-" .. colore
end

-- ---------------------------------------------------------------------------
-- Foglio di stile
-- ---------------------------------------------------------------------------


-- Note del lettore: corsivo, corpo ridotto, colore distinto dal testo.
-- Base (crengine, e-ink): blu scuro, luminanza bassa per un buon contrasto in grigio.
-- Web: blu intermedio, leggibile sia sul tema chiaro sia su quello scuro.
M.COLORE_NOTA = "#2E4A7D"
M.COLORE_NOTA_WEB = "#5577AA"

--[[--
Genera parergon.css per le combinazioni usate.
@param usate lista di { forma, colore } (senza duplicati)
@param extra {
  note        = true se ci sono note nel testo,
  corsivo     = false per le note nel testo in tondo (predefinito: corsivo),
  richiami    = true se ci sono richiami [n] di note a comparsa,
  richiamo    = "linea" (predefinito) | "apice",
  pagina_note = true se c'è la pagina «Note del lettore»
}
]]
function M.css(usate, extra)
    extra = extra or {}
    local base, web = {}, {}
    if extra.note then
        -- la nota non eredita grassetto, sottolineature o rientri dal contesto
        base[#base + 1] = ".parergon-note { font-style: " .. (extra.corsivo == false and "normal" or "italic")
            .. "; font-weight: normal; font-size: 0.9em; "
            .. "color: " .. M.COLORE_NOTA .. "; text-decoration: none; vertical-align: baseline; }"
        web[#web + 1] = ".parergon-note { -cr-only-if: never; color: " .. M.COLORE_NOTA_WEB .. "; }"
    end
    if extra.richiami then
        -- Richiamo [n]: più grande di un esponente normale (circa 0,6 em) e con un
        -- po' di margine, per essere facile da toccare su un e-reader.
        -- predefinito: sulla riga (scelta verificata sul Kindle il 22/11/2026)
        local posizione = extra.richiamo == "apice"
            and "font-size: 0.8em; vertical-align: super; line-height: 1;"
            or "font-size: 0.9em; vertical-align: baseline;"
        base[#base + 1] = ".parergon-noteref { " .. posizione .. " font-style: normal; font-weight: bold; "
            .. "color: " .. M.COLORE_NOTA .. "; text-decoration: none; padding: 0 0.15em; }"
        web[#web + 1] = ".parergon-noteref { -cr-only-if: never; color: " .. M.COLORE_NOTA_WEB .. "; }"
    end
    if extra.indice then
        -- pagina dell'indice personale: leggibile come un capitolo
        base[#base + 1] = ".parergon-index { margin: 0 1.5em; font-size: 1em; line-height: 1.45; }"
        base[#base + 1] = ".parergon-index-title { text-align: center; margin: 1em 0 1.2em 0; }"
        base[#base + 1] = ".parergon-index-group { margin: 1.2em 0 0.5em 0; page-break-after: avoid; }"
        base[#base + 1] = ".parergon-index-count { font-weight: normal; font-size: 0.8em; }"
        base[#base + 1] = ".parergon-index-entry { margin: 0 0 0.9em 0; }"
        base[#base + 1] = ".parergon-index-entry p { text-indent: 0; margin: 0; font-size: 1em; }"
        base[#base + 1] = ".parergon-index-head a { font-weight: bold; text-decoration: none; color: inherit; }"
        base[#base + 1] = ".parergon-index-entry p.parergon-index-passage { font-style: italic; font-size: 0.95em; }"
        base[#base + 1] = ".parergon-index-entry p.parergon-index-note { color: " .. M.COLORE_NOTA .. "; font-size: 0.95em; }"
        web[#web + 1] = ".parergon-index-entry p.parergon-index-note { -cr-only-if: never; color: " .. M.COLORE_NOTA_WEB .. "; }"
    end
    if extra.lettore then
        base[#base + 1] = ".parergon-reader { text-align: center; text-indent: 0; font-style: italic; margin: 2em 0 0 0; }"
        base[#base + 1] = ".parergon-reader-page { margin-top: 35%; }"
    end
    if extra.pagina_note then
        -- Pagina pensata per essere letta: corpo pieno, margini come un capitolo
        -- (la pagina non riceve il CSS del libro), voci ben separate.
        base[#base + 1] = ".parergon-notes { margin: 0 1.5em; font-size: 1em; line-height: 1.45; }"
        base[#base + 1] = ".parergon-notes-title { text-align: center; margin: 1em 0 1.2em 0; }"
        base[#base + 1] = ".parergon-endnote { margin: 0 0 1em 0; font-size: 1em; }"
        base[#base + 1] = ".parergon-endnote p { text-indent: 0; margin: 0; font-size: 1em; }"
        base[#base + 1] = ".parergon-backlink { font-weight: bold; color: " .. M.COLORE_NOTA
            .. "; text-decoration: none; padding: 0 0.2em 0 0; }"
        base[#base + 1] = ".parergon-endnote p.parergon-endnote-passage { font-style: italic; font-size: 0.95em; margin-top: 0.2em; }"
        web[#web + 1] = ".parergon-backlink { -cr-only-if: never; color: " .. M.COLORE_NOTA_WEB .. "; }"
    end
    for _, u in ipairs(usate) do
        local forma, colore = u[1], u[2]
        local sel = "." .. M.classe(forma, colore)
        local mono = colore == "mono"
        local col = M.COLORI[colore]
        if forma == "highlight" then
            local opaco = mono and "#CCCCCC" or M.sfondo(col)
            local trasp = mono and "rgba(0, 0, 0, 0.20)" or M.rgba(col, M.ALFA_WEB)
            base[#base + 1] = string.format("%s { background-color: %s; }", sel, opaco)
            web[#web + 1] = string.format("%s { -cr-only-if: never; background-color: %s; }", sel, trasp)
        else
            local linea = mono and "currentColor" or M.linea(col)
            local spessore = forma == "wavy" and "0.12em" or "0.08em"
            base[#base + 1] = string.format("%s { border-bottom: %s %s %s; }", sel, spessore, BORDO[forma], linea)
            web[#web + 1] = string.format(
                "%s { -cr-only-if: never; border-bottom: none; text-decoration: underline; "
                .. "text-decoration: underline %s %s; text-decoration-thickness: 0.08em; "
                .. "text-underline-offset: 0.18em; text-decoration-skip-ink: none; }",
                sel, forma, linea)
        end
    end
    return table.concat({
        "/* Parergon — evidenziazioni permanenti delle annotazioni del lettore.",
        "   Livello 1: KOReader (crengine) e motori semplici.",
        "   Livello 2: motori web; crengine lo ignora grazie a \"-cr-only-if: never\". */",
        "",
        table.concat(base, "\n"),
        "",
        table.concat(web, "\n"),
        "",
    }, "\n")
end

return M
