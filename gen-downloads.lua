-- Generate a list of curl commands based on a Microchip pack index

fmt = string.format

function print_commands(pack_index, repo_url, pack_pattern, cmd)
    for _, p in ipairs(pack_index) do
        -- Which pack(s) do we want?
        if p:match(pack_pattern) then
            if cmd == "show" then
                print(p)
            elseif cmd == "get" then
                print(fmt("[ -f pack/%s ] || curl -L -o pack/%s %s%s", p, p, repo_url, p))
            end
        end
    end
end

-- arg 1 is pack file index in lua form
-- arg 2 is pack repo base url
-- arg 3 is packname match string
-- arg 4 is "show" or "get"
function doit()
    print_commands(dofile(arg[1]), arg[2], arg[3], arg[4])
end

doit()
