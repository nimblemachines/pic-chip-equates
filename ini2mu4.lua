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

-- There might be one each of these:
--   CFGMEM=<range_start>,<range_end>
--   EEPROM=<range_start>,<range_end>
--   USERIDMEM=<range_start>,<range_end>

-- And several of these:
--   INTSRC=<name>,<irq number>,<description>
--   SFR=<name>,<address>,<bit-width>
--   SFRFLD=<name>,<address>,<bit-position>,<bit-width>

function parse_ini(s)
    local function parse_range(name)
        local range_start, range_end = s:match(name .. "=(%x+)%-(%x+)")
        if range_start then
            local range_start, range_end = tonumber(range_start, 16), tonumber(range_end, 16)
            -- Return start and size.
            return { range_start, range_end - range_start + 1 }
        end
        return nil
    end

    local rom_size = s:match("ROMSIZE=(%x+)")
    if rom_size then rom_size = tonumber(rom_size, 16) end

    local ram_size = s:match("RAMSIZE=(%x+)")
    if ram_size then ram_size = tonumber(ram_size, 16) end

    local config = parse_range "CFGMEM"
    local eeprom = parse_range "EEPROM"
    local userid = parse_range "USERIDMEM"

    -- Start of RAM is hard. For PIC18's we can infer it from the first part of
    -- COMMON=<addr>.
    local ram_start = s:match "COMMON=(%x+)%-"
    if ram_start then ram_start = tonumber(ram_start, 16) end

    -- We need to know how many bits in the bank select register (BSR).
    -- For many PIC18 parts, it is 4 bits. There are several newer parts
    -- with lots of RAM and i/o that have 6 bit BSRs.
    -- For some reason, at least with the K and Q parts, it has a "0x"
    -- prefix!
    -- For now, we don't bother trying to match a decimal version.
    local bsr_bits = s:match "BSRBITS=0x(%x+)\n"
    if bsr_bits then
        bsr_bits = tonumber(bsr_bits, 16)
    end

    -- Some special hacks where PIC18 and PIC16 differ.
    if s:match "ARCH=PIC14E" then
        -- For PIC16 parts, we match BANKSELBITS. Also has 0x prefix!
        bsr_bits = s:match "BANKSELBITS=0x(%x+)\n"
        if bsr_bits then
            bsr_bits = tonumber(bsr_bits, 16)
        end
        -- For PIC16's, LINEARBASE is better a better @ram.
        -- XXX Not sure how to deduce linear #ram number!
        ram_start = s:match "LINEARBASE=0x(%x+)\n"
        if ram_start then ram_start = tonumber(ram_start, 16) end
        -- Config space is named differently from PIC18.
        config = parse_range "CONFIG"
    end

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
    for name, addr, bit_width in s:gmatch("SFR=(%w+),(%x+),(%d+)") do
        addr, bit_width = tonumber(addr, 16), tonumber(bit_width, 10)
        if bit_width > 8 then
            sfrs[#sfrs+1] = { name = name, addr = addr, bit_width = bit_width }
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
        config = config,
        eeprom = eeprom,
        userid = userid,
        bsr_bits = bsr_bits,
        vectors = vectors,
        sfrs = sfrs,
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
    local p = function(fmt, ...)
        -- Remove any trailing whitespace
        print((string.gsub(string.format(fmt, ...), "%s+$", "")))
    end

    local function kibi(n)
        if (n >= 1024) and (n & 0x3ff == 0) then
            -- Print Ki in decimal. If > 9, print # prefix.
            local ki = n >> 10
            local prefix = (ki > 9) and "#" or ""
            return fmt("%s%d Ki", prefix, ki)
        else
            return fmt("%x", n)
        end
    end

    local function origin(m)
        return fmt("%02x_%04x", m >> 16, m & 0xffff)
    end

    local function print_range(name, r)
        if r then
            if r[1] > 0x10000 then
                -- PIC18
                p("\n%s constant @%s", origin(r[1]), name)
                p("%7s constant #%s", kibi(r[2]), name)
            else
                -- PIC16
                p("\n%04x constant @%s", r[1], name)
                p("%4s constant #%s", kibi(r[2]), name)
            end
        end
    end

    p("( Equates for %s, generated from %s.)", chip, pack_file)
    p "\nhex"
    p("\n%s constant #flash", kibi(eq.rom_size))

    p("\n%x constant @ram", eq.ram_start)
    if eq.ram_size then
        p("%s constant #ram", kibi(eq.ram_size))
    end

    -- Print these in memory order.
    print_range("user-id", eq.userid)
    print_range("config", eq.config)
    print_range("eeprom", eq.eeprom)

    if eq.bsr_bits and eq.bsr_bits >= 4 then
        p("\n%d constant bsr-bits", eq.bsr_bits)
    else
        p "\nerror\" No BSRBITS definition found. Probably an error.\""
    end

    if #eq.vectors > 0 then
        p "\ndecimal\n\n( Vector table)"
        for _,v in ipairs(eq.vectors) do
            p("%3d vector %-14s | %s", v.irq_num, v.name.."_IRQ", v.descr)
        end
    end

    p "\nhex\n\n( SFRs)"
    for _,sfr in ipairs(eq.sfrs) do
        if sfr.bit_width then
            p("%04x equ %-12s | alias; %d bits wide",
                sfr.addr, sfr.name, sfr.bit_width)
        else
            p("%04x equ %-12s%s",
                sfr.addr, sfr.name, bit_names(sfr_fields[sfr.addr]))
        end
    end
end

-- arg 1 is ini file, in the following form: ini/<pack>/<chip>.ini
function doit()
    local pack_file, chip = arg[1]:match "^ini/(..-)/(..-)%.ini"
    local f = io.open(arg[1], "r")
    local contents = f:read("a")   -- read entire file as a string
    f:close()
    print_equates(pack_file, chip, parse_ini(contents))
end

doit()
