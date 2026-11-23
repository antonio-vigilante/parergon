--[[--
Data della nota di lettura ("nel novembre 2026"), nella lingua dell'interfaccia.

Non si usa os.date("%B"): dipende dalla locale del sistema, che su Kindle e
Android di solito è inglese o "C". I mesi sono scritti qui.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local M = {}

local MESI = {
    it = { "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
           "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre" },
    en = { "January", "February", "March", "April", "May", "June",
           "July", "August", "September", "October", "November", "December" },
}

--[[--
Complemento di tempo con mese e anno.
  it: "nel novembre 2026", "nell'aprile 2026" (elisione davanti a vocale)
  en: "in November 2026"
@param lingua codice ("it", "en"...); le lingue senza tabella usano l'inglese
@param t tempo (os.time), predefinito: adesso
]]
function M.meseAnno(lingua, t)
    local d = os.date("*t", t or os.time())
    if lingua == "it" then
        local mese = MESI.it[d.month]
        local prep = mese:match("^[aeiou]") and "nell'" or "nel "
        return prep .. mese .. " " .. d.year
    end
    return "in " .. MESI.en[d.month] .. " " .. d.year
end

return M
