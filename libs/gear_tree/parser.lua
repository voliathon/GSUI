-- GearTree parser
-- Pattern-matches `sets.*` assignments from a Gearswap user Lua file.
-- Does NOT execute the Lua. Tolerates comments, multi-line tables, set_combine,
-- references, and the various bracket/dot key syntaxes Mote-style files use.

local parser = {}

----------------------------------------------------------------------
-- Small string helpers
----------------------------------------------------------------------

-- Strip Lua line comments (-- ...) and block comments (--[[ ... ]]).
-- Preserves line numbering by replacing comment characters with spaces
-- rather than deleting (so error messages stay accurate).
local function strip_comments(src)
    local out = {}
    local i = 1
    local n = #src
    while i <= n do
        local c = src:sub(i, i)
        local c2 = src:sub(i, i + 1)
        if c2 == '--' then
            -- Check for block comment --[[ ... ]]
            if src:sub(i, i + 3) == '--[[' then
                out[#out + 1] = '    '
                i = i + 4
                while i <= n do
                    if src:sub(i, i + 1) == ']]' then
                        out[#out + 1] = '  '
                        i = i + 2
                        break
                    end
                    local ch = src:sub(i, i)
                    out[#out + 1] = (ch == '\n') and '\n' or ' '
                    i = i + 1
                end
            else
                -- Line comment: skip to newline
                out[#out + 1] = '  '
                i = i + 2
                while i <= n and src:sub(i, i) ~= '\n' do
                    out[#out + 1] = ' '
                    i = i + 1
                end
            end
        elseif c == '"' or c == "'" then
            -- Skip string literal so embedded -- doesn't trip us
            out[#out + 1] = c
            i = i + 1
            while i <= n do
                local sc = src:sub(i, i)
                out[#out + 1] = sc
                if sc == '\\' then
                    i = i + 1
                    if i <= n then
                        out[#out + 1] = src:sub(i, i)
                        i = i + 1
                    end
                elseif sc == c then
                    i = i + 1
                    break
                else
                    i = i + 1
                end
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Find the matching closing brace/paren for the opener at position `start`.
-- Returns end position (the closing char's index) or nil.
local function find_matching(src, start, open, close)
    local depth = 0
    local i = start
    local n = #src
    while i <= n do
        local c = src:sub(i, i)
        if c == '"' or c == "'" then
            -- Skip string
            local quote = c
            i = i + 1
            while i <= n do
                local sc = src:sub(i, i)
                if sc == '\\' then
                    i = i + 2
                elseif sc == quote then
                    i = i + 1
                    break
                else
                    i = i + 1
                end
            end
        elseif c == open then
            depth = depth + 1
            i = i + 1
        elseif c == close then
            depth = depth - 1
            if depth == 0 then
                return i
            end
            i = i + 1
        else
            i = i + 1
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Key path extraction
----------------------------------------------------------------------

-- Parse the left-hand side starting with `sets`. Walk forward consuming
-- `.identifier` or `[ "string" ]` / `[ 'string' ]` segments.
-- Returns: { keys = {"sets", "precast", "WS", "Rudra's Storm", "SA"}, endpos = <position after last segment> }
local function parse_lhs(src, pos)
    -- pos should be at the 's' of "sets"
    if src:sub(pos, pos + 3) ~= 'sets' then return nil end
    local keys = { 'sets' }
    local i = pos + 4
    local n = #src

    while i <= n do
        -- Skip whitespace
        while i <= n and src:sub(i, i):match('%s') do i = i + 1 end
        local c = src:sub(i, i)

        if c == '.' then
            i = i + 1
            while i <= n and src:sub(i, i):match('%s') do i = i + 1 end
            local id_start = i
            while i <= n and src:sub(i, i):match('[%w_]') do i = i + 1 end
            if i == id_start then return nil end
            keys[#keys + 1] = src:sub(id_start, i - 1)
        elseif c == '[' then
            i = i + 1
            while i <= n and src:sub(i, i):match('%s') do i = i + 1 end
            local q = src:sub(i, i)
            if q ~= '"' and q ~= "'" then return nil end
            i = i + 1
            local key_start = i
            while i <= n and src:sub(i, i) ~= q do
                if src:sub(i, i) == '\\' then i = i + 2
                else i = i + 1 end
            end
            local key = src:sub(key_start, i - 1)
            -- Un-escape simple cases
            key = key:gsub("\\'", "'"):gsub('\\"', '"')
            keys[#keys + 1] = key
            i = i + 1 -- past closing quote
            while i <= n and src:sub(i, i):match('%s') do i = i + 1 end
            if src:sub(i, i) ~= ']' then return nil end
            i = i + 1
        else
            break
        end
    end

    return { keys = keys, endpos = i }
end

----------------------------------------------------------------------
-- Right-hand side classification and gear extraction
----------------------------------------------------------------------

-- Parse a Lua table body (the content between { and }) into a flat dict of
-- slot_name -> value_string. Best-effort: handles `slot="Item Name"`,
-- `slot=gear.foo`, `slot=empty`, and nested tables/calls (which become the
-- raw source substring).
local function parse_table_body(body)
    local out = {}
    local i = 1
    local n = #body
    while i <= n do
        -- Skip whitespace and commas
        while i <= n and body:sub(i, i):match('[%s,]') do i = i + 1 end
        if i > n then break end

        -- Slot name (identifier) - must start with a letter/underscore
        local key_start = i
        while i <= n and body:sub(i, i):match('[%w_]') do i = i + 1 end
        if i == key_start then
            -- Couldn't find an identifier; advance one to avoid loop
            i = i + 1
        else
            local key = body:sub(key_start, i - 1)
            while i <= n and body:sub(i, i):match('%s') do i = i + 1 end
            if body:sub(i, i) == '=' then
                i = i + 1
                while i <= n and body:sub(i, i):match('%s') do i = i + 1 end
                -- Now capture the value. Stop at top-level comma or end.
                local val_start = i
                while i <= n do
                    local c = body:sub(i, i)
                    if c == '"' or c == "'" then
                        local q = c
                        i = i + 1
                        while i <= n do
                            local sc = body:sub(i, i)
                            if sc == '\\' then i = i + 2
                            elseif sc == q then i = i + 1; break
                            else i = i + 1 end
                        end
                    elseif c == '{' then
                        local close = find_matching(body, i, '{', '}')
                        if close then i = close + 1 else i = n + 1 end
                    elseif c == '(' then
                        local close = find_matching(body, i, '(', ')')
                        if close then i = close + 1 else i = n + 1 end
                    elseif c == ',' then
                        break
                    else
                        i = i + 1
                    end
                end
                local val = body:sub(val_start, i - 1):gsub('%s+$', ''):gsub('^%s+', '')
                out[key] = val
            end
        end
    end
    return out
end

-- Classify and extract data from a right-hand-side expression source string.
-- Returns one of:
--   { kind = 'table',   slots = {head=..., body=...} }
--   { kind = 'combine', args = {"sets.precast.WS", "{...}"}, slots = <merged best-effort> }
--   { kind = 'ref',     target = "sets.buff['Sneak Attack']" }
--   { kind = 'other',   raw = <source> }
local function parse_rhs(rhs_src)
    local trimmed = rhs_src:gsub('^%s+', ''):gsub('%s+$', '')

    -- Literal table?
    if trimmed:sub(1, 1) == '{' then
        local close = find_matching(trimmed, 1, '{', '}')
        if close then
            local body = trimmed:sub(2, close - 1)
            return { kind = 'table', slots = parse_table_body(body), raw = trimmed }
        end
    end

    -- set_combine(...)?
    local sc_open = trimmed:match('^set_combine%s*%(()')
    if sc_open then
        local close = find_matching(trimmed, sc_open - 1, '(', ')')
        if close then
            local args_src = trimmed:sub(sc_open, close - 1)
            -- Split args at top level
            local args = {}
            local depth_p, depth_b, depth_c = 0, 0, 0
            local last = 1
            local i = 1
            local n = #args_src
            while i <= n do
                local c = args_src:sub(i, i)
                if c == '"' or c == "'" then
                    local q = c
                    i = i + 1
                    while i <= n do
                        local sc = args_src:sub(i, i)
                        if sc == '\\' then i = i + 2
                        elseif sc == q then i = i + 1; break
                        else i = i + 1 end
                    end
                elseif c == '(' then depth_p = depth_p + 1; i = i + 1
                elseif c == ')' then depth_p = depth_p - 1; i = i + 1
                elseif c == '{' then depth_c = depth_c + 1; i = i + 1
                elseif c == '}' then depth_c = depth_c - 1; i = i + 1
                elseif c == '[' then depth_b = depth_b + 1; i = i + 1
                elseif c == ']' then depth_b = depth_b - 1; i = i + 1
                elseif c == ',' and depth_p == 0 and depth_b == 0 and depth_c == 0 then
                    args[#args + 1] = args_src:sub(last, i - 1):gsub('^%s+', ''):gsub('%s+$', '')
                    last = i + 1
                    i = i + 1
                else
                    i = i + 1
                end
            end
            args[#args + 1] = args_src:sub(last):gsub('^%s+', ''):gsub('%s+$', '')

            -- For preview, try to extract slots from any literal-table args
            local merged = {}
            local refs = {}
            for _, a in ipairs(args) do
                if a:sub(1, 1) == '{' then
                    local cc = find_matching(a, 1, '{', '}')
                    if cc then
                        for k, v in pairs(parse_table_body(a:sub(2, cc - 1))) do
                            merged[k] = v
                        end
                    end
                else
                    refs[#refs + 1] = a
                end
            end
            return {
                kind = 'combine',
                args = args,
                slots = merged, -- overrides only; the referenced bases aren't resolved here
                refs = refs,
                raw = trimmed,
            }
        end
    end

    -- Reference to another sets path?
    if trimmed:match('^sets[%.%[]') then
        return { kind = 'ref', target = trimmed, raw = trimmed }
    end

    -- Identifier (e.g. an unrecognized helper call) - just store raw
    return { kind = 'other', raw = trimmed }
end

----------------------------------------------------------------------
-- Top-level: walk the file looking for `sets.* = ...` assignments
----------------------------------------------------------------------

local function line_number(src, pos)
    local _, count = src:sub(1, pos):gsub('\n', '')
    return count + 1
end

function parser.parse(src)
    src = strip_comments(src)
    local assignments = {}
    local n = #src
    local i = 1

    while i <= n do
        -- Look for "sets" starting at a word boundary
        local s = src:find('sets', i, true)
        if not s then break end
        -- Check it's a fresh identifier, not "filesets" or similar
        local prev = src:sub(s - 1, s - 1)
        if s == 1 or not prev:match('[%w_%.]') then
            local lhs = parse_lhs(src, s)
            if lhs and #lhs.keys >= 2 then
                -- Now look for "=" after the LHS (but not "==")
                local j = lhs.endpos
                while j <= n and src:sub(j, j):match('%s') do j = j + 1 end
                if src:sub(j, j) == '=' and src:sub(j + 1, j + 1) ~= '=' then
                    j = j + 1
                    while j <= n and src:sub(j, j):match('%s') do j = j + 1 end
                    -- Capture RHS: scan until a top-level statement boundary
                    -- (newline followed by something that starts a new stmt, or end).
                    -- Simpler heuristic: scan, balancing braces/parens, until we see
                    -- whitespace+(another `sets`-assignment, identifier-assignment,
                    -- keyword, or end of file). For now we use a brace-balanced scan
                    -- plus a lookahead for "\n%s*sets%." or "\n%s*end" or "\n%s*function".
                    local rhs_start = j
                    local depth_p, depth_b, depth_c = 0, 0, 0
                    while j <= n do
                        local c = src:sub(j, j)
                        if c == '"' or c == "'" then
                            local q = c
                            j = j + 1
                            while j <= n do
                                local sc = src:sub(j, j)
                                if sc == '\\' then j = j + 2
                                elseif sc == q then j = j + 1; break
                                else j = j + 1 end
                            end
                        elseif c == '(' then depth_p = depth_p + 1; j = j + 1
                        elseif c == ')' then depth_p = depth_p - 1; j = j + 1
                        elseif c == '{' then depth_c = depth_c + 1; j = j + 1
                        elseif c == '}' then depth_c = depth_c - 1; j = j + 1
                        elseif c == '[' then depth_b = depth_b + 1; j = j + 1
                        elseif c == ']' then depth_b = depth_b - 1; j = j + 1
                        elseif c == '\n' and depth_p == 0 and depth_b == 0 and depth_c == 0 then
                            -- Look ahead to see if next non-blank starts a new stmt
                            local k = j + 1
                            while k <= n and src:sub(k, k):match('[ \t]') do k = k + 1 end
                            local rest = src:sub(k, math.min(k + 20, n))
                            if rest:match('^sets[%.%[%s=]') or
                               rest:match('^[%w_]+%s*=') or
                               rest:match('^function%s') or
                               rest:match('^end%s') or rest:match('^end$') or
                               rest:match('^send_command') or
                               rest:match('^local%s') or
                               rest:match('^if%s') or rest:match('^for%s') or
                               rest:match('^while%s') or rest:match('^return') or
                               rest:match('^%-%-') then
                                break
                            end
                            j = j + 1
                        else
                            j = j + 1
                        end
                    end
                    local rhs_raw = src:sub(rhs_start, j - 1)
                    local rhs_src = rhs_raw:gsub('%s+$', '')
                    local rhs_end = rhs_start + #rhs_src - 1
                    local rhs = parse_rhs(rhs_src)
                    assignments[#assignments + 1] = {
                        keys = lhs.keys,
                        rhs = rhs,
                        lhs_start = s,
                        lhs_end = lhs.endpos - 1,
                        rhs_start = rhs_start,
                        rhs_end = rhs_end,
                        line = line_number(src, s),
                        end_line = line_number(src, rhs_end),
                    }
                    i = j
                else
                    i = lhs.endpos
                end
            else
                i = s + 4
            end
        else
            i = s + 4
        end
    end

    return assignments
end

----------------------------------------------------------------------
-- Convenience: load and parse a file path
----------------------------------------------------------------------

function parser.parse_file(path)
    local f, err = io.open(path, 'r')
    if not f then return nil, err end
    local src = f:read('*a')
    f:close()
    local assignments = parser.parse(src)
    local file_name = path:match('[^/\\]+$') or path
    for _, assignment in ipairs(assignments) do
        assignment.source_path = path
        assignment.source_file = file_name
        if assignment.lhs_start and assignment.rhs_end then
            assignment.source_text = src:sub(assignment.lhs_start, assignment.rhs_end)
        end
    end
    return assignments
end

return parser
