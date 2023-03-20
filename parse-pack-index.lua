-- After downloading the Microchip pack index, parse it

fmt = string.format

-- An entry looks like this:
-- </h3>
--            <button type="button" class="btn btn-primary pull-right download-button" data-toggle="modal" data-target="#eula-modal" data-link="Microchip.ATtiny_DFP.3.0.151.atpack">

function parse(s)
    local packs = {}
    for pack in s:gmatch [[</h3>%s+<button.-data%-link="(%S-%.atpack)">]] do
        packs[#packs+1] = pack
    end

    return packs
end

function print_as_lua(p)
    io.write "return {\n"
    for _, pack in ipairs(p) do
        io.write(fmt("  %q,\n", pack))
    end
    io.write "}\n"
end

-- arg 1 is file to process
function doit()
    local s = io.stdin:read("a")   -- read entire file as a string
    print_as_lua(parse(s))
end

doit()

junk = [[
Microchip.PIC12-16F1xxx_DFP.1.3.90
Microchip.PIC12-16F1xxx_DFP.1.3.90.atpack
Microchip.PIC18F-K_DFP.1.8.249
Microchip.PIC18F-K_DFP.1.8.249.atpack
Microchip.PIC18F-Q_DFP.1.16.368
Microchip.PIC18F-Q_DFP.1.16.368.atpack
Microchip.PICkit4_TP.1.15.1688
Microchip.PICkit4_TP.1.15.1688.atpack
]]
