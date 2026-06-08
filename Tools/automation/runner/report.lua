local M = {}

function M.new_reporter()
    local self = {
        total = 0,
        passed = 0,
        failed = 0,
        details = {},
    }

    function self:add(result)
        self.total = self.total + 1
        if result.ok then
            self.passed = self.passed + 1
        else
            self.failed = self.failed + 1
        end
        self.details[#self.details + 1] = result
    end

    function self:print_summary()
        print(string.format("[Automation] 总计=%d, 通过=%d, 失败=%d", self.total, self.passed, self.failed))
        for _, item in ipairs(self.details) do
            local status = item.ok and "PASS" or "FAIL"
            print(string.format("[%s] %s", status, item.case_id))
            if not item.ok and item.message and item.message ~= "" then
                print("  " .. item.message:gsub("\n", "\n  "))
            end
        end
    end

    return self
end

return M
