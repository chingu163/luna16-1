require "nn"
require "cunn"
require "cutorch"
require "optim"
require "torch"
require "xlua"
require "gnuplot"
threads = require "threads"
dofile("imageCandidates.lua")
dofile("3dInterpolation3.lua")
dofile("getBatch.lua")
dofile("binaryAccuracy.lua")
models = require "models"
shuffle = require "shuffle"

------------------------------------------ GLobal vars/params -------------------------------------------
cmd = torch.CmdLine()
cmd:text()
cmd:text()
cmd:text('Options')
cmd:option('-lr',0.00002,'Learning rate')
cmd:option('-momentum',0.95,'Momentum')
cmd:option('-batchSize',1,'batchSize')
cmd:option('-cuda',1,'CUDA')
cmd:option('-sliceSize',36,"Length size of cube around nodule")
cmd:option('-angleMax',0.5,"Absolute maximum angle for rotating image")
cmd:option('-scalingFactor',0.75,'Scaling factor for image')
cmd:option('-clipMin',-1200,'Clip image below this value to this value')
cmd:option('-clipMax',1200,'Clip image above this value to this value')
cmd:option('-useThreads',0,"Use threads or not") 
cmd:option('-display',0,"Display images/plots") 
cmd:option('-activations',0,"Show activations -- needs -display 1") 
cmd:option('-log',0,"Make log file in /Results/") 
cmd:option('-train',0,'Train straight away')
cmd:option('-test',0,"Test") 
cmd:option('-loadModel',0,"Load model") 
cmd:option('-para',1,"Are we using a parallel network? If bigger than 0 then this is equal to number of inputs. Otherwise input number is 1.") 
cmd:option('-nInputScalingFactors',3,"Number of input scaling factors.") 
-- K fold cv options
cmd:option('-kFold',1,"Are we doing k fold? Default is to train on subsets 1-9 and test on subset0") 
cmd:option('-fold',0,"Which fold to NOT train on") 
--cmd:option('-loadModel',"model1.model","Load model") 
cmd:text()
params = cmd:parse(arg)
params.model = model
params.rundir = cmd:string('results', params, {dir=true})


-------------------------------------------- Model ---------------------------------------------------------
modelName = "/models/para1.model"
model = models.parallelNetwork()
print("Model == >",model)
print("==> Parameters",params)

-------------------------------------------- Criterion & Activations ----------------------------------------
criterion = nn.MSECriterion()
--criterion = nn.BCECriterion()

if params.log == 1 then  -- Log file
	local logPath = "results/"..params.rundir
	paths.mkdir(logPath)
	logger = optim.Logger(logPath.. '/results.log') 
end

--Show activations need first n layers
if params.activations == 1 then
	modelActivations1 = nn.Sequential()
	for i=1,3 do modelActivations1:add(model:get(i)) end
end

-------------------------------------------- Optimization --------------------------------------------------
optimState = {
	learningRate = params.lr,
	beta1 = 0.9,
	beta2 = 0.999,
	epsilon = 1e-8
}
optimMethod = optim.adam

if params.cuda == 1 then
	model = model:cuda()
	criterion = criterion:cuda()
	print("==> Placed on GPU")
end
-------------------------------------------- Parallel Table parameters --------------------------------------


-------------------------------------------- Loading data ---------------------------------------------------
if params.para == 0 then
	params.para = {}
else
	params.para = {0.7,0.9,1.3}
end
print("Input scaling factors")
print(params.para)
if params.kFold == 1 then 
	if params.test == 1 then
		trainTest = "Test"
	else
		trainTest = "Train"
	end
	print("==> k fold cross validation leaving subset "..params.fold.." out for testing")
	local C0Path = "CSVFILES/subset"..params.fold.."/candidatesClass0"..trainTest..".csv"
	local C1Path = "CSVFILES/subset"..params.fold.."/candidatesClass1"..trainTest..".csv"

	print("==> "..trainTest.."ing on csv files; "..C0Path..", "..C1Path..".")
	C0 = Data:new(C0Path,params.clipMin,params.clipMax,params.sliceSize)
	C1 = Data:new(C1Path,params.clipMin,params.clipMax,params.sliceSize)
end
C0:getNewScan()
C1:getNewScan()

function getBatch(data1,data2,batchSize,sliceSize,clipMin,clipMax,angleMax,scalingFactor,test,para)
	--Make empty table to loop into
	X = {}
	y = torch.Tensor(batchSize,1)
	for i=1, batchSize do
		if torch.uniform() < 0.5 then data = data1 else data = data2 end
		if data.finishedScan == true then
			data:getNewScan()
		else
			data:getNextCandidate()
		end

		if #para>1 then

			x = {}
			X[i] = x
			for iScaling =1, #para do
			   x[iScaling] = rotation3d(data, angleMax, sliceSize, clipMin, clipMax, para[iScaling] , test):reshape(1,1,sliceSize,sliceSize,sliceSize):cuda()
		  	 end
		else 
			X[i] = rotation3d(data, angleMax, sliceSize, clipMin, clipMax, scalingFactor, test):reshape(1,1,sliceSize,sliceSize,sliceSize)
		end
		y[i] = data.Class
	end
	collectgarbage()
	return X,y
end

start = torch:Timer()
x,y = getBatch(C0,C1,params.batchSize,params.sliceSize,params.clipMin,params.clipMax,params.angleMax,params.scalingFactor,params.test,params.para)
print(start:time().real)


function training()

	if i~= nil then i = 1 end
	
	if displayTrue==nil and params.display==1 then
		print("Initializing displays ==>")
		zoom = 0.6
		init = image.lena()
		imgZ = image.display{image=init, zoom=zoom, offscreen=false}
		imgY = image.display{image=init, zoom=zoom, offscreen=false}
		imgX = image.display{image=init, zoom=zoom, offscreen=false}
		--[[
		imgZ1 = image.display{image=init, zoom=zoom, offscreen=false}
		imgY1 = image.display{image=init, zoom=zoom, offscreen=false}
		imgX1 = image.display{image=init, zoom=zoom, offscreen=false}
		imgZ2 = image.display{image=init, zoom=zoom, offscreen=false}
		imgY2 = image.display{image=init, zoom=zoom, offscreen=false}
		imgX2 = image.display{image=init, zoom=zoom, offscreen=false}
		]]--
		if params.activations == 1 then
			activationDisplay1 = image.display{image=init, zoom=zoom, offscreen=false}
			--activationDisplay2 = image.display{image=init, zoom=zoom, offscreen=false}
		end
		displayTrue = "not nil"
	end


	if model then parameters,gradParameters = model:getParameters() end

	epochLosses = {}
	batchLosses = {}
	batchLossesMA = {}
	accuraccies = {}

	while true do

		inputs,targets = getBatch(C0,C1,params.batchSize,params.sliceSize,params.clipMin,params.clipMax,params.angleMax,params.scalingFactor,params.test,params.para)

		if params.cuda == 1 then
			targets = targets:cuda()
		end
			
		function feval(x)
			if x~= parameters then parameters:copy(x) end

			gradParameters:zero()

			predictions = model:forward(inputs[1])
			loss = criterion:forward(predictions,targets)
			dLoss_d0 = criterion:backward(predictions,targets)
			if params.log == 1 then logger:add{['loss'] = loss } end
			model:backward(inputs[1], dLoss_d0)

			return loss, gradParameters

		end
		-- Possibly improve this to take batch with large error more frequently
		_, batchLoss = optimMethod(feval,parameters,optimState)


		-- Performance metrics
		accuracy = binaryAccuracy(targets,predictions,params.cuda)
		loss = criterion:forward(predictions,targets)

		accuraccies[#accuraccies + 1] = accuracy
		batchLosses[#batchLosses + 1] = loss 
		accuracciesT = torch.Tensor(accuraccies)
		batchLossesT = torch.Tensor(batchLosses)
		local t = torch.range(1,batchLossesT:size()[1])
		local ma = 10
		if i > ma then 
			print(string.format("Iteration %d. MA loss of last 20 batches == > %f. MA accuracy ==> %f. Overall accuracy ==> %f ",
			i, batchLossesT[{{-ma,-1}}]:mean(), accuracciesT[{{-ma,-1}}]:mean(),accuracciesT:mean()))
		end

		--Plot
		if i % 30 == 0 then
			gnuplot.figure(1)
			gnuplot.plot({"Train loss",t,batchLossesT})
		end


		if i % 100 == 0 then
			print("==> Saving weights for ".. modelName)
			torch.save("models/"..modelName,model)
		end

		if params.display == 1 and displayTrue ~= nil and i % 5 == 0 then 
			local idx = 1 
			local class = "Class = " .. targets[1][1] .. ". Prediction = ".. predictions[1]

			-- Display rotated images
			-- Middle Slice
			image.display{image = inputs[1][1][{{idx},{},{params.sliceSize/2 +1}}]:reshape(params.sliceSize,params.sliceSize), win = imgZ, legend = class}
			image.display{image = inputs[1][2][{{idx},{},{params.sliceSize/2 +1}}]:reshape(params.sliceSize,params.sliceSize), win = imgY, legend = class}
			image.display{image = inputs[1][3][{{idx},{},{params.sliceSize/2 +1}}]:reshape(params.sliceSize,params.sliceSize), win = imgX, legend = class}
			-- Slice + 1
			--[[
			image.display{image = inputs[{{idx},{},{params.sliceSize/2 +2}}]:reshape(params.sliceSize,params.sliceSize), win = imgZ1, legend = class}
			image.display{image = inputs[{{idx},{},{},{params.sliceSize/2 +2}}]:reshape(params.sliceSize,params.sliceSize), win = imgY1, legend = class}
			image.display{image = inputs[{{idx},{},{},{},{params.sliceSize/2 +2}}]:reshape(params.sliceSize,params.sliceSize), win = imgX1, legend = class}
			-- Slice + 2 
			image.display{image = inputs[{{idx},{},{params.sliceSize/2 }}]:reshape(params.sliceSize,params.sliceSize), win = imgZ2, legend = class}
			image.display{image = inputs[{{idx},{},{},{params.sliceSize/2 }}]:reshape(params.sliceSize,params.sliceSize), win = imgY2, legend = class}
			image.display{image = inputs[{{idx},{},{},{},{params.sliceSize/2 }}]:reshape(params.sliceSize,params.sliceSize), win = imgX2, legend = class}
			]]--

			-- Display first layer activtion plane. Draw one activation plane at random and slice on first (z) dimension.
			if params.activations == 1 then 
				local activations1 = modelActivations1:forward(inputs)
				local randomFeat1 = torch.random(1,modelActivations1:get(2).nOutputPlane)
				image.display{image = activations1[{{1},{randomFeat1},{params.sliceSize/2}}]:reshape(params.sliceSize,params.sliceSize), win = activationDisplay1, legend = "Activations"}
			end

		end

		i = i + 1
		collectgarbage()
	end
end

function testing()
	local batchLosses = {}
	local accuraccies = {}
	local i = 1
	while true do
		i = i + 1
		if not params.useThreads then 
			local xBatchTensor = torch.Tensor(params.batchSize,1,params.sliceSize,params.sliceSize,params.sliceSize)
			local yBatchTensor = torch.Tensor(params.batchSize,1)

			getBatch(train,params.batchSize,xBatchTensor,yBatchTensor,params.sliceSize,params.clipMin,params.clipMax,params.angleMax,params.scalingFactor)
			inputs, targets = xBatchTensor, yBatchTensor
		else 
			inputs, targets = retrieveBatch()
		end 

		if params.cuda == 1 then
			inputs = inputs:cuda()
			targets = targets:cuda()
		end

		predictions = model:forward(inputs)

		accuracy = binaryAccuracy(targets,predictions,params.cuda)
		loss = criterion:forward(predictions,targets)

		accuraccies[#accuraccies + 1] = accuracy
		batchLosses[#batchLosses + 1] = loss 
		accuracciesT = torch.Tensor(accuraccies)
		batchLossesT = torch.Tensor(batchLosses)
		local t = torch.range(1,batchLossesT:size()[1])
		local ma = 10
		if i > ma then 
			print(string.format("Iteration %d. MA loss of last 20 batches == > %f. MA accuracy ==> %f. Overall accuracy ==> %f ",
			i, batchLossesT[{{-ma,-1}}]:mean(), accuracciesT[{{-ma,-1}}]:mean(),accuracciesT:mean()))
		end

	end
end
 
if params.train == 1 then
	training()
elseif params.test == 1 then
	testing()
end




