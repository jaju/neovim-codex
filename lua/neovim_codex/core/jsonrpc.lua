local M = {}

local Decoder = {}
Decoder.__index = Decoder

function Decoder:new(opts)
  assert(opts and opts.json, "json codec is required")
  return setmetatable({
    json = opts.json,
    buffer = "",
  }, self)
end

function Decoder:push(chunk)
  if not chunk or chunk == "" then
    return {}, nil
  end

  self.buffer = self.buffer .. chunk
  local messages = {}

  while true do
    local newline = self.buffer:find("\n", 1, true)
    if not newline then
      break
    end

    local line = self.buffer:sub(1, newline - 1)
    self.buffer = self.buffer:sub(newline + 1)

    if line ~= "" then
      local ok, decoded = pcall(self.json.decode, line)
      if not ok then
        return messages, string.format("failed to decode json-rpc line: %s", decoded)
      end
      table.insert(messages, decoded)
    end
  end

  return messages, nil
end

function M.new_decoder(opts)
  return Decoder:new(opts)
end

function M.encode_request(json, id, method, params)
  return json.encode({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params,
  }) .. "\n"
end

function M.encode_notification(json, method, params)
  local message = {
    jsonrpc = "2.0",
    method = method,
  }
  if params ~= nil then
    message.params = params
  end
  return json.encode(message) .. "\n"
end

function M.encode_response(json, id, result)
  return json.encode({
    jsonrpc = "2.0",
    id = id,
    result = result,
  }) .. "\n"
end

return M
