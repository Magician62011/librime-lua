-- 2024-10-09	Magician62011
-- 功能目标：实现主动切换界面横竖显示 
-- 方法：
-- 使用快捷键触发配置值'style/horizontal'更改
-- 使用lua_processor实现连续的状态判断
-- 使用switcher:process_key发送hotkey实现触发UI界面更新（若使用engine:process_key发送hotkey则会造成不再进入processor导致后续无法处理）

-- 跨processor变量
local n = 0
local i = 0 
local switcher_active = nil
local Switcher_lasttime = nil
local temp_input = nil
local manual = false

--控制日志输出打印
local function log_error(info)
	local log_enable = false --false --true 
	if log_enable then 
		log.error(info)
	end
end

local function horizontal_switch(key_event, env)
	--进入processor次数
	n = n+1
	log_error("n: "..n)
	
	--输出触发按键信息
	local keyrepr = key_event:repr()
	log_error("keyrepr: "..tostring(keyrepr))
	
	--获得engine和context
	local engine = env.engine
	log_error("engine: "..tostring(engine))
	local context = engine.context
	log_error("context.input: "..tostring(context.input))


	--再次进入processor时发送Escape 实现界面变化
	if Switcher_lasttime ~= nil and switcher_active == true then
		log_error("Phase2**Switcher_lasttime.active-step2: "..tostring(Switcher_lasttime.active))
		result_2 = Switcher_lasttime:process_key( KeyEvent("Escape") )
		log_error("Phase2**send Escape : "..(result_2 and 'success' or 'fail'))
		--再检查active状态
		log_error("Phase2**Switcher_lasttime.active-step3: "..tostring(Switcher_lasttime.active))
		switcher_active = nil
		if i > 1 then 
			temp_input = context.input
			i = 0
		end 
		context:clear() 
		return 2 --关键处理，能使界面变化
	end
	
	--第三次进入到processor时，处理context.input，在新界面恢复先前输入内容
	if temp_input ~= nil and switcher_active == nil then 
		context.input = temp_input
		log_error("Phase3***new context input replaced: "..tostring(context.input))
		temp_input = nil
		return 2
	end


	local schema = engine.schema
	local h_config_state = schema.config:get_bool('style/horizontal')	--获得设置里横竖状态 布尔值 -- schema.yaml文件中要有style/horizontal的配置，否则返回nil，首次not h_config_state为true横向
	log_error("h_config_state: "..tostring(h_config_state))
	
	local function send_hotkey()
		--保存当前输入
		temp_input = context.input
		log_error("Phase1*current context input: "..tostring(temp_input))
		--修改配置值
		schema.config:set_bool('style/horizontal', not h_config_state) 
		log_error("Phase1*--change horizontal--")
		--检查配置值修改成功
		local h_config_state_new = schema.config:get_bool('style/horizontal') 
		log_error("Phase1*h_config_state_new: "..tostring(h_config_state_new ))
		
		-- 判断条件 发送hotkey(Control+grave) 触发开关界面
		if h_config_state_new == not h_config_state then 
			--创建开关对象
			switcher = Switcher(env.engine)
			log_error("Phase1*switcher1: "..tostring(switcher))
			--检查active状态
			log_error("Phase1*switcher.active-original: "..tostring(switcher.active))
			--发送hotkey
			local result_1 = switcher:process_key( KeyEvent("Control+grave") )
			log_error("Phase1*send Control+grave : "..(result_1 and 'success' or 'fail'))
			--检查active状态
			log_error("Phase1*switcher-if: "..tostring(switcher))
			--保留active状态
			switcher_active = switcher.active
			log_error("Phase1*switcher.active-step1: "..tostring(switcher_active))
			--保留开关对象
			Switcher_lasttime = switcher
			log_error("Phase1*Switcher_lasttime: "..tostring(Switcher_lasttime))
		end
	end
	
	-- 不同条件触发配置值修改和发送hotkey:

	-- 1. 快捷键手动触发 功能完善 组合按键能确保进入processor三次以上
	--if keyrepr == "Control+apostrophe" then 
	local shortcut_key = schema.config:get_string("horizontal_switch/shortcut_key") or "Control+apostrophe" 
	if keyrepr == shortcut_key then 
		send_hotkey()
		manual = not manual --强制手动控制 防与has_tag冲突
	end
	
	-- 2. has_tag自动触发  小瑕疵 每次切换时第一个字符会暂时不显示

	--local tag = schema.config:get_string("mails/tag") --or 'mails'  --需要自动切换的tag类型
	local tags = schema.config:get_list("horizontal_switch/auto_switch_tags") --ConfigList
	log_error("tags: "..type(tags))
	local tags_size = tags and tags.size or nil 
	log_error("tags_size: "..tostring(tags_size))

	if tags ~= nil and manual == false then 
		local segment = context.composition:back() --当空输入时，segment会是nil
		local has_tag = false
		for i=0, tags.size-1 do
			tag = tags:get_value_at(i):get_string()
			has_tag = segment ~= nil and segment:has_tag(tag) or false  --是否含有tag --此processor放在 - recognizer之后
			log_error("--has tag--: "..tag.."--: "..tostring(has_tag))
			if has_tag == true then break end 
		end 
		
		if has_tag == true then 
			if h_config_state == true -- 当输入法是横向时，识别到tag，切换为竖向
			then
				send_hotkey()
			end
		else --没有tag时恢复
			if h_config_state == false -- 输入法是竖向时，切换回为横向
			then
				i= i+1 -- 控制发送的变量 防止开关界面留置
				if i > 1 then 
				-- 跳过第1次 满足条件没有tag   第一次：旧按键Release，tag消失
				-- 当第二次 满足条件，进入执行 第二次：新按键按下 进入 processor 但暂无法获得context.input，会在Phase2去处理（新按键Release进入processor时）
				-- 若取第三次满足条件，进入执行 第三次：新按键Release，进入此处逻辑，会因无后续按键进入proecessor，依然会造成界面留置。
				-- 所以取一次新按键，两次进入processor完成界面刷新，是最好的方案，但缺点是第一个按键信息会暂时不显示
				send_hotkey()
				end 
			end
		end
	end

	return 2
end

return horizontal_switch



--[[
-- xxx.schema.yaml 对应位置添加配置：

engine:
  processors:
    - lua_processor@*horizontal_switch
style:
  horizontal: true
horizontal_switch:
  shortcut_key: "Control+apostrophe"
  auto_switch_tags: [mails]         #[mails, radical_lookup]

-- 或使用patch：
__patch:
  'engine/processors/@before 3': lua_processor@*horizontal_switch 
  style/horizontal: true                                # 横向展示 默认值
  horizontal_switch/shortcut_key: "Control+apostrophe"  # 手动切换快捷键
  horizontal_switch/auto_switch_tags: [mails]           # 自动切换的tags 非必选项 逗号分割
--]]




