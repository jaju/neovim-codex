local selectors = require("neovim_codex.core.selectors")

local M = {}

local function list_turn_items(turn)
  if type(turn) ~= "table" then
    return {}
  end

  if type(turn.items_order) == "table" and type(turn.items_by_id) == "table" then
    return selectors.list_items(turn)
  end

  if type(turn.items) == "table" then
    return turn.items
  end

  return {}
end

function M.list_turns(thread)
  if type(thread) ~= "table" then
    return {}
  end

  if type(thread.turns_order) == "table" and type(thread.turns_by_id) == "table" then
    return selectors.list_turns(thread)
  end

  if type(thread.turns) == "table" then
    return thread.turns
  end

  return {}
end

function M.compaction_turn_indices(turns)
  local indices = {}

  for index, turn in ipairs(turns or {}) do
    for _, item in ipairs(list_turn_items(turn)) do
      if item.type == "contextCompaction" then
        indices[#indices + 1] = index
        break
      end
    end
  end

  return indices
end

function M.visible_window(turns, opts)
  opts = opts or {}

  local total_turns = #(turns or {})
  local max_turns = math.max(1, tonumber(opts.max_turns) or 18)
  local compaction_indices = M.compaction_turn_indices(turns)
  local start_index = math.max(1, total_turns - max_turns + 1)
  local anchor = "tail"

  if opts.prefer_penultimate_compaction ~= false and #compaction_indices >= 2 then
    start_index = compaction_indices[#compaction_indices - 1]
    anchor = "penultimate_compaction"
  end

  return {
    start_index = start_index,
    end_index = total_turns,
    total_turns = total_turns,
    hidden_turn_count = math.max(0, start_index - 1),
    visible_turn_count = math.max(0, total_turns - start_index + 1),
    anchor = anchor,
    compaction_turn_indices = compaction_indices,
  }
end

function M.compaction_segments(turns)
  local total_turns = #(turns or {})
  if total_turns == 0 then
    return {}
  end

  local indices = M.compaction_turn_indices(turns)
  local segments = {}
  local start_index = 1

  for _, index in ipairs(indices) do
    if index > start_index then
      segments[#segments + 1] = {
        start_index = start_index,
        end_index = index - 1,
        anchor = "history",
      }
    end
    start_index = index
  end

  if start_index <= total_turns then
    segments[#segments + 1] = {
      start_index = start_index,
      end_index = total_turns,
      anchor = #indices > 0 and "compaction" or "history",
    }
  end

  return segments
end

function M.turn_index(turns, turn_id)
  if turn_id == nil then
    return nil
  end

  for index, turn in ipairs(turns or {}) do
    if turn.id == turn_id then
      return index
    end
  end

  return nil
end

return M
