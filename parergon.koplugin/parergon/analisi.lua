--[[--
Analisi delle annotazioni di un libro: per ciascuna, file dello spine e punto
dell'XHTML corrispondente. Non modifica nulla.

Modulo in Lua puro: riceve dall'esterno il lettore dell'EPUB, le annotazioni,
la versione DOM e (facoltativa) una funzione che chiede a crengine il testo che
precede la sottolineatura. Così la stessa logica gira sul dispositivo e nei test.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local corrisp = require("parergon/corrisp")
local epub = require("parergon/epub")
local testo = require("parergon/testo")
local xmltok = require("parergon/xmltok")
local xpointer = require("parergon/xpointer")
local _ = require("parergon/i18n")

local M = {}

--- Le annotazioni utilizzabili: sottolineature (hanno `drawer`) con indirizzi testuali.
function M.sottolineature(annotazioni)
    local out = {}
    for i, a in ipairs(annotazioni) do
        if a.drawer and type(a.pos0) == "string" and type(a.pos1) == "string" then
            out[#out + 1] = { indice = i, ann = a }
        end
    end
    return out
end

--[[--
@param p tabella:
  lettore      — { leggi = function(nome) }
  annotazioni  — lista delle annotazioni di KOReader
  versione_dom — cre_dom_version del libro (nil = recente)
  prefisso     — function(xp_analizzato, ann) → testo prima di pos0, oppure nil
@return {
  libro, frammenti,
  esiti = { { ann, indice, voce (file), esito (vedi corrisp.trova) } },
  trovate, saltate
} oppure nil e messaggio
]]
function M.analizza(p)
    local libro, err = epub.leggi(p.lettore)
    if not libro then return nil, err end
    local frammenti = epub.frammenti(libro, p.versione_dom)

    local cache = {}
    local function documento(voce)
        if cache[voce.percorso] == nil then
            local src = p.lettore.leggi(voce.percorso)
            cache[voce.percorso] = (src and xmltok.analizza(src)) or false
        end
        return cache[voce.percorso] or nil
    end

    local esiti, trovate, saltate = {}, 0, 0
    for __, el in ipairs(M.sottolineature(p.annotazioni)) do
        local a = el.ann
        local x0 = xpointer.analizza(a.pos0)
        local voce = x0 and frammenti[x0.frammento]
        local esito
        if not x0 then
            esito = { ok = false, codice = "indirizzo", motivo = _("invalid position") }
        elseif not voce then
            esito = { ok = false, codice = "spine", motivo = _.trf("DocFragment[%d] does not match any file in the spine", x0.frammento) }
        else
            local d = documento(voce)
            if not d then
                esito = { ok = false, codice = "file", motivo = _.trf("file %s cannot be read or parsed", voce.percorso) }
            else
                local pref = p.prefisso and p.prefisso(x0, a) or nil
                esito = corrisp.trova(d, a, { prefisso = pref })
            end
        end
        if esito.ok then trovate = trovate + 1 else saltate = saltate + 1 end
        esiti[#esiti + 1] = { ann = a, indice = el.indice, voce = voce, esito = esito }
    end
    return { libro = libro, frammenti = frammenti, esiti = esiti, trovate = trovate, saltate = saltate }
end

--- Rapporto testuale dell'analisi, adatto a un TextViewer.
function M.rapporto(ris, versione_dom)
    local righe = {}
    local function r(s) righe[#righe + 1] = s end
    r(_.trf("Highlights analyzed: %d", #ris.esiti))
    r(_.trf("Certain matches: %d", ris.trovate))
    r(_.trf("Skipped: %d", ris.saltate))
    r(_.trf("Book DOM version: %s · files in spine: %d · OPF: %s",
        tostring(versione_dom or "?"), #ris.frammenti, ris.libro.opf))
    r("")
    for n, e in ipairs(ris.esiti) do
        local a, esito = e.ann, e.esito
        r(string.format("── %d. %s%s", n,
            a.chapter and ("«" .. a.chapter .. "»") or "",
            a.pageno and (" · p. " .. a.pageno) or ""))
        local passo, tronco = testo.primiCaratteri(testo.normalizza(a.text), 70)
        r(_.trf("Passage: «%s»", passo .. (tronco and "…" or "")))
        if a.note then
            local nota, tn = testo.primiCaratteri(testo.normalizza(a.note), 50)
            r(_.trf("Note: %s", nota .. (tn and "…" or "")))
        end
        r(_.trf("Style: %s", tostring(a.drawer) .. (a.color and (", " .. a.color) or "")))
        if esito.ok then
            r("→ " .. _.trf("%s, line %d, %s", e.voce.percorso, esito.riga, esito.percorso))
            r("  " .. _.trf("%d segment(s), bytes %d–%d · %s",
                #esito.segmenti, esito.inizio, esito.fine, esito.metodo))
            r("  …" .. esito.prima .. "⟦" .. esito.passo .. "⟧" .. esito.dopo .. "…")
        else
            r("✗ " .. _.trf("SKIPPED: %s", esito.motivo))
            if e.voce then r("  (" .. _.trf("file: %s", e.voce.percorso) .. ")") end
        end
        r("  pos0: " .. a.pos0)
        r("  pos1: " .. a.pos1)
        r("")
    end
    return table.concat(righe, "\n")
end

return M
