local Common = require("mocks.wow_api_common")

local M = {}

function M.new()
    return {
        make_frame = Common.make_frame,
        deep_copy = Common.deep_copy,
    }
end

return M
