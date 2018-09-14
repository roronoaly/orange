local BasePlugin = require("orange.plugins.base_handler")
local orange_db = require("orange.store.orange_db")
local json = require("cjson.safe")
local http = require("resty.http")
local dns_client = require "resty.dns.client"
local toip = dns_client.toip
local string_format = string.format

local HomepageHandler = BasePlugin:extend()

HomepageHandler.PRIORITY = 1000

function HomepageHandler:new()
    HomepageHandler.super.new(self, "homepage-plugin")
end

local function check_upstream()
    local selectors = orange_db.get_json("balancer.selectors")
    for _, upstream in pairs(selectors) do
        if upstream.backup_enable then
            --获取upstream的服务节点
            local targets = orange_db.get_json("balancer.selector." .. upstream.id .. ".rules")
            --服务节点必须要大于0
            if targets and #targets > 0 then
                local sum = 0
                local fail_count = 0
                for _, t in ipairs(targets) do
                    if t.enable then
                        sum = sum + 1
                        --匹配出host和port
                        local host, port_num = string.match(t.target, "^(.-):(%d+)$")
                        port_num = tonumber(port_num)

                        -- have to do a regular DNS lookup
                        local ip, port = toip(host, port_num, true)
                        if not ip then
                            if port == "dns server error; 3 name error" then
                                -- in this case a "503 service unavailable", others will be a 500.
                                ngx.log(ngx.ERR, "name resolution failed for '", host, "': ", port)
                            end
                        end

                        --判断是服务节点是否正常
                        local url = string_format("http://%s:%d/health", ip, port)
                        local httpc = http.new()
                        -- 设置超时时间1s
                        httpc:set_timeout(1000)
                        local res, err = httpc:request_uri(url, {
                            method = "GET",
                            headers = {
                                ["HOST"] = "homepage.my.com",
                            }
                        })
                        if not res or err or not res.status == 200 then
                            ngx.log(ngx.ERR, "failed to request,url:", url, ",error:", err)
                            fail_count = fail_count + 1
                        end
                        -- ngx.log(ngx.INFO, "[url]:", url, ",[res status]:", res.status)
                    end
                end
                --错误的节点是否超过半数
                local status = fail_count <= (sum / 2)
                ngx.log(ngx.INFO, "[upstream name]:", upstream.name, ",[status]:", status)
                orange_db.set("balancer.selector." .. upstream.id .. ".status", status)
            end
        end
    end

    local interval = 1
    local ok, err = ngx.timer.at(interval, function() check_upstream() end)
    if not ok then
        ngx.log(ngx.ERR, "failed to create check upstream the timer: ", err)
        return
    end
end


function HomepageHandler:init_worker()
    HomepageHandler.super.init_worker(self)
    ngx.log(ngx.INFO, "homepage init worker")
    -- 单进程，只执行一次
    if ngx.worker.id() == 0 then
        --2s后执行，让插件将数据加载到dict中
        local interval = 2
        local ok, err = ngx.timer.at(interval, function() check_upstream() end)
        if not ok then
            ngx.log(ngx.ERR, "failed to create check upstream the timer: ", err)
            return
        end
    end
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

                --兼容处理为空的情况
                if not json_arg.category_id then
                    json_arg.category_id = 1
                end
                --兼容处理关注频道user_id为空的问题
                if json_arg.category_id == 51 then
                    if type(json_arg.user_id) == "userdata" then
                        json_arg.user_id = 0
                    end
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
                    --赋值ip信息
                    local ip = request_headers["Http-Client-Ip"]
                    if ip then
                        json_arg.ip = ip
                    end
                    if json_arg.ip then
                        local location = ipip:location(ipip:find(json_arg.ip))
                        city = location.city
                    end
                    --如果是推荐tab且不为柚宝宝app，则需要是否活跃用户判断
                    if json_arg.category_id == 1 then
                        local is_youbaobao = (json_arg.app_id == 2 or json_arg.app_id == 8 or json_arg.app_id == 14)
                        if not is_youbaobao then
                            --判断是否是活跃用户
                            local url = string_format("http://%s/browse/isActive?userId=%s", "127.0.0.1:80", json_arg.user_id)
                            local httpc = http.new()
                            -- 设置超时时间 2000 ms
                            httpc:set_timeout(2000)
                            local res, err = httpc:request_uri(url, {
                                method = "GET",
                                headers = {
                                    ["HOST"] = "homepage.my.com",
                                }
                            })

                            if not res or err then
                                ngx.log(ngx.ERR, "failed to request: ", err)
                                is_active = 1
                            else
                                is_active = (res.body == "true") and 1 or 0
                            end
                        end
                    end
                end
                --设置参数信息
                json_arg.city = city
                json_arg.is_test = arg.is_test
                --维密后台特殊处理
                if arg.is_vm and arg.is_vm == "1" then
                    is_active = (arg.is_active == "1") and 1 or 0
                    json_arg.is_vm = arg.is_vm
                end
                json_arg.is_active = is_active
                --ngx.log(ngx.ERR, "params:" .. json.encode(json_arg))
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
            if json_arg.is_vm and json_arg.is_vm == "1" then
                json_arg.user_id = math.floor(json_arg.user_id / 100)
            end
            params.json = json.encode(json_arg)
            params.is_test = json_arg.is_test
            ngx.req.set_uri_args(params)
        end
    end
end

return HomepageHandler
