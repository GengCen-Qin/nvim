-- snacks picker 配置
--
-- 查找时不想看的代码文件/目录（字面匹配，无正则，目录名整目录排除）。
-- <leader><leader> 找文件、<leader>/ 全局搜索（见 keymaps.lua，regex=false 即字面匹配）
-- 统一都走 snacks.picker，exclude 只在这里维护一份。
local exclude = {
  "cpp", -- 整个 cpp/ 目录（其下还有 .sln/.vcxproj/Makefile 等非源码文件）
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
