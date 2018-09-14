local BaseAPI = require("orange.plugins.base_api")
local common_api = require("orange.plugins.common_api")
local http = require("resty.http")
local dns_client = require "resty.dns.client"
local toip = dns_client.toip
local string_format = string.format
local json = require("cjson.safe")


local api = BaseAPI:new("balancer-api", 2)
api:merge_apis(common_api("balancer"))

api:get("/balancer/eureka/apps", function(store)
    return function(req, res, next)
        -- have to do a regular DNS lookup
        local ip, port = toip("luffy-cloud", 7998, true)
        if not ip then
            if port == "dns server error; 3 name error" then
                -- in this case a "503 service unavailable", others will be a 500.
                ngx.log(ngx.ERR, "name resolution failed for luffy-cloud'': ", port)
            end
        end

        --判断是服务节点是否正常
        local url = string_format("http://%s:%d/eureka/apps/", ip, port)
        local httpc = http.new()
        -- 设置超时时间1s
        httpc:set_timeout(1000)
        local http_res, err = httpc:request_uri(url, {
            method = "GET",
            headers = {
                ["HOST"] = "homepage.my.com",
                ["Content-Type"] = "application/json;charset=UTF-8",
                ["Accept"] = "application/json",
            }
        })

        local success, data
        if not http_res or err or not http_res.status == 200 then
            ngx.log(ngx.ERR, "failed to request,url:", url, ",error:", err)
            success = false
            data = err
        else
            success = true
            data = json.decode(http_res.body)
        end

        res:json({
            success = success,
            data = data
        })
    end
end)

api:get("/balancer/eureka/get/apps", function(store)
    return function(req, res, next)
        --请求name
        local name = req.query.name

        -- have to do a regular DNS lookup
        local ip, port = toip("luffy-cloud", 7998, true)
        if not ip then
            if port == "dns server error; 3 name error" then
                -- in this case a "503 service unavailable", others will be a 500.
                ngx.log(ngx.ERR, "name resolution failed for luffy-cloud'': ", port)
            end
        end

        --判断是服务节点是否正常
        local url = string_format("http://%s:%d/eureka/apps/%s", ip, port, name)
        local httpc = http.new()
        -- 设置超时时间1s
        httpc:set_timeout(1000)
        local http_res, err = httpc:request_uri(url, {
            method = "GET",
            headers = {
                ["HOST"] = "homepage.my.com",
                ["Content-Type"] = "application/json;charset=UTF-8",
                ["Accept"] = "application/json",
            }
        })

        local success, data
        if not http_res or err or not http_res.status == 200 then
            ngx.log(ngx.ERR, "failed to request,url:", url, ",error:", err)
            success = false
            data = err
        else
            success = true
            data = json.decode(http_res.body)
        end

        res:json({
            success = success,
            data = data
        })
    end
end)

return api
