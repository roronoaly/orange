local BasePlugin = require("orange.plugins.base_handler")
local orange_db = require("orange.store.orange_db")
local json = require("cjson.safe")
local http = require("resty.http")
local string_format = string.format

local HomepageHandler = BasePlugin:extend()

HomepageHandler.PRIORITY = 1000

function HomepageHandler:new()
    HomepageHandler.super.new(self, "homepage-plugin")
end

function HomepageHandler:rewrite(conf)
    HomepageHandler.super.rewrite(self)
    local enable = orange_db.get("homepage.enable")
    if enable then
        --uri
        local uri_path = ngx.var.uri
        --限定首页请求
        if uri_path == "/homepage/api/query/topicIdList" then
            --请求参数
            local arg = ngx.req.get_uri_args()
            --请求header头
            local request_headers = ngx.req.get_headers()

            if arg and arg.json then
                --对json字符串进行格式化
                local json_arg, err = json.decode(arg.json)
                if not json_arg then
                    ngx.log(ngx.ERR, "failed to decode json: " .. tostring(err))
                    return
                end

                --对statinfo进行解析,base64解析后使用json序列化
                local header_statinfo = request_headers["statinfo"]
                if header_statinfo then
                    local statinfo = ngx.decode_base64(header_statinfo)
                    local statinfo_json, decode_err = json.decode(statinfo)
                    if not statinfo_json then
                        ngx.log(ngx.ERR, "failed to decode statinfo json: " .. tostring(decode_err))
                        return
                    end
                    --赋值apn字段和openudid字段
                    json_arg.apn = statinfo_json.apn
                    json_arg.openudid = statinfo_json.openudid
                    json_arg.ua = statinfo_json.ua
                end

                local city = ""
                local is_active = 1
                --app端请求才需要ip到地区的映射
                if json_arg.feeds_type == 2 or json_arg.feeds_type == 3 then
                    --请求ip地址
                    local ip = request_headers["Http-Client-Ip"]
                    if ip then
                        local location = ipip:location(ipip:find(ip))
                        city = location.city
                    end
                    --如果是推荐tab且不为柚宝宝app，则需要是否活跃用户判断
                    if json_arg.category_id == 1 then
                        local is_youbaobao = (json_arg.app_id == 2 or json_arg.app_id == 8 or json_arg.app_id == 14)
                        if not is_youbaobao then
                            --判断是否是活跃用户
                            local url = string_format("http://%s/browse/isActive?userId=%s", "60.205.219.54", json_arg.user_id)
                            local httpc = http.new()
                            -- 设置超时时间 1000 ms
                            httpc:set_timeout(1000)
                            local res, err = httpc:request_uri(url, {
                                method = "GET",
                                headers = {
                                    ["HOST"] = "homepage.my.com",
                                }
                            })

                            if not res or err then
                                ngx.log(ngx.ERR, "failed to request: ", err)
                                is_active = 1
                            end
                            is_active = (res.body == "true") and 1 or 0
                        end
                    end
                end
                --设置参数信息
                json_arg.city = city
                json_arg.is_active = is_active
                json_arg.is_test = arg.is_test
                --设置nginx请求参数
                ngx.req.set_uri_args(json_arg)
            end
        end
    end
end

function HomepageHandler:access(conf)
    --ngx.log(ngx.ERR, "homepage access")
    HomepageHandler.super.access(self)
    local enable = orange_db.get("homepage.enable")
    if enable then
        --uri
        local uri_path = ngx.var.uri
        --限定首页请求
        if uri_path == "/homepage/api/query/topicIdList" then
            local params = {}
            local json_arg = ngx.req.get_uri_args()
            params.json = json.encode(json_arg)
            params.is_test = json_arg.is_test
            ngx.req.set_uri_args(params)
        end
    end
end

return HomepageHandler
