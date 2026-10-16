return {
  "luckasRanarison/nvim-devdocs",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {},
  keys = {
    { "<leader>dd", "<cmd>DevdocsOpen<CR>", desc = "Search DevDocs" },
    { "<leader>di", "<cmd>DevdocsInstall<CR>", desc = "Install DevDocs" },
    { "<leader>du", "<cmd>DevdocsUpdateAll<CR>", desc = "Update DevDocs" },
    { "<leader>do", "<cmd>DevdocsOpenCurrentFloat<CR>", desc = "Current Language Docs" },
  },
}
