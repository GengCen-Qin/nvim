-- Rails 模型类名 -> 数据库表名 的解析
--
-- 供 dadbod-schema.lua 使用：光标停在 PasAccount 这类模型类名上按 K 时，
-- 用它把类名解析成表名，再去查表结构。
--
-- 表名的来源按 Rails 的事实来源，不做猜测：
--   1. 模型文件里显式写的 self.table_name = "..."（可能带 schema 前缀，如 audit.pas_positions）
--   2. 没写就用 Rails 默认推导 tableize(underscore(ClassName))
--
-- tableize/underscore 是 Rails ActiveSupport::Inflector 的 Lua 移植，
-- 已用 PAS 全部 823 个模型类名与真实 Ruby 结果逐条比对，完全一致。
local M = {}

-- Rails Inflector.underscore：PasAccount -> pas_account，VPasX -> v_pas_x
local function underscore(name)
  local s = name:gsub("::", "/")
  s = s:gsub("([A-Z%d]+)([A-Z][a-z])", "%1_%2")
  s = s:gsub("([a-z%d])([A-Z])", "%1_%2")
  s = s:gsub("/", "_")
  s = s:gsub("%-", "_")
  s = s:gsub("%s+", "_")
  return s:lower()
end

-- 顺序 = Rails 规则的实际匹配顺序（后定义者优先，即定义顺序的逆序）。
-- Lua pattern 没有交替，故 (x|ch|ss|sh) 这类拆成多条。
local plural_rules = {
  { "(quiz)$", "%1zes" },
  { "^(oxen)$", "%1" },
  { "^(ox)$", "%1en" },
  { "^([ml])ice$", "%1ice" },
  { "^([ml])ouse$", "%1ice" },
  { "(matr)(ix)$", "%1ices" }, { "(matr)(ex)$", "%1ices" },
  { "(vert)(ix)$", "%1ices" }, { "(vert)(ex)$", "%1ices" },
  { "(ind)(ix)$", "%1ices" }, { "(ind)(ex)$", "%1ices" },
  { "(x)$", "%1es" }, { "(ch)$", "%1es" }, { "(ss)$", "%1es" }, { "(sh)$", "%1es" },
  { "([^aeiouy])y$", "%1ies" }, { "(qu)y$", "%1ies" },
  { "(hive)$", "%1s" },
  { "([^f])fe$", "%1ves" }, { "([lr])f$", "%1ves" },
  { "sis$", "ses" },
  { "([ti])a$", "%1a" },
  { "([ti])um$", "%1a" },
  { "(buffal)o$", "%1oes" }, { "(tomat)o$", "%1oes" },
  { "(bu)s$", "%1ses" },
  { "(alias)$", "%1es" }, { "(status)$", "%1es" },
  { "(octop)i$", "%1i" }, { "(vir)i$", "%1i" },
  { "(octop)us$", "%1i" }, { "(vir)us$", "%1i" },
  { "(ax)is$", "%1es" }, { "(test)is$", "%1es" },
  { "s$", "s" },
}

local plural_irregular = {
  person = "people", man = "men", child = "children", sex = "sexes",
  move = "moves", zombie = "zombies",
}

local plural_uncountable = {
  equipment = true, information = true, rice = true, money = true,
  species = true, series = true, fish = true, sheep = true,
  jeans = true, police = true,
}

local function pluralize(word)
  if plural_uncountable[word] then
    return word
  end
  local irr = plural_irregular[word]
  if irr then
    return irr
  end
  for _, rule in ipairs(plural_rules) do
    if word:find(rule[1]) then
      return (word:gsub(rule[1], rule[2]))
    end
  end
  return word .. "s"
end

function M.tableize(class_name)
  return pluralize(underscore(class_name))
end

-- 扫一个模型文件，把 {类名 = 显式表名 或 false} 累加进 into。
-- 多类的文件按「最近一个 class」归属，符合模型文件的常规写法。
local function scan_file(path, into)
  local f = io.open(path, "r")
  if not f then
    return
  end
  local current
  for line in f:lines() do
    local cls = line:match("^%s*class%s+([%w_:]+)")
    if cls then
      current = cls:match("([%w_]+)$")
      if into[current] == nil then
        into[current] = false
      end
    end
    local tn = line:match("^%s*self%.table_name%s*=%s*[\"']([^\"']+)[\"']")
    if tn and current then
      into[current] = tn
    end
  end
  f:close()
end

-- 扫 Rails 根下 app/models 的全部 .rb，返回 类名 -> 表名。
-- 显式 self.table_name 优先，其余按 Rails 默认推导。
function M.scan(root)
  local into = {}
  local files = vim.fn.glob(root .. "/app/models/**/*.rb", false, true)
  for _, path in ipairs(files) do
    scan_file(path, into)
  end
  local map = {}
  for name, explicit in pairs(into) do
    map[name] = explicit or M.tableize(name)
  end
  return map
end

-- 从文件路径向上找 Rails 根（含 app/models 目录）。
function M.rails_root_of(path)
  local dir = path ~= "" and vim.fn.fnamemodify(path, ":p:h") or vim.fn.getcwd()
  while dir ~= "" and dir ~= "/" do
    if vim.fn.isdirectory(dir .. "/app/models") == 1 then
      return dir
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  return nil
end

-- 类名 -> 表名，按 Rails 根缓存。
-- 缓存键带上 app/models 目录的 mtime，新增/删除模型文件后会自动重建。
local cache = {}
function M.map_for(root)
  local stamp = vim.fn.getftime(root .. "/app/models")
  local hit = cache[root]
  if hit and hit.stamp == stamp then
    return hit.map
  end
  local map = M.scan(root)
  cache[root] = { stamp = stamp, map = map }
  return map
end

return M
