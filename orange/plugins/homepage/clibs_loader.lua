local ffi = require "ffi"
local function _loadlib(libpath)
    local path

    local f = io.open(libpath)
    if f ~= nil then
        io.close(f)
        path = libpath
    end
    return path and ffi.load(path)
end

return {
    loadlib = _loadlib
}
