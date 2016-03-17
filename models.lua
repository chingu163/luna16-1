modelLayers = require "modelLayers"

models = {}

function miniNetwork()
	local model = nn.Sequential()
	--nFiltersInc = 32 
	nFiltersInc = 42 
	nFilters = {1,nFiltersInc,nFiltersInc*2,nFiltersInc*3,nFiltersInc*4}
	filterSizeConv = {3,3,3,3,3}
	strideConv = {1,1,1,1,1}
	paddingConv = {1,1,1,1,1}

	sizeMP = {3,3,3,3,3}
	strideMP = {2,2,2,2,2}
	paddingMP = {1,1,1,1,1}

	model = nn.Sequential()

	layerNu = 2 
	modelLayers.addBN(model, 1, 1)
	--model:add(nn.VolumetricConvolution(1,1,2,2,2,1,1,1,0,0,0))
	for i = 1,3 do 

		modelLayers.add3DConv(model, layerNu, nFilters, filterSizeConv, strideConv, paddingConv,0)
		--[[
		modelLayers.addBN(model, layerNu, nFilters)
		modelLayers.add3DConv(model, layerNu, nFilters, filterSizeConv, strideConv, paddingConv,1)
		]]--
		--
		--model:add(nn.ReLU())
		--model:add(nn.PReLU())
		model:add(nn.Tanh())
		modelLayers.addMP(model, layerNu, sizeMP, strideMP, paddingMP)
		modelLayers.addBN(model, layerNu, nFilters)
		layerNu = layerNu + 1
	end
	lastLayerNeurons = nFiltersInc*3*3*3*3
	model:add(nn.View(lastLayerNeurons))
	--model:add(nn.Linear(lastLayerNeurons,lastLayerNeurons))
	model:add(nn.Linear(lastLayerNeurons,1))
	return model
end

function models.parallelNetwork()

	-- Seperate networks all take same input size
	--- |  |  |
	--  \  |  /
	--   \ | /
	--     |   (concat)
	--   output 
	
	-- Seperate (mini) network architecture
	-- Parallel Table forwards the ith member module to the i-th input i.e. we need to feed it a table of size 3 in this case
	model = nn.Sequential()
	mother = nn.ParallelTable(3)	
	mother:add(miniNetwork())	
	mother:add(miniNetwork())	
	mother:add(miniNetwork())	
	model:add(mother)
	model:add(nn.JoinTable(1))
	--[[
	model:add(nn.Linear(3,10))
	model:add(nn.Normalize(2))
	model:add(nn.Tanh())
	model:add(nn.Linear(10,3))
	model:add(nn.Normalize(2))
	model:add(nn.Tanh())
	--]]
	model:add(nn.Linear(3,1))
	model:add(nn.Sigmoid())
	return model 

end
return models
