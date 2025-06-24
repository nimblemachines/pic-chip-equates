-- Figure out where the RAM and SFRs are relative to each other.
--
-- A useful way to run this:
--
--    (for c in ini/Microchip.PIC18*/*.ini; do lua ram-info.lua $c < $c; done) | less

fmt = string.format

function parse(chip, s)
    local ram_start = tonumber(s:match "COMMON=(%x+)%-", 16)
    local ram_size = tonumber(s:match "RAMSIZE=(%x+)", 16)
    local bsr_bits = tonumber(s:match "BSRBITS=0x(%x+)", 16)

    local sfr_min, sfr_max = (1 << (bsr_bits+8)), 0
    for name, addr, bit_width in s:gmatch("SFR=(%w+),(%x+),(%d+)") do
        addr, bit_width = tonumber(addr, 16), tonumber(bit_width, 10)
        if bit_width == 8 then
            -- Ignore aliases
            if addr < sfr_min then sfr_min = addr end
            if addr > sfr_max then sfr_max = addr end
        end
    end
    print(fmt("%-10s %04x %04x %d %04x %04x", chip, ram_start, ram_size, bsr_bits, sfr_min, sfr_max))
end

-- arg[1] is the path to the chip .ini file
chip = arg[1]:match "/([^/]+)%.ini$"
parse(chip, io.stdin:read "a")
