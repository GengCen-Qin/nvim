-- ctags-lsp: Ruby 定义跳转 / 符号搜索（基于 universal-ctags）
--
-- 用 mason 装的 ctags-lsp 绝对路径，避免解析到 PATH 里那个
-- /mnt/c/.../mise/shims/ctags-lsp（Windows 侧坏 shim，会超时挂起 nvim）。
-- 只对 ruby 启用，并限制 ctags 语言为 Ruby，避免扫描仓库内 cpp 等拖慢启动。
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ctags_lsp = {
          cmd = {
            vim.fn.stdpath("data") .. "/mason/bin/ctags-lsp",
            "--languages=Ruby",
          },
          filetypes = { "ruby" },
          -- 只在 ruby 下 attach；root 用仓库根（.git 等）
        },
      },
    },
  },
}
