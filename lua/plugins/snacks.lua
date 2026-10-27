-- snacks picker 配置
--
-- 查找时不想看的代码文件扩展名（字面匹配，无正则）。
-- <leader><leader> 找文件 / 全局搜索默认都走 snacks；本表同时被 telescope.lua
-- （<leader>/ 自定义全局搜索）引用，保证各处过滤一致。
local exclude = {
  "*.cpp",
  "*.cc",
  "*.cxx",
  "*.hpp",
  "*.h",
  "*.js",
  "*.mjs",
  "*.ts",
  "*.cs",
  "*.csproj",
}

-- 供其它插件文件复用（telescope.lua 用它拼 --glob=!xxx）
_G.nvim_files_exclude = exclude

return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        files = {
          exclude = exclude,
        },
        grep = {
          exclude = exclude,
        },
      },
    },
  },
}
