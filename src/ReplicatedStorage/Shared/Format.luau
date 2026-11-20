--!strict
-- Format: number/money formatting shared by server notifications and client UI.
-- Container: ReplicatedStorage.Shared

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc" }

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

-- Compact form: 1.25K, 3.4M, 12B
function Format.short(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local text = if n == math.floor(n) or n >= 100 then tostring(math.floor(n)) else string.format("%.1f", n)
		return (if negative then "-" else "") .. text
	end
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	local text
	if n >= 100 then
		text = string.format("%.0f", math.floor(n))
	elseif n >= 10 then
		text = string.format("%.1f", math.floor(n * 10) / 10)
	else
		text = string.format("%.2f", math.floor(n * 100) / 100)
	end
	return (if negative then "-" else "") .. text .. SUFFIXES[index]
end

-- Money for headline displays: $125,430 below a million, $12.5M above.
function Format.cash(n: number): string
	if math.abs(n) < 1_000_000 then
		return (if n < 0 then "-$" else "$") .. withCommas(math.abs(n))
	end
	return "$" .. Format.short(n)
end

function Format.money(n: number): string
	return "$" .. Format.short(n)
end

function Format.commas(n: number): string
	return withCommas(n)
end

function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

function Format.percent(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

return Format
