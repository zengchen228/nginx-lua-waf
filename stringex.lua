-- Extending the standard Lua String library.

-- Split string with resp to table
function string.split(self, reps)
    local R = {}
    self:gsub('[^'..reps..']+', function(w)
        table.insert(R, w)
    end)
    return R
end

-- Trims white space on both sides.
function string.strip(self)
    return self:match('^%s*(.-)%s*$')
end

-- Trims white space on left side.
function string.lstrip(self)
    return self:match('^%s*(.-)$')
end

-- Trims white space on right side.
function string.rstrip(self)
    return self:match('^(.-)%s*$')
end
