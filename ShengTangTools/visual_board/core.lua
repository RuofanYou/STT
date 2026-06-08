local T, C, L = unpack(select(2, ...))
do

local VisualBoard = {}
T.VisualBoard = VisualBoard

VisualBoard.initialized = false

function VisualBoard:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true

end

function VisualBoard:GetBoards()
    if not (T.VisualBoardData and T.VisualBoardData.GetAllBoards) then
        return {}
    end
    return T.VisualBoardData:GetAllBoards()
end

function VisualBoard:CreateBoard(name)
    if not (T.VisualBoardData and T.VisualBoardData.CreateBoard) then
        return nil
    end
    return T.VisualBoardData:CreateBoard(name)
end

function VisualBoard:DeleteBoard(id)
    if not (T.VisualBoardData and T.VisualBoardData.DeleteBoard) then
        return false, "data_unavailable"
    end
    return T.VisualBoardData:DeleteBoard(id)
end

if T.RegisterInitCallback then
    T.RegisterInitCallback(function()
        VisualBoard:Initialize()
    end)
end

end
