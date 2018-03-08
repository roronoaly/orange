local ffi = require("ffi")
local cldr = require("orange.plugins.homepage.clibs_loader")
local type = type
-- local re_gmatch = ngx.re.gmatch
local re_match = ngx.re.match
local ffi_new = ffi.new
local ffi_str = ffi.string
local ffi_gc = ffi.gc
ffi.cdef[[
    typedef void *ipip_t;
    int ipip_destroy(ipip_t);
    ipip_t ipip_init(const char *ipdb);
    int ipip_find(ipip_t, const char *ip, char *result);
]]

local _M = { __index = { } }
local _MT_index = _M.__index

local libipip, ipip_init, ipip_find, ipip_destroy

local function init_mod()
    local lib = cldr.loadlib(ffi.os == "Windows" and "orange/plugins/homepage/libipip.dll" or "orange/plugins/homepage/libipip.so")
    if not lib then
        return nil, "can't load clib"
    end
    ipip_init = lib.ipip_init
    ipip_find = lib.ipip_find
    ipip_destroy = lib.ipip_destroy
    libipip = lib

    return true
end

function _M.new()
    if not libipip then
        local ok, err = init_mod()
        if not ok then
            ngx.log(ngx.ERR, "init_mod: failed, "..tostring(err))
            return nil
        end
    end
    return setmetatable({ }, _M)
end

function _MT_index:init(ipdb_path)
    if type(ipdb_path) ~= "string" then
        return nil, "invalid params"
    end
    local ret = ipip_init(ipdb_path)
    if not ret or tonumber(ffi.cast("intptr_t", ret)) == 0 then
        -- error
        return nil, "failed to load ipdb"
    end

    self._buff = ffi_new("char[512]")
    self._ipip = ret
    local status = { }
    self._status = status
    ffi_gc(ret, function() if not status.deleted then ipip_destroy(ret) end end) -- TODO: seems like don't work..

    return true
end

function _MT_index:uninit()
    if self._ipip then
        self._status.deleted = true
        local ret = ipip_destroy(self._ipip)
        self._ipip = nil

        return ret
    end
    return nil, "not initialized"
end

function _MT_index:find_city(ip)
    if type(ip) ~= "string" then
        return nil, "invalid params"
    end

    if self._ipip then
        if ipip_find(self._ipip, ip, self._buff) < 0 then
            return nil, "invalid params"
        end

        local cap = re_match(ffi_str(self._buff), "([^\\t]+)\\s([^\\t]+)", "sjio")
        return { cap[1], cap[2] }
    end
    return nil, "not initialized"
end

function _MT_index:find_full(ip)
    if type(ip) ~= "string" then
        return nil, "invalid params"
    end

    if self._ipip then
        if ipip_find(self._ipip, ip, self._buff) < 0 then
            return nil, "invalid params"
        end

        local ret = { }
        local i = 1
        for v in re_gmatch(ffi_str(self._buff), "([^\\t]+)", "sjio") do
            ret[i] = v[1]
            i = i + 1
        end
        return ret
    end
    return nil, "not initialized"
end

function _MT_index:find_str(ip)
    if type(ip) ~= "string" then
        return nil, "invalid params"
    end

    if self._ipip then
        if ipip_find(self._ipip, ip, self._buff) < 0 then
            return nil, "invalid params"
        end

        return ffi_str(self._buff)
    end
    return nil, "not initialized"
end

return _M
