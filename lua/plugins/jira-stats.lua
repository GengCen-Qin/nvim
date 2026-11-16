return {
	dir = "/home/lucas/RubyProjects/jira-stats.nvim",
	name = "jira-stats.nvim",
	cmd = "JiraStats",
	keys = {
		{ "<leader>sd", "<cmd>JiraStats<cr>", desc = "Jira Sprint 统计" },
	},
	opts = { project = "GI", timezone = "Asia/Shanghai" },
	config = function(_, opts)
		require("jira-stats").setup(opts)
	end,
}
