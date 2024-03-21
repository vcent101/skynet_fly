local setmetatable = setmetatable
local pairs = pairs

local M = {}
local mata = {
    __index = M,
}

-- 新建条目数据
function M:new(ormtab, entry_data)
    local t = {
        _ormtab = ormtab,
        _entry_data = entry_data,
        _change_map = {},                    --变更的条目
    }
    
    setmetatable(t, mata)
    return t
end

--新增无效条目数据 用于防止缓存穿透
function M:new_invaild(entry_data)
    local t = {
        _entry_data = entry_data,
        _invaild = true,
    }
    
    setmetatable(t, mata)
    return t
end

-- 获取条目数据的值
function M:get(filed_name)
    return self._entry_data[filed_name]
end

-- 修改条目数据的值
function M:set(filed_name, filed_value)
    if filed_value == self._entry_data[filed_name] then return end
    local ormtab = self._ormtab
    ormtab:check_one_filed(filed_name, filed_value)
    self._entry_data[filed_name] = filed_value
    self._change_map[filed_name] = true      --标记变更
    ormtab:set_change_entry(self)
end

-- 获取数据表
function M:get_entry_data()
    return self._entry_data
end

-- 获取修改条目
function M:get_change_map()
    return self._change_map
end

-- 清除变更标记
function M:clear_change()
    local change_map = self._change_map
    for filed_name in pairs(change_map) do
        change_map[filed_name] = nil
    end
end

--是否无效条目
function M:is_invaild()
    return self._invaild
end

return M