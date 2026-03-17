local M = {}

function M.call(request_fn, opts)
  opts = opts or {}
  local done = false
  local result = nil
  local err_message = nil

  request_fn(function(err, payload)
    done = true
    err_message = err
    result = payload
  end)

  if opts.wait then
    local ok = vim.wait(opts.timeout_ms or 4000, function()
      return done
    end, 50)
    if not ok then
      return nil, "timed out waiting for app-server response"
    end
  end

  return result, err_message
end

function M.options(opts)
  return {
    wait = opts.wait ~= false,
    timeout_ms = opts.timeout_ms,
  }
end

return M
