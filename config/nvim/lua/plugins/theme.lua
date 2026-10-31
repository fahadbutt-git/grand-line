-- Neovim takes its colour scheme from the active package theme (theme pick),
-- with a see-through background so it always sits on the terminal's colour.
local f = io.open(vim.fn.expand("~/.local/state/mac-setup/nvim-theme"))
local scheme = f and f:read("*l") or "vscode"
if f then f:close() end

local by_theme = {
  ["vscode"] = { "Mofiqul/vscode.nvim", opts = { transparent = true } },
  ["nord"] = { "gbprod/nord.nvim", opts = { transparent = true } },
  ["everforest"] = { "neanias/everforest-nvim", main = "everforest", opts = { transparent_background_level = 1 } },
  ["rose-pine-dawn"] = { "rose-pine/neovim", name = "rose-pine", opts = { variant = "dawn", styles = { transparency = true } } },
}

if not by_theme[scheme] then scheme = "vscode" end
-- All four are installed up front, so switching theme never waits on a
-- download; only the active one loads.
local specs = {}
for name, spec in pairs(by_theme) do
  spec.lazy = name ~= scheme
  spec.priority = 1000
  table.insert(specs, spec)
end
table.insert(specs, { "LazyVim/LazyVim", opts = { colorscheme = scheme } })
return specs
