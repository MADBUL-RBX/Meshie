local UserConfig = {}

UserConfig.VertexSize    = 0.2
UserConfig.EdgeThickness = 0.08

UserConfig.VertexColor = Color3.new(0.298039, 0.752941, 1)
UserConfig.FaceColor   = Color3.new(1, 0.666667, 0)
UserConfig.EdgeColor   = Color3.new(0.4, 1, 0.4)

UserConfig.VertexMaterial = Enum.Material.Neon
UserConfig.FaceMaterial   = Enum.Material.Neon
UserConfig.EdgeMaterial   = Enum.Material.Neon

UserConfig.ToolHotkeys = {
	Transform = "Z",
	Extrude   = "X",
	Bevel     = "C",
	Dissolve  = "V",
}

UserConfig.GeometryModeHotkeys = {
	Vertex = "LeftBracket",
	Edge   = "RightBracket",
	Face   = "BackSlash",
}

UserConfig.BevelTargetVertexColor = Color3.fromRGB(255, 130, 130)
UserConfig.BevelTargetEdgeColor   = Color3.fromRGB(255, 130, 130)
UserConfig.BevelHandleColor       = Color3.fromRGB(255, 255, 255)
UserConfig.BevelHandleMaterial    = Enum.Material.Neon
UserConfig.BevelHandleSize        = Vector3.new(0.28, 0.28, 0.28)
UserConfig.BevelHandleOffset      = 0.4

return UserConfig
