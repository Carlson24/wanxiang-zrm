--@amzxyz https://github.com/amzxyz/rime-wanxiang


local wanxiang = require('wanxiang/wanxiang')

local tone_map = {
  ['ā'] = 'a',
  ['á'] = 'a',
  ['ǎ'] = 'a',
  ['à'] = 'a',
  ['ē'] = 'e',
  ['é'] = 'e',
  ['ě'] = 'e',
  ['è'] = 'e',
  ['ī'] = 'i',
  ['í'] = 'i',
  ['ǐ'] = 'i',
  ['ì'] = 'i',
  ['ō'] = 'o',
  ['ó'] = 'o',
  ['ǒ'] = 'o',
  ['ò'] = 'o',
  ['ň'] = 'n',
  ['ū'] = 'u',
  ['ú'] = 'u',
  ['ǔ'] = 'u',
  ['ù'] = 'u',
  ['ǹ'] = 'n',
  ['ǖ'] = 'ü',
  ['ǘ'] = 'ü',
  ['ǚ'] = 'ü',
  ['ǜ'] = 'ü',
  ['ń'] = 'n',
}

local letter_preedit_map = {
  ["A"] = "𝙰",
  ["B"] = "𝙱",
  ["C"] = "𝙲",
  ["D"] = "𝙳",
  ["E"] = "𝙴",
  ["F"] = "𝙵",
  ["G"] = "𝙶",
  ["H"] = "𝙷",
  ["I"] = "𝙸",
  ["J"] = "𝙹",
  ["K"] = "𝙺",
  ["L"] = "𝙻",
  ["M"] = "𝙼",
  ["N"] = "𝙽",
  ["O"] = "𝙾",
  ["P"] = "𝙿",
  ["Q"] = "𝚀",
  ["R"] = "𝚁",
  ["S"] = "𝚂",
  ["T"] = "𝚃",
  ["U"] = "𝚄",
  ["V"] = "𝚅",
  ["W"] = "𝚆",
  ["X"] = "𝚇",
  ["Y"] = "𝚈",
  ["Z"] = "𝚉",
}

local tone_preedit_map = {
  ['6'] = '①',
  ['7'] = '②',
  ['8'] = '③',
  ['9'] = '④',
}

-- ----------------------
-- # 错音错字提示模块
-- ----------------------
local CR = {}
local corrections_cache = nil -- 用于缓存已加载的词典
local cached_dict_path = nil  -- 记录当前缓存的词典路径

function CR.init(env)
  -- 动态获取样式，因为配置可能在运行时被修改，所以这个不放进缓存拦截里
  CR.style = env.settings.corrector_type or '{comment}'

  local auto_delimiter = env.settings.auto_delimiter
  local path = "dicts/cuoyin.pro.dict.yaml"
  -- 如果缓存已经存在，并且文件路径没变，直接返回，不再读盘
  if corrections_cache and cached_dict_path == path then
    return
  end

  local file, close_file, err = wanxiang.load_file_with_fallback(path)
  if not file then
    log.error(string.format("[super_comment]: 加载失败 %s，错误: %s", path, err))
    return
  end

  corrections_cache = {}
  for line in file:lines() do
    if not line:match("^#") then
      local text, code, weight, comment = line:match("^(.-)\t(.-)\t(.-)\t(.-)$")
      if text and code then
        text = text:match("^%s*(.-)%s*$")
        code = code:match("^%s*(.-)%s*$")
        comment = comment and comment:match("^%s*(.-)%s*$") or ""
        comment = comment:gsub("%s+", auto_delimiter)
        code = code:gsub("%s+", auto_delimiter)
        corrections_cache[code] = { text = text, comment = comment }
      end
    end
  end
  close_file()

  -- 记录本次成功加载的文件路径
  cached_dict_path = path
end

function CR.get_comment(cand)
  local correction = corrections_cache and corrections_cache[cand.comment] or nil
  if not (correction and cand.text == correction.text) then
    return nil
  end
  -- 只认占位符 `comment`，按“刀法”切分
  local tpl = CR.style or "comment"
  local left, right = tpl:match("^(.-)comment(.-)$")

  if left then
    return left .. correction.comment .. right
  else
    return correction.comment
  end
end

-- ----------------------
-- 部件组字返回的注释
-- ----------------------
local function get_charset_label(text)
  if not text or text == "" then return nil end
  local cp = utf8.codepoint(text)
  if not cp then return nil end

  -- 按照 Unicode 区块频率排序
  if cp >= 0x4E00 and cp <= 0x9FFF then return "基本" end
  if cp >= 0x3400 and cp <= 0x4DBF then return "扩A" end
  if cp >= 0x20000 and cp <= 0x2A6DF then return "扩B" end
  if cp >= 0x2A700 and cp <= 0x2B73F then return "扩C" end
  if cp >= 0x2B740 and cp <= 0x2B81F then return "扩D" end
  if cp >= 0x2B820 and cp <= 0x2CEAF then return "扩E" end
  if cp >= 0x2CEB0 and cp <= 0x2EBEF then return "扩F" end
  if cp >= 0x2EBF0 and cp <= 0x2EE5F then return "扩I" end
  if cp >= 0x30000 and cp <= 0x3134F then return "扩G" end
  if cp >= 0x31350 and cp <= 0x323AF then return "扩H" end

  -- 兼容区
  if cp >= 0xF900 and cp <= 0xFAFF then return "兼容" end
  if cp >= 0x2F800 and cp <= 0x2FA1F then return "兼容" end

  return nil
end

local function get_az_comment(cand, env, initial_comment)
  local inner_parts = {}

  -- 音形注释拆解逻辑
  if initial_comment and initial_comment ~= "" then
    local segments = {}
    for segment in string.gmatch(initial_comment, "[^%s]+") do
      table.insert(segments, segment)
    end

    if #segments > 0 then
      local semicolon_count = select(2, string.gsub(segments[1], ";", ""))
      local pinyins = {}
      local fuzhu = nil

      for _, segment in ipairs(segments) do
        local pinyin = string.match(segment, "^[^;~]+")
        local fz = nil

        if semicolon_count == 1 then
          fz = string.match(segment, ";(.+)$")
        end

        if pinyin then
          table.insert(pinyins, pinyin)
        end
        if not fuzhu and fz and fz ~= "" then fuzhu = fz end
      end

      if #pinyins > 0 then
        local pinyin_str = table.concat(pinyins, ",")
        table.insert(inner_parts, string.format("音%s", pinyin_str))

        if fuzhu then
          table.insert(inner_parts, string.format("辅%s", fuzhu))
        end
      end
    end
  end

  if cand and cand.text then
    local label = get_charset_label(cand.text)
    if label then
      table.insert(inner_parts, label)
    end
  end

  if #inner_parts == 0 then
    return "〔无〕"
  end
  -- 使用间隔号连接
  return "〔" .. table.concat(inner_parts, "・") .. "〕"
end
-- ----------------------
-- # 辅助码提示或带调全拼注释模块 (Fuzhu)
-- ----------------------
local function get_fz_comment(cand, env, initial_comment)
  local length = utf8.len(cand.text)
  if length > env.settings.candidate_length then
    return ""
  end
  local auto_delimiter = env.settings.auto_delimiter or " "
  local segments = {}
  for segment in string.gmatch(initial_comment, "[^" .. auto_delimiter .. "]+") do
    table.insert(segments, segment)
  end

  -- 根据 option 动态决定是否强制使用 tone
  local use_tone = env.engine.context:get_option("tone_hint") or env.engine.context:get_option("toneless_hint")
  local fuzhu_type = use_tone and "tone" or "fuzhu"

  local first_segment = segments[1] or ""
  local semicolon_count = select(2, first_segment:gsub(";", ""))
  local fuzhu_comments = {}
  -- 没有分号的情况
  if semicolon_count == 0 then
    return initial_comment:gsub(auto_delimiter, " ")
  else
    -- 有分号：按类型提取
    for _, segment in ipairs(segments) do
      if fuzhu_type == "tone" then
        -- 取第一个分号“前”的内容
        local before = segment:match("^(.-);")
        if before and before ~= "" then
          table.insert(fuzhu_comments, before)
        end
      else -- "fuzhu"
        -- 取第一个分号“后”的内容（到行尾）
        local after = segment:match(";(.+)$")
        if after and after ~= "" then
          table.insert(fuzhu_comments, after)
        end
      end
    end
  end

  -- 最终拼接输出，fuzhu用 `,`，tone用 /连接
  if #fuzhu_comments > 0 then
    if fuzhu_type == "tone" then
      return table.concat(fuzhu_comments, " ")
    else
      return table.concat(fuzhu_comments, "/")
    end
  else
    return ""
  end
end

-- 对 cand.preedit 应用 tone_preedit/0..9 的映射（数字 -> 上标等）
-- 对 cand.preedit 应用转换：数字转上标，且隐藏双大写辅助码
local function apply_tone_preedit(env, cand)
  if not cand or not cand.preedit or cand.preedit == "" then return end

  local engine = env.engine
  local ctx = engine and engine.context
  local input = ctx and ctx.input or ""

  -- 如果包含连续数字（如电脑小键盘），直接跳过不转换
  if input:match("%d%d") then return end

  -- 判断首选是否为纯英文（通过匹配是否全由英文字符组成且不含中文）
  if cand.text:match("^[%a%p%s]+$") then return end

  local converted = cand.preedit
  -- 排除前两位是大写的情况，只转换后续出现的双大写
  -- ([A-Z][A-Z]+) 匹配后续连续的两个及以上的大写字母。
  converted = converted:gsub("^(..?-?)([A-Z][A-Z]+)", function(prefix, upper)
    -- 检查前缀是否包含大写字母。如果前缀里有大写，说明可能是英文输入，不转换。
    if prefix:match("[A-Z]") then
      return prefix .. upper
    else
      return prefix .. "›" -- 使用一个特殊符号（如›）来占位，表示这里有双大写被隐藏了
    end
  end)

  -- 处理非行首（音节中间或靠后）的双大写
  -- 比如 "nihaoWS" -> "nihao·"
  converted = converted:gsub("([^%s%^])([A-Z][A-Z]+)", function(prev)
    return prev .. "›" -- 同样使用特殊符号占位
  end)

  converted = converted:gsub("([^%s%^])([A-Z]+)", function(prev, upper)
    return prev .. letter_preedit_map[upper] or upper
  end)

  converted = converted:gsub("([^%d%s]+)(%d+)", function(body, digits)
    local mapped = digits:gsub("%d", function(d)
      return tone_preedit_map[d] or d
    end)
    return body .. mapped
  end)

  cand.preedit = converted
end

-- ----------------------
-- 主函数：根据优先级处理候选词的注释和preedit
-- ----------------------
local ZH = {}
function ZH.init(env)
  local config = env.engine.schema.config
  local delimiter = config:get_string('speller/delimiter') or " '"
  local auto_delimiter = delimiter:sub(1, 1)
  local manual_delimiter = delimiter:sub(2, 2)
  env.settings = {
    delimiter = delimiter,
    auto_delimiter = auto_delimiter,
    manual_delimiter = manual_delimiter,
    corrector_enabled = config:get_bool("super_comment/corrector") or true,
    corrector_type = config:get_string("super_comment/corrector_type") or "{comment}",
    candidate_length = tonumber(config:get_string("super_comment/candidate_length")) or 1,
  }

  CR.init(env)
end

function ZH.fini(env)
end

function ZH.func(input, env)
  local context = env.engine.context
  local input_str = context.input or ""
  local is_radical_mode = wanxiang.is_in_radical_mode(env)
  local should_skip_candidate_comment = wanxiang.is_function_mode_active(context) or input_str == ""
  local is_tone_comment = env.engine.context:get_option("tone_hint")
  local is_comment_hint = env.engine.context:get_option("fuzhu_hint")

  for cand in input:iter() do
    local genuine_cand = cand:get_genuine()
    if genuine_cand.type == "shijian" then
      yield(genuine_cand)
      goto continue
    end
    local initial_comment = genuine_cand.comment
    local final_comment = initial_comment
    if should_skip_candidate_comment then
      yield(genuine_cand)
      goto continue
    end
    apply_tone_preedit(env, genuine_cand)
    -- 进入注释处理阶段
    -- ① 辅助码注释或者声调注释
    if initial_comment and (string.find(initial_comment, "~") or string.find(initial_comment, "\226\152\175") or cand.type == "shijian" or cand.type == "cnen") then
      final_comment = initial_comment

      -- 2. 常规的辅助码提示模式
    elseif is_comment_hint then
      local fz_comment = get_fz_comment(cand, env, initial_comment)
      if fz_comment then
        final_comment = fz_comment
      end

      -- 3. 常规的带调拼音模式
    elseif is_tone_comment then
      local fz_comment = get_fz_comment(cand, env, initial_comment)
      if fz_comment then
        final_comment = fz_comment
      end

      -- 5. 其他情况一律清空注释
    else
      final_comment = ""
    end

    -- ② 错音错字提示
    if env.settings.corrector_enabled then
      local cr_comment = CR.get_comment(cand)
      if cr_comment and cr_comment ~= "" then
        final_comment = cr_comment
      end
    end

    -- ③ 反查模式提示
    if is_radical_mode then
      local az_comment = get_az_comment(cand, env, initial_comment)
      if az_comment and az_comment ~= "" then
        final_comment = az_comment
      end
    end

    -- 应用注释
    if final_comment ~= initial_comment then
      genuine_cand.comment = final_comment
    end

    yield(genuine_cand)
    ::continue::
  end
end

return ZH
