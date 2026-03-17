local M = {}

local function resolve_opts(opts)
  return opts or {}
end

function M.select_sync(items, opts)
  local choice = nil
  local finished = false
  vim.ui.select(items, resolve_opts(opts), function(item)
    choice = item
    finished = true
  end)
  vim.wait(10000, function()
    return finished
  end, 20)
  return choice
end

function M.input_sync(opts)
  local value = nil
  local finished = false
  vim.ui.input(resolve_opts(opts), function(input)
    value = input
    finished = true
  end)
  vim.wait(10000, function()
    return finished
  end, 20)
  return value
end

function M.select_async(items, opts, on_choice)
  vim.schedule(function()
    vim.ui.select(items, resolve_opts(opts), function(item)
      vim.schedule(function()
        on_choice(item)
      end)
    end)
  end)
end

function M.input_async(opts, on_input)
  vim.schedule(function()
    vim.ui.input(resolve_opts(opts), function(input)
      vim.schedule(function()
        on_input(input)
      end)
    end)
  end)
end

return M
