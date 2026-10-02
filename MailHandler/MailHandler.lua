local addonName, ns = ...

ns.PREFIX = "|cff66ccffMailHandler|r"

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises.
-- This client hands addon code some values as secrets: the call succeeds,
-- but comparing or testing the result raises. The branch has to happen
-- inside `fn`, not on a value fetched through here and tested outside.
function ns.Guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

--- Copper as the game writes money, coin icons and all; "1g 23s 4c" on a
-- client without that.
function ns.Money(copper)
    if GetMoneyString then
        return GetMoneyString(copper)
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if rest > 0 or #parts == 0 then
        parts[#parts + 1] = rest .. "c"
    end
    return table.concat(parts, " ")
end

--- "1 mail", "2 mails".
function ns.Count(count, word)
    if count == 1 then
        return "1 " .. word
    end
    return string.format("%d %ss", count, word)
end

--- Something about the ticks or the opening changed: redraw the boxes and
-- Open's count, if they are made.
function ns.Changed()
    if ns.Buttons and ns.Buttons.Refresh then
        ns.Buttons.Refresh()
    end
end
