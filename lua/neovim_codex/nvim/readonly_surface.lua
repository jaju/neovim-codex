local M = {}

local function stop_insert()
  pcall(vim.cmd, "stopinsert")
end

local function in_insert_mode()
  local mode = vim.api.nvim_get_mode().mode or ""
  return mode:sub(1, 1) == "i"
end

function M.attach(bufnr, opts)
  opts = opts or {}

  local function target_active()
    if opts.is_target_active then
      return opts.is_target_active() == true
    end
    return true
  end

  local function run_insert_attempt_handler()
    if opts.on_insert_attempt then
      return opts.on_insert_attempt() == true
    end
    return false
  end

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = opts.augroup,
    buffer = bufnr,
    callback = function()
      vim.schedule(function()
        if not target_active() then
          return
        end
        if run_insert_attempt_handler() then
          return
        end
        stop_insert()
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = opts.augroup,
    buffer = bufnr,
    callback = function()
      vim.schedule(function()
        if not target_active() then
          return
        end
        if not in_insert_mode() then
          return
        end
        stop_insert()
      end)
    end,
  })
end

return M
