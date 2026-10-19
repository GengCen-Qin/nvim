-- 注释统一为暗红色（改这里即可调整色值）
local COMMENT_FG = "#EA999C"

-- 窗口分隔线（改这里即可调整色值）
-- catppuccin-frappe 默认把 WinSeparator 设成 crust(#232634)，比背景 base(#303446)
-- 还暗，分割线几乎看不见；<C-/> 开出的终端分屏与代码区因此糊成一片，边界难认。
-- 这里改成粉红色 + bold，一眼分清边界。
local WINSEPARATOR_FG = "#f4b8e4" -- catppuccin pink

-- 竖直分隔线字符：默认 │ (细线) 太细，换成 ▌ (左半实心块)，加粗更明显。
-- 改这里即可换成别的字符，如 "┃"(粗竖线) / "▏"(细右半块)。宽度固定 1 列，主题需要支持宽字符。
local WINSEPARATOR_VERT = "▌"

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("UserCommentColor", { clear = true }),
  callback = function()
    for _, group in ipairs({
      "Comment",
      "@comment",
      "@comment.documentation",
      "@comment.error",
      "@comment.warning",
      "@comment.note",
      "@comment.todo",
      "@comment.debug",
      "@lsp.type.comment",
    }) do
      vim.api.nvim_set_hl(0, group, { fg = COMMENT_FG })
    end

    vim.api.nvim_set_hl(0, "WinSeparator", { fg = WINSEPARATOR_FG, bold = true })

    -- fillchars 的 vert 控制竖直分隔线用什么字符；它在 options 里也会被设置，
    -- 这里放在 ColorScheme 里再设一遍，保证换主题后依然是加粗的 ▌。
    vim.opt.fillchars:append({ vert = WINSEPARATOR_VERT })
  end,
})

return {
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-frappe",
    },
  },
}
