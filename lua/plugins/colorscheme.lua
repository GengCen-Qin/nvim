-- 注释统一为暗红色（改这里即可调整色值）
local COMMENT_FG = "#EA999C"

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
