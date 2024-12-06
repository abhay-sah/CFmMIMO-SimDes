%% Pre 6G Cell Free Simulation
% This shows how to use pre6GCPU, pre6GAP and pre6GUE in system-level 
% simulation. The models a 1Km x 1Km area consisting of uniformly distributed 
% access point (AP) nodes and a set of user equipment (UE) nodes connected to 
% its closest AP node. This file models channel impairments that you can 
% customize.
%% Scenario Configuration
% Check if the Communications Toolbox Wireless Network Simulation Library support 
% package is installed. If the support package is not installed, MATLAB® returns 
% an error with a link to download and install the support package

clear;
wirelessnetworkSupportPackageCheck
%% 
% Create the wireless network simulator.

rng("default") % Reset the random number generator
numFrameSimulation = 20; % Simulation time in terms of number of 10 ms frames
networkSimulator = wirelessNetworkSimulator.init;
pre6GCPU.reset(); % Reset the CPU Cell ID Count, Necessary to do with wireless network simulator initialization
%% 
% You can only use full PHY as of now. All the nodes (CPU, APs and UEs) must 
% use the same PHY processing method.

phyAbstractionType = "none"; % PHY Abstraction must be "none"
duplexMode = "TDD"; % This Cell-Free implementation only supports "TDD"
split = "Centralized"; % Realization used
%% 
% Set up the simulation parameters.

lengthX = 1000; % Length (in meter) of Simulation Area in X diection
lengthY = 1000; % Length (in meter) of Simulation Area in Y diection
numAPs = 25; % Number of APs in that Simulation Area
numUEs = 7; % Number of UEs in that Simulation Area
numUEConnections = 4; % Number of Connections UE can make to its nearby APs
%% 
% Create a CPU node with specific parameter.

CPU = pre6GCPU(Name="CPU-1",Position=[lengthX*0.5, lengthY + 50, 10], ...
    PHYAbstractionMethod=phyAbstractionType,Split=split,DuplexMode=duplexMode, ...
    CarrierFrequency=1.9e9,ChannelBandwidth=20e6,SubcarrierSpacing=15e3);
%% 
% Generate AP Positions uniformly in the specified area. And create AP nodes 
% on that location.

[apPositions, apRadius] = generateAPPositions(numAPs, lengthX, lengthY);
apNames = "AP-" + (1:size(apPositions,1));
APs = pre6GAP(Name=apNames,Position=apPositions, ...
    TransmitPower=23,NumTransmitAntennas=4,NumReceiveAntennas=4,ReceiveGain=0,NoiseFigure=9);
%% 
% Connect those AP nodes with CPU node.

CPU.connectAP(APs);
%% 
% Generate UE Positions and create UE nodes on that locations then connect it 
% to nearest APs based on the number of connections specified.

uePositions = generateUEPositions(numUEs, lengthX, lengthY);
% Initialize UE array
UEs = pre6GUE.empty(0,numUEs);
for i=1:numUEs
    % Get closest APs to the particular UE
    distance = sqrt((apPositions(:,1)-uePositions(i,1)) .^ 2 + (apPositions(:,2) - uePositions(i,2)) .^ 2);
    [~, closestAPIdx] = sort(distance, 'ascend');
    % Generate UE name according to the numUEConnections specified
    ueName = "UE" + i + " AP-";
    for j=1:numUEConnections
        ueName = ueName + floor(APs(closestAPIdx(j)).APCellID/3);
        if(j ~= numUEConnections)
            ueName = ueName + "-";
        end
    end
    % Create a UE node with the generated name
    UEs(i) = pre6GUE(Name=ueName,Position=uePositions(i,:),PHYAbstractionMethod=phyAbstractionType, ...
        TransmitPower=20,NumTransmitAntennas=1,NumReceiveAntennas=1,ReceiveGain=0,NoiseFigure=9);
    % Connect the UE with nearest APs
    for j=1:numUEConnections
        APs(closestAPIdx(j)).connectUE(UEs(i),FullBufferTraffic="on");
    end
end
%% 
% Add CPU, AP and UE nodes to the simulator.

addNodes(networkSimulator, CPU);
addNodes(networkSimulator, APs);
addNodes(networkSimulator, UEs);
%% 
% Create an N-by-N array of link-level channels, where N is the total number 
% of nodes in the system. An element at index (i,j) contains the channel instance 
% from node i to node j. An empty element at index (i,j) indicates that the channel 
% does not exist from node i to node j. Here, i and j are the node IDs.

numNodes = length(CPU) + numAPs + numUEs;
channels = cell(numNodes,numNodes);
channelConfig = struct("DelaySpread",300e-9);
for i=1:numAPs
    channels = createCDLChannels(channels,channelConfig,APs(i),UEs);
end
%% 
% Create a custom channel model using |channels| and install the custom channel 
% on the simulator. The network simulator applies the custom channel to a packet 
% in transit before passing it to the receiver.

customChannelModel = hNRCustomChannelModel(channels,struct(PHYAbstractionMethod=phyAbstractionType));
addChannelModel(networkSimulator,@customChannelModel.applyChannelModel)
%% 
% Set up the metric visualizer for plotting graphs.

enablePHYPlot =  true;
enableSchPlot =  true;
enableCDFPlot =  true;
numMetricsSteps = numFrameSimulation;
metricsVisualizer = helperNRMetricsVisualizer(CPU,UEs,NumMetricsSteps=numMetricsSteps,...
    PlotSchedulerMetrics=enableSchPlot,PlotPhyMetrics=enablePHYPlot,PlotCDFMetrics=enableCDFPlot);
%% 
% Visualize the scenario.

enableVisualization = true;
if enableVisualization
    pre6GNetworkVisualizer();
end
%% 
% Run the simulation for the specified |numFrameSimulation| frames.

% Calculate the simulation duration (in seconds)
simulationTime = numFrameSimulation * 1e-2;
% Run the simulation
tic;
run(networkSimulator,simulationTime);
toc;
%% 
% Read per-node statistics.

cpuStats = CPU.statistics();
ueStats = UEs.statistics();
%% 
% Compare the achieved value for system performance indicators with their theoretical 
% peak values (considering zero overheads). The performance indicators displayed 
% are the achieved data rate (UL and DL), the achieved spectral efficiency (UL 
% and DL), and the achieved block error rate (UL and DL). This calculates 
% the peak values as per 3GPP TR 37.910.

 displayPerformanceIndicators(metricsVisualizer);
%% Local Funtion
% Generate AP Positions

function [apPositions, apRadius] = generateAPPositions(numAPs, lengthX, lengthY)
    %generateAPPositions generate AP positions in a given area uniformly
    % It returns the apPositions and apRadius based on the generated
    % positions.
    %
    % numAPs - Number of APs.
    % lengthX - Length of area in X direction.
    % lengthY - Length of area in Y direction.

    % a, b is num of APs in lengthX, lengthY
    a = round(sqrt(numAPs * lengthX / lengthY));
    while(a > 0)
        b = numAPs / a;
        if b == floor(b)
            break;
        end
        a = a - 1;
    end
    flag = 0;
    if a==1 && b > 3
        flag = 1;
        a = round(sqrt((numAPs - 1) * lengthX / lengthY));
        while(a > 0)
            b = (numAPs - 1) / a;
            if b == floor(b)
                break;
            end
            a = a - 1;
        end
    end
    % lengths of sub segment covered by an AP
    subX = lengthX / a;
    subY = lengthY / b;
    % calculate radius per AP
    apRadius = max(subX,subY)/2;
    % initializing position array
    x = zeros(numAPs, 1);
    y = zeros(numAPs, 1);
    k = 1;
    % rx, ry is lengths of random region in sub segment / 2
    rx = 0.3 * b/(a+b);
    ry = 0.3 * a/(a+b);
    for i=1:a
        for j=1:b
            if flag && j == b
                continue;
            end
            x(k) = subX * (i - (0.5+rx) + 2*rx*rand);
            y(k) = subY * (j - (0.5+ry) + 2*ry*rand);
            k = k + 1;
        end
    end
    if flag
        subX = lengthX / (a+1);
        for i=1:(a+1)
            x(k) = subX * (i - (0.5+rx) + 2*rx*rand);
            y(k) = subY * (b - (0.5+ry) + 2*ry*rand);
            k = k + 1;
        end
    end
    z = zeros(numAPs, 1);
    apPositions = [x y z];
end
%% 
% Generate UE Positions

function [uePositions] = generateUEPositions(numUEs, lengthX, lengthY)
    %generateUEPositions generate UE positions in a given area randomly
    % It returns the uePositions
    %
    % numUEs - Number of UEs.
    % lengthX - Length of area in X direction.
    % lengthY - Length of area in Y direction.

    % initializing position array
    x = zeros(numUEs, 1);
    y = zeros(numUEs, 1);
    for i = 1:numUEs
        % Evenly Distribute UEs in 4 quardrents
        rx = mod(i, 4);
        ry = mod(rx, 2);
        x(i) = (floor(rx / 2) + rand) * lengthX / 2;
        y(i) = (ry + rand) * lengthY / 2;
    end
    z = zeros(numUEs, 1);
    uePositions = [x y z];
end
%% 
% Set up CDL channel instances for each DL and UL link in the cell

function channels = createCDLChannels(channels,channelConfig,AP,UEs)
    %createCDLChannels Create channels between AP node and UE nodes in a cell
    %   CHANNELS = createCDLChannels(CHANNELS,CHANNELCONFIG,AP,UES) creates channels
    %   between AP and UES in a cell.
    %
    %   CHANNELS is a N-by-N array where N is the number of nodes in the cell.
    %
    %   CHANNLECONFIG is a struct with these fields - DelayProfile and
    %   DelaySpread.
    %
    %   AP is an pre6GAP node.
    %
    %   UES is an array of pre6GUE nodes.
    % Create channel matrix to hold the channel objects

    % Get the sample rate of waveform
    waveformInfo = nrOFDMInfo(AP.NumResourceBlocks,AP.SubcarrierSpacing/1e3);
    sampleRate = waveformInfo.SampleRate;
    channelFiltering = strcmp(AP.PHYAbstractionMethod,'none');
    numUEs = length(UEs);

    % Create a CDL channel model object configured with the desired delay
    % profile, delay spread, and Doppler frequency
    channel = nrCDLChannel;
    channel.CarrierFrequency = AP.CarrierFrequency;
    channel.DelaySpread = channelConfig.DelaySpread;
    channel.ChannelFiltering = channelFiltering;
    channel.SampleRate = sampleRate;

    for ueIdx = 1:numUEs
        % Configure the DL channel model between AP and UE
        cdl = hMakeCustomCDL(channel);
        cdl.Seed = 73 + (ueIdx - 1);
        cdl = hArrayGeometry(cdl,AP.NumTransmitAntennas,UEs(ueIdx).NumReceiveAntennas,...
            'downlink');

        % Compute the LOS angle from AP to UE
        [~,depAngle] = rangeangle(UEs(ueIdx).Position', ...
            AP.Position');

        % Configure the azimuth and zenith angle offsets for this UE
        cdl.AnglesAoD(:) = cdl.AnglesAoD(:) + depAngle(1);
        % Convert elevation angle to zenith angle amsfnksdsff
        cdl.AnglesZoD(:) = cdl.AnglesZoD(:) - cdl.AnglesZoD(1) + (90 - depAngle(2));
        channels{AP.ID, UEs(ueIdx).ID} = cdl;

        % Configure the UL channel model between AP and UE
        cdlUL = clone(cdl);
        cdlUL.swapTransmitAndReceive();
        channels{UEs(ueIdx).ID, AP.ID} = cdlUL;
    end
end
