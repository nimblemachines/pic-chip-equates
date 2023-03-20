-- "Parse" a Microchip PIC .ini file and generate a muforth .mu4 equates
-- file.

-- We are going to write this as a simple filter. It sucks in its input;
-- processes it; and writes out a .mu4 file. However, we want to pass some
-- metadata on the command line: the name/version of the pack file, and the
-- name of the chip file.

function fix_irq_descr(d)
    d = d:gsub("%*", " ")
         :gsub("Treshold", "Threshold")
    return d
end

-- We want to match the following:

-- There is one each of these:
--   ROMSIZE=<size_of_rom>
--   RAMSIZE=<size_of_ram>
--   EEPROM=<range_start>,<range_end>

-- And several of these:
--   INTSRC=<name>,<irq number>,<description>
--   SFR=<name>,<address>,<bit-width>
--   SFRFLD=<name>,<address>,<bit-position>,<bit-width>

function parse_ini(s)
    local rom_size = s:match("ROMSIZE=(%x+)")
    if rom_size then rom_size = tonumber(rom_size, 16) end

    local ram_size = s:match("RAMSIZE=(%x+)")
    if ram_size then ram_size = tonumber(ram_size, 16) end

    local eeprom_start, eeprom_end = s:match("EEPROM=(%x+)%-(%x+)")
    if eeprom_start then
        eeprom_start = tonumber(eeprom_start, 16)
        eeprom_end = tonumber(eeprom_end, 16)
    end

    -- Start of RAM is hard. We can maybe infer it from the first part of
    -- COMMON=<addr>.
    local ram_start = s:match("COMMON=(%x+)%-")
    if ram_start then ram_start = tonumber(ram_start, 16) end

    -- Parse interrupt sources - aka vector table.
    vectors = {}
    for name, irq_num, descr in s:gmatch("INTSRC=(%w+),(%d+),(%S+)") do
        vectors[#vectors+1] = {
            name = name,
            irq_num = tonumber(irq_num, 10),
            descr = fix_irq_descr(descr)
        }
    end

    -- Need this because many PICs don't have an interrupt vector table!
    if #vectors > 0 then
        -- Create a "dummy" LAST vector so we know where the table ends.
        local last_vector = vectors[#vectors].irq_num + 1
        vectors[#vectors+1] = {
            name = "LAST",
            irq_num = last_vector,
            descr = "dummy LAST vector to mark end of vector table"
        }
    end

    -- Parse SFRs.
    sfrs = {}
    sfr_alias = {}
    for name, addr, bit_width in s:gmatch("SFR=(%w+),(%x+),(%d+)") do
        addr, bit_width = tonumber(addr, 16), tonumber(bit_width, 10)
        if bit_width > 8 then
            sfr_alias[addr] = { name = name, bit_width = bit_width }
        else
            -- assume a bit_width of 8
            sfrs[#sfrs+1] = { name = name, addr = addr }
        end
    end

    -- Parse SFR fields.
    -- Unfortunately, our job is complicated by the fact that Microchip
    -- has, in many places, multiples names for the same field, and also
    -- sometimes names an aggregate of several bits, but then also names
    -- each constituent bit individually!
    --
    -- We want to favor the shorter name over the longer; and favor the
    -- narrower field over the wider.
    --
    -- Each entry in sfr_fields, which is indexed by addr, as an array of
    -- eight bit-names: [1] is bit7, [2] is bit6, etc.
    sfr_fields = {}
    for name, addr, lsb, bit_width in s:gmatch("SFRFLD=(%w+),(%x+),(%d+),(%d+)") do
        addr, lsb, bit_width =
            tonumber(addr, 16),
            8 - tonumber(lsb, 10),
            tonumber(bit_width, 10)

        if bit_width == 1 then      -- we ignore anything wider!
            local bits = sfr_fields[addr] or {}
            sfr_fields[addr] = bits

            -- If we don't already have a name for this bit, or if the new
            -- name is shorter, set bit name to new name.

            -- Return true if y is nil, or x is shorter than y; but return
            -- false if y starts with "n".
            local is_shorter = function(x, y)
                if not y then return true end
                if y:match "^n" then return false end
                return (string.len(x) < string.len(y))
            end

            if is_shorter(name, bits[lsb]) then
                --print(string.format("  replacing %s with %s", bits[lsb], name))
                bits[lsb] = name
            end
        end
    end

    -- Return everything in a table.
    return {
        rom_size = rom_size,
        ram_start = ram_start,
        ram_size = ram_size,
        eeprom_start = eeprom_start,
        eeprom_end = eeprom_end,
        vectors = vectors,
        sfrs = sfrs,
        sfr_alias = sfr_alias,
        sfr_fields = sfr_fields
    }
end

-- Return either an empty string (if bits is empty), or " | " prepended to
-- the list of bits, each one in a fixed-width field.
function bit_names(bits)
    -- If name is xyzPPS<n>, just make it PPS<n> so it's not so damn long.
    local nicer = function(name) return name:match "PPS%d$" or name end

    if not bits then return "" end
    for i = 1,8 do
        bits[i] = string.format("%-8s", nicer(bits[i] or "--"))
    end
    return " | " .. table.concat(bits, "  ")
end

function print_equates(pack_file, chip, eq)
    local p = function(fmt, ...) print(string.format(fmt, ...)) end

    p("( Equates for %s, generated from %s.)", chip, pack_file)
    p "\ndecimal"
    p("\n%d constant #flash", eq.rom_size)      -- XXX print as KiB?
    p("\"%04x constant @ram", eq.ram_start)

    if eq.ram_size then
        p("%d constant #ram", eq.ram_size)
    end
    if eq.eeprom_start then
        p("\"%6x constant @eeprom", eq.eeprom_start)
        p("%d constant #eeprom", eq.eeprom_end - eq.eeprom_start + 1)
    end

    if #eq.vectors > 0 then
        p "\n( Vector table)"
        for _,v in ipairs(eq.vectors) do
            p("%3d vector %-14s | %s", v.irq_num, v.name.."_IRQ", v.descr)
        end
    end

    p "hex\n\n( SFRs)"
    for _,sfr in ipairs(eq.sfrs) do
        local alias = sfr_alias[sfr.addr]
        if alias then
            p("%04x equ %-12s | alias; %d bits wide",
                sfr.addr,
                alias.name,
                alias.bit_width)
        end
        p("%04x equ %-12s%s", sfr.addr, sfr.name, bit_names(sfr_fields[sfr.addr]))
    end
end

-- arg 1 is pack file, arg 2 is chip
function doit()
    local pack_file = arg[1]
    local chip = arg[2]
    local contents = io.stdin:read("a")   -- read entire file as a string
    print_equates(pack_file, chip, parse_ini(contents))
end

doit()
