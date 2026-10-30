return {
  dir = vim.fn.stdpath("config") .. "/local-plugin/git-review.nvim",
  keys = {
    {
      "<leader>bb",
      "<cmd>GitReview<cr>",
      desc = "Git Review",
    },
  },
}
