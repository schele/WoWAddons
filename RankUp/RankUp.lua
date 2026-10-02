local addonName, ns = ...

ns.PREFIX = "|cff66ccffRankUp|r"

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

function ns.Buttons(count)
    if count == 1 then
        return "1 button"
    end
    return string.format("%d buttons", count)
end
