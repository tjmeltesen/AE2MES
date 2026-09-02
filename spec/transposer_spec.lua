local mock_oc = require("mock_oc")
mock_oc.reset()

local TransposerComponent

describe("TransposerComponent inventory", function()
    before_each(function()
        mock_oc.reset()
        package.loaded["TransposerComponent"] = nil
        package.loaded["BaseComponent"] = nil
        package.loaded["ComponentLibrary"] = nil
        TransposerComponent = require("TransposerComponent")
    end)

    it("drains every stack via getAllStacks and transferItem", function()
        local transfers = {}

        mock_oc.override_component_proxy(function(address, proxy)
            if address ~= "trans-1" then
                return proxy
            end

            proxy.getAllStacks = function(_, side)
                if side == 3 then
                    return {
                        { name = "minecraft:iron_ingot", label = "Iron Ingot", size = 16 },
                        { name = "minecraft:glass", label = "Glass", size = 8 },
                    }
                end
                return {}
            end

            proxy.transferItem = function(_, fromSide, toSide, count)
                table.insert(transfers, { from = fromSide, to = toSide, count = count })
                return count
            end

            return proxy
        end)

        local transposer = TransposerComponent:new("trans-1")
        local total, err = transposer:drainInventory(3, 2)

        assert.is_nil(err)
        assert.are.equal(24, total)
        assert.are.equal(2, #transfers)
        assert.are.equal(3, transfers[1].from)
        assert.are.equal(2, transfers[1].to)
        assert.are.equal(16, transfers[1].count)
        assert.are.equal(8, transfers[2].count)
    end)

    it("builds inventory contents from getAllStacks arrays", function()
        mock_oc.override_component_proxy(function(address, proxy)
            if address ~= "trans-2" then
                return proxy
            end

            proxy.getAllStacks = function()
                return {
                    { name = "minecraft:stone", label = "Stone", size = 5, maxSize = 64 },
                }
            end

            return proxy
        end)

        local transposer = TransposerComponent:new("trans-2")
        local contents = transposer:getInventoryContents(2)

        assert.are.equal(1, #contents)
        assert.are.equal(1, contents[1].slot)
        assert.are.equal("minecraft:stone", contents[1].name)
        assert.are.equal("Stone", contents[1].label)
        assert.are.equal(5, contents[1].size)
        assert.are.equal(64, contents[1].maxSize)
    end)

    it("unwraps stackSlot objects that expose getAll()", function()
        mock_oc.override_component_proxy(function(address, proxy)
            if address ~= "trans-3" then
                return proxy
            end

            proxy.getAllStacks = function()
                return {
                    getAll = function()
                        return {
                            { name = "minecraft:dirt", label = "Dirt", size = 3 },
                        }
                    end,
                }
            end

            proxy.transferItem = function(_, _, _, count)
                return count
            end

            return proxy
        end)

        local transposer = TransposerComponent:new("trans-3")
        local total = transposer:drainInventory(1, 2)

        assert.are.equal(3, total)
    end)
end)
