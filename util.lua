-- 将日志发送到远端需要启用socket
-- local logger = require "socket"
local io = require("io")
local cjson = require("cjson.safe")
local string = require("string")
local config = require("config")

local _M = {
    version = "0.1",
    RULE_TABLE = {},
    RULE_FILES = {
        "args.rule",
        "blackip.rule",
        "cookie.rule",
        "post.rule",
        "url.rule",
        "useragent.rule",
        "whiteip.rule",
        "whiteurl.rule",
        "frequency.rule"   -- 新加
    }
}

-- 建立字典 规则类名称:规则文件路径
function _M.get_rule_files(rules_path)
    local rule_files = {}
    for _, file in ipairs(_M.RULE_FILES) do
        if file ~= "" then
            local file_name = rules_path .. '/' .. file
            ngx.log(ngx.DEBUG, string.format("规则:%s, 文件路径:%s", file, file_name))
            rule_files[file] = file_name
        end
    end
    return rule_files
end

-- 载入规则到本模块RULE_TABLE
function _M.get_rules(rules_path)
    local rule_files = _M.get_rule_files(rules_path)
    if rule_files == {} then
        return nil
    end
    for rule_name, rule_file in pairs(rule_files) do
        local t_rule = {}
        --修改为按行读取规则文件
        local file_rule_name = io.open(rule_file,"r")
        if file_rule_name ~= nil then
            for line in file_rule_name:lines() do
                --在规则文件中可以使用lua模式的注释
                if string.sub( line, 1, 2 ) ~= "--" then
                    -- string.gsub(s, "^%s*(.-)%s*$", "%1") 去除字符串s两端的空格
                    table.insert(t_rule, (string.gsub(line, "^%s*(.-)%s*$", "%1")))
                    ngx.log(ngx.INFO, string.format("规则名称:%s, 值:%s", rule_name, line))
                end
            end
        end
        file_rule_name:close()
        ngx.log(ngx.INFO, string.format("规则文件%s读取完毕!", rule_file))
        _M.RULE_TABLE[rule_name] = t_rule
    end
    return (_M.RULE_TABLE)
end

-- 获取来访IP
function _M.get_client_ip()
    local CLIENT_IP = ngx.req.get_headers()["X_real_ip"]
    if CLIENT_IP == nil then
        CLIENT_IP = ngx.req.get_headers()["X_Forwarded_For"]
    end
    if CLIENT_IP == nil then
        CLIENT_IP = ngx.var.remote_addr
    end
    if CLIENT_IP == nil then
        CLIENT_IP = "0.0.0.0"
    end
    -- 判断CLIENT_IP是否为table类型，table类型即获取到多个ip的情况
    if type(CLIENT_IP) == "table" then
        CLIENT_IP = table.concat(CLIENT_IP, ",")
    end
    if type(CLIENT_IP) ~= "string" then
        CLIENT_IP = "0.0.0.0"
    end
    return CLIENT_IP
end

-- 获取UserAgnet
function _M.get_user_agent()
    local USER_AGENT = ngx.var.http_user_agent
    if USER_AGENT == nil then
        USER_AGENT = "unknown"
    end
    return USER_AGENT
end

-- 记录JSON格式日志
function _M.log_record(config_log_dir, attack_type, url, data, ruletag)
    local log_path = config_log_dir
    local client_IP = _M.get_client_ip()
    local user_agent = _M.get_user_agent()
    local server_name = ngx.var.server_name
    local local_time = string.sub(ngx.localtime(),1,10).."T"..string.sub(ngx.localtime(),12,-1).."+08:00"
    local log_json_obj = {
        realip = client_IP,
        timestamp = local_time,
        server = server_name,
        agent = user_agent,
        attack_type = attack_type,
        urls = url,
        url = ngx.var.uri,
        postdata = data,
        ruletag = ruletag,
        waf_mode = config.config_waf_model,
    }
    local log_line = cjson.encode(log_json_obj)
    -- log_line = string.gsub(log_line,"\\\"","")   -- 去掉所有\"
    -- log_line = string.gsub(log_line,"\\","")     -- 去掉所有\
    local log_name = string.format("%s/%s_waf.log", log_path, ngx.today())
    local file, err = io.open(log_name, "a+")
    if err ~= nil then ngx.log(ngx.DEBUG, "file err:" .. err) end
    if file == nil then
        return
    end
    file:write(string.format("%s\n", string.gsub(string.gsub(log_line,"\\\"",""),"\\","")))
    file:flush()
    file:close()
end

-- 恶意访问处理函数
-- 使用log模式时，仅记录ip到共享存储
function _M.waf_output()
    local bad_guy_ip = _M.get_client_ip()
    _M.set_bad_guys(bad_guy_ip, config.config_expire_time)

    if config.config_waf_model == "redirect" then
        ngx.redirect(config.config_waf_redirect_url, 301)
    elseif config.config_waf_model == "log" then
        return
    else
        ngx.header.content_type = "text/html"
        ngx.status = ngx.HTTP_FORBIDDEN
        ngx.say(string.format(config.config_output_html, _M.get_client_ip()))
        ngx.exit(ngx.status)
    end
end

-- 获取请求头中Host字段
function _M.get_server_host()
    local host = ngx.req.get_headers()["Host"]
    return host
end

-- 将IP存入共享存储gadGuys
function _M.set_bad_guys(bad_guy_ip, expire_time)
    local badGuys = ngx.shared.badGuys
    local ret, _ = badGuys:get(bad_guy_ip)
    if ret then
        badGuys:incr(bad_guy_ip, 1)
    else
        badGuys:safe_set(bad_guy_ip, 1, expire_time)
    end
end

-- 检查来访IP是否为标记过的恶意IP
function _M.bad_guy_check()
    local badGuys = ngx.shared.badGuys
    local ret, _ = badGuys:get(_M.get_client_ip())
    if client_ip ~= "" then
        if ret ~= nil and ret > 0 then
            return true
        end
    end
    return false
end

return _M
