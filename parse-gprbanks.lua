-- Parse the GPRBANKS declaration and see if there are holes in it. If
-- there are, calculate the amount of contiguous ram and check it against
-- the value declared by the .ini file.
--
-- A useful way to run this:
--
--    (for c in ini/Microchip.PIC18*/*.ini; do echo $c; lua parse-gprbanks.lua < $c; done) | less

fmt = string.format

function parse(s)
    local ram_size = tonumber(s:match "RAMSIZE=(%x+)", 16)
    local ram_start = tonumber(s:match "COMMON=(%x+)%-", 16)
    local gprbanks = s:match "GPRBANKS=([%x,-]+)"
    local expected_start_addr
    local last_contiguous
    local ram_start_inferred

    for start_addr, end_addr in gprbanks:gmatch "(%x+)%-(%x+)" do
        start_addr = tonumber(start_addr, 16)
        end_addr = tonumber(end_addr, 16)
        if start_addr % 256 ~= 0 then
            -- First bank doesn't start on a mod 256 address
            ram_start_inferred = start_addr - (start_addr % 256)
        else
            if expected_start_addr ~= start_addr then
                last_contiguous = expected_start_addr
            end
        end
        expected_start_addr = end_addr + 1
    end
    -- Comment on what we found.
    if ram_start ~= ram_start_inferred then
        print(fmt("   >>> MISMATCH: start: %04x, inferred: %04x",
            ram_start, ram_start_inferred))
    end
    if last_contiguous then
        -- We found a hole in the memory map; the declared ram size should
        -- differ from the contiguous size.
        local contiguous_size = last_contiguous - ram_start
        if contiguous_size == ram_size then
            print(fmt("   >>> UNEXPECTED MATCH: size: %04x, contiguous: %04x",
                ram_size, contiguous_size))
        else
            print(fmt("   >>> EXPECTED MISMATCH: size: %04x, contiguous: %04x",
                ram_size, contiguous_size))
        end
    else
        -- No holes in the memory map; declared ram_size should match
        -- expected_start_addr - ram_start.
        local calculated_size = expected_start_addr - ram_start
        if calculated_size ~= ram_size then
            print(fmt("   >>> MISMATCH: size: %04x, calculated: %04x",
                ram_size, calculated_size))
        end
    end
end

parse(io.stdin:read "a")
