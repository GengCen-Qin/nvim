return {
  "RRethy/vim-illuminate",
  event = "LazyFile", -- 打开文件即加载，不依赖 LSP 附加
  config = function()
    require("illuminate").configure({
      providers = {
        "lsp", -- 优先使用 LSP 识别变量（更精准）
        "treesitter", -- 其次使用 Treesitter
        "regex", -- 最后使用正则匹配
      },
      delay = 200, -- 延迟 200ms 高亮，避免打字时闪烁
    })
  end,
}
