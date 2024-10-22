classdef helperNRMetricsVisualizer < handle
    %helperNRMetricsVisualizer Creates metrics visualization object
    %   The class implements visualization of the metrics. The following three
    %   types of visualizations are shown:
    %       - Display of MAC Scheduler performance metrics
    %       - Display of Phy metrics
    %       - Dispaly of RLC metrics
    %       - Display of CDF plots for cell throughput and block error rate (BLER) metrics
    %
    %   helperNRMetricsVisualizer methods:
    %
    %   plotLiveMetrics - Updates the metric plots by querying from nodes
    %
    %   helperNRMetricsVisualizer Name-Value pairs:
    %
    %   CellOfInterest       - Cell ID to which the visualization object belongs
    %   LinkDirection        - Indicates the link direction associated to the plots to visualize
    %   PlotSchedulerMetrics - Switch to turn on/off the scheduler performance metrics plots
    %   PlotPhyMetrics       - Switch to turn on/off the PHY metrics plots
    %   PlotRLCMetrics       - Switch to turn on/off the RLC metrics plots
    %   PlotCDFMetrics       - Switch to turn on/off the CDF plots for cell throughput and BLER metrics
    %   NumMetricsSteps      - Number of times metrics plots to be updated

    %   Copyright 2022-2023 The MathWorks, Inc.

    properties
        %CellOfInterest Cell id to which the visualization belongs
        CellOfInterest (1, 1) {mustBeInteger, mustBeInRange(CellOfInterest, 0, 1007)} = 1;

        %LinkDirection  Indicates the link direction associated to the plots to visualize
        % It takes the values 0, 1, 2 and represent downlink, uplink, and both link
        % directions respectively. Default value is 2.
        LinkDirection = 2;

        %PlotSchedulerMetrics Switch to turn on/off the scheduler performance metrics plots
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default the plots ar disabled
        PlotSchedulerMetrics = false;

        %PlotPhyMetrics Switch to turn on/off the PHY metrics plots
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default, the plots are disabled
        PlotPhyMetrics = false;

        %PlotRLCMetrics Switch to turn on/off the RLC metrics plots
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default, the plots are disabled
        PlotRLCMetrics = false;

        %PlotCDFMetrics Switch to turn on/off the CDF plots for cell throughput and BLER metrics
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default, the plots are disabled
        PlotCDFMetrics = false;

        %NumMetricsSteps Number of times metrics plots are updated
        NumMetricsSteps = 10;
    end

    properties(Hidden)
        %MACVisualization Timescope to display the downlink and uplink scheduler performance metrics
        MACVisualization = cell(2, 1);

        %PhyVisualization Timescope to display the downlink and uplink block error rates
        PhyVisualization

        %RLCVisualization Timescope to display RLC layer's transmitted bytes
        RLCVisualization

        %PHYCDFVisualizationFigHandle Handle of the PHY CDF visualization
        PHYCDFVisualizationFigHandle

        %MACCDFVisualizationFigHandle Handle of the MAC CDF visualization
        MACCDFVisualizationFigHandle
    end

    properties (Access = private)
        %SimTime Simulation end time (in seconds)
        SimTime

        %ULRLCMetrics Contains RLC metrics of UEs in uplink
        % It is a column vector of length M, where M represents the number of UEs
        ULRLCMetrics

        %DLRLCMetrics Contains RLC metrics of UEs in downlink
        % It is a colum vector of length M, where M represents the number of UEs
        DLRLCMetrics

        %PeakDataRateDL Theoretical peak data rate
        % A vector of two elements. First and second elements represent the
        % downlink and uplink theoretical peak data rate respectively
        PeakDataRate = zeros(2, 1);

        %Bandwidth Carrier bandwidth
        % A vector of two elements and represents the downlink and uplink bandwidth
        % respectively
        Bandwidth

        %UELegend Legend for the UE
        UELegend

        %MetricsStepDuration Duration of 1 metrics step
        MetricsStepDuration

        %MACTxBytes Total bytes transmitted (newTx + reTx)
        MACTxBytes

        %MACRxBytes Total bytes received
        MACRxBytes

        %DLBLERInfo Information to calculate DL block error rate
        % It is a M-by-2 matrix, where M represents the number of UEs and the
        % column1, column2 represents the total decode failures and total packets
        % received in downlink
        DLBLERInfo

        %ULBLERInfo Information to calculate UL block error rate
        % It is a M-by-2 matrix, where M represents the number of UEs and the
        % column1, column2 represents the total decode failures and total packets
        % received in uplink
        ULBLERInfo

        %ResourceShareMetrics Number of RBs allocated to each UE
        % Matrix of size 'M-by-2', where M is the number of UEs, 2 represents the
        % columns for downlink and uplink
        ResourceShareMetrics

        %AvgBLER Average block error rate (BLER) for CellOfInterest
        % Matrix of size 'MetricsStepDuration-by-2', where 2 represents the columns
        % for downlink and uplink
        AvgBLER

        %CellThroughput Cell throughput of CellOfInterest
        % Matrix of size 'MetricsStepDuration-by-2', where 2 represents the columns
        % for downlink and uplink
        CellThroughput

        %GNB gNB node object
        % It is a scalar and object of type nrGNB
        GNB

        %UEs UE node objects
        % It is an array of node objects of type nrUE
        UEs
    end

    properties(Access = private)
        %PlotIDs Represent the IDs of the plots. The value 1 and 2 indicate
        %downlink and uplink plot IDs, respectively
        PlotIDs = [1 2]

        %MaxMetricLinesPerSubPlot Maximum number of metric lines can be plotted in a sub-plot of time scope
        % Time scope allows plotting only 20 metric lines per sub-plot. 2 out 20
        % metric lines set aside for plotting cell level metrics like throughput
        % metric line and peak data rate metric line. Remaining 18 metric lines
        % will be used for plotting UE level metrics.
        MaxMetricLinesPerSubPlot = 18;

        %UEOfInterestList Information about the list of UEs of interest
        UEOfInterestList
    end

    properties (Access = private, Constant, Hidden)
        % Constants related to downlink and uplink information. These constants are
        % used for indexing logs and identifying plots
        %DownlinkIdx Index for all downlink information
        DownlinkIdx = 1;
        %UplinkIdx Index for all uplink information
        UplinkIdx = 2;
    end

    methods (Access = public)
        function obj = helperNRMetricsVisualizer(gNB, UEs, varargin)
            %helperNRMetricsVisualizer Constructs metrics visualization object
            %
            % OBJ = helperNRMetricsVisualizer(GNB, UES) Create metrics visualization
            % object for downlink and uplink plots.
            %
            % OBJ = helperNRMetricsVisualizer(GNB, UES, Name=Value) creates a metrics
            % visualization object, OBJ, with properties specified by one or more
            % name-value pairs. You can specify additional name-value pair arguments in
            % any order as (Name1=Value1,...,NameN=ValueN).
            %
            % GNB   - Base node of the cell
            % UEs   - UE nodes of the cell. They must be connected to GNB
            %
            % These are the name-value pairs that can be provided through varargin.
            %
            %   CellOfInterest       - Cell ID to which the visualization object belongs
            %   LinkDirection        - Indicates the link direction associated to the plots to visualize
            %   PlotSchedulerMetrics - Switch to turn on/off the scheduler performance metrics plots
            %   PlotPhyMetrics       - Switch to turn on/off the PHY metrics plots
            %   PlotCDFMetrics       - Switch to turn on/off the CDF plots for cell throughput and BLER metrics
            %   NumMetricsSteps      - Number of times metrics plots to be updated

            networkSimulator = wirelessNetworkSimulator.getInstance();
            % Initialize the properties
            for idx = 1:2:numel(varargin)
                obj.(varargin{idx}) = varargin{idx+1};
            end
            obj.GNB = gNB;
            obj.UEs = UEs;

            % Create legend information for the plots
            totalNumUEs = numel(UEs);

            ueOfInterestList = 1:totalNumUEs;
            numUEsOfInterest = numel(ueOfInterestList);
            obj.UELegend = cell(1, numUEsOfInterest);
            obj.UEOfInterestList = zeros(numUEsOfInterest, 1);
            for idx = 1:numUEsOfInterest
                obj.UEOfInterestList(idx) = ueOfInterestList(idx); % Update the UE id
                obj.UELegend{idx} = UEs(idx).Name;
            end
            obj.DLBLERInfo = zeros(totalNumUEs, 2);
            obj.ULBLERInfo = zeros(totalNumUEs, 2);

            obj.MACTxBytes = zeros(totalNumUEs, 2);
            obj.MACRxBytes = zeros(totalNumUEs, 2);
            obj.ResourceShareMetrics = zeros(totalNumUEs, 2);

            obj.ULRLCMetrics = zeros(totalNumUEs, 1);
            obj.DLRLCMetrics = zeros(totalNumUEs, 1);

            if obj.LinkDirection ~= 2
                % Either UL or DL is enabled
                obj.PlotIDs = obj.LinkDirection+1;
            end

            [obj.PeakDataRate(obj.DownlinkIdx), obj.PeakDataRate(obj.UplinkIdx)] = calculatePeakDataRate(obj);
            obj.Bandwidth(obj.DownlinkIdx) = obj.GNB.ChannelBandwidth;
            obj.Bandwidth(obj.UplinkIdx) = obj.GNB.ChannelBandwidth;

            % Initialize the properties for visualizing the CDF plots
            obj.AvgBLER = [];
            obj.CellThroughput = [];

            scheduleAction(networkSimulator, @obj.initLiveMetricPlots, [], 0);
        end

        function addRLCVisualization(obj)
            %addRLCVisualization Create RLC visualization
            %
            % addRLCVisualization(OBJ) Create and configure RLC
            % visualization. It creates figures for visualizing metrics
            % in both downlink and uplink.

            % Create the timescope
            if isempty(obj.RLCVisualization)
                obj.RLCVisualization = timescope('Name', 'RLC Metrics Visualization');
            end

            % Maximum number of node PHY metrics allowed to plot
            numUEs = size(obj.UEOfInterestList, 1);
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end
            txBytes = zeros(1, numUEs);

            set(obj.RLCVisualization, 'LayoutDimensions', [numel(obj.PlotIDs) 1], 'ShowLegend', true, 'AxesScaling', 'Updates', 'AxesScalingNumUpdates', 1, ...
                'SampleRate', obj.NumMetricsSteps/obj.SimTime,'TimeSpanSource', 'property','ChannelNames', repmat(obj.UELegend(1:numUEs), [1 numel(obj.PlotIDs)]), 'TimeSpan', obj.SimTime);

            titles = {'Downlink RLC', 'Uplink RLC'};
            % Initialize the plots
            if numel(obj.PlotIDs) == 1
                obj.RLCVisualization(txBytes);
            else
                obj.RLCVisualization(txBytes, txBytes);
            end

            % Add the titles and legends
            for idx=1:numel(obj.PlotIDs)
                obj.RLCVisualization.ActiveDisplay = idx;
                obj.RLCVisualization.YLabel = ['Cell-' num2str(obj.CellOfInterest) ' Tx Rate (Mbps)'];
                obj.RLCVisualization.Title = titles{obj.PlotIDs(idx)};
            end
        end

        function addMACVisualization(obj)
            %addMACVisualization Create MAC visualization
            %
            % addMACVisualization(OBJ) Create and configure MAC visualization. It
            % creates figures for visualizing metrics in both downlink and uplink.

            numUEs = size(obj.UEOfInterestList, 1);
            % Maximum number of node MAC metrics allowed to plot
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end
            nodeMetrics = zeros(1, numUEs);
            % Plot titles and Y-axis label prefix
            title = {'Downlink Scheduler Performance Metrics', ...
                'Uplink Scheduler Performance Metrics'};
            tag = {['Cell-' num2str(obj.CellOfInterest) ' DL '], ...
                ['Cell-' num2str(obj.CellOfInterest) ' UL ']};
            channelNames = [obj.UELegend(1:numUEs) 'Cell' 'Peak Data Rate' obj.UELegend(1:numUEs) obj.UELegend(1:numUEs) 'Cell' 'Peak Data Rate' obj.UELegend(1:numUEs)];

            % Create time scope and add labels
            for idx=1:numel(obj.PlotIDs)
                windowId = obj.PlotIDs(idx);

                if isempty(obj.MACVisualization{windowId})
                    obj.MACVisualization{windowId} = timescope('Name', title{windowId});
                end

                set(obj.MACVisualization{windowId}, 'LayoutDimensions',[2 2], 'ChannelNames', channelNames,...
                    'ActiveDisplay',1, 'YLabel',[tag{windowId} 'Tx rate (Mbps)'], 'ShowLegend',true,'AxesScaling', 'Updates', ...
                    'AxesScalingNumUpdates', 1, 'TimeSpanSource', 'property', 'TimeSpan', obj.SimTime, ...
                    'ActiveDisplay',2, 'YLabel',[tag{windowId} 'Resource Share (%)'], ...
                    'ShowLegend',true, 'YLimits',[1 100],'AxesScaling', 'Updates','AxesScalingNumUpdates', 1, ...
                    'SampleRate', obj.NumMetricsSteps/obj.SimTime, 'TimeSpanSource', 'property', 'TimeSpan', obj.SimTime, ...
                    'ActiveDisplay',3, 'YLabel',[tag{windowId} 'Throughput (Mbps)'], 'ShowLegend',true,'AxesScaling', 'Updates', 'AxesScalingNumUpdates', 1, ...
                    'SampleRate', obj.NumMetricsSteps/obj.SimTime, 'TimeSpanSource', 'property', 'TimeSpan', obj.SimTime, ...
                    'ActiveDisplay',4, 'YLabel',[tag{windowId} 'Buffer Status (KB)'], 'ShowLegend',true,'AxesScaling', 'Updates', 'AxesScalingNumUpdates', 1, ...
                    'SampleRate', obj.NumMetricsSteps/obj.SimTime, 'TimeSpanSource', 'property', 'TimeSpan', obj.SimTime);
                obj.MACVisualization{windowId}([nodeMetrics 0 obj.PeakDataRate(windowId)], nodeMetrics, [nodeMetrics 0 obj.PeakDataRate(windowId)], nodeMetrics);
            end
        end

        function addPhyVisualization(obj)
            %addPhyVisualization Create Phy visualization
            %
            % addPhyVisualization(OBJ) Create and configure Phy visualization. It
            % creates figures for visualizing metrics in both downlink and uplink.

            % Create and configure the timescope
            if isempty(obj.PhyVisualization)
                obj.PhyVisualization = timescope('Name', 'Block Error Rate (BLER) Visualization');
            end

            % Maximum number of node PHY metrics allowed to plot
            numUEs = size(obj.UEOfInterestList, 1);
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end
            blerData = zeros(1, numUEs);

            set(obj.PhyVisualization, 'LayoutDimensions', [numel(obj.PlotIDs) 1], 'ShowLegend', true, ...
                'SampleRate', obj.NumMetricsSteps/obj.SimTime,'TimeSpanSource', 'property','ChannelNames', repmat(obj.UELegend(1:numUEs), [1 numel(obj.PlotIDs)]), 'TimeSpan', obj.SimTime);

            titles = {'Downlink BLER', 'Uplink BLER'};
            % Initialize the plots
            if numel(obj.PlotIDs) == 1
                obj.PhyVisualization(blerData);
            else
                obj.PhyVisualization(blerData, blerData);
            end

            % Add the titles and legends
            for idx=1:numel(obj.PlotIDs)
                obj.PhyVisualization.ActiveDisplay = idx;
                obj.PhyVisualization.YLimits = [0 1];
                obj.PhyVisualization.YLabel = ['Cell-' num2str(obj.CellOfInterest) ' BLER'];
                obj.PhyVisualization.Title = titles{obj.PlotIDs(idx)};
            end
        end

        function plotLiveMetrics(obj, ~, ~)
            %plotLiveMetrics Updates the metric plots by querying from nodes

            % RLC metrics visualization
            if ~isempty(obj.RLCVisualization)
                plotLiveRLCMetrics(obj);
            end

            % MAC metrics visualization
            if ~isempty(obj.MACVisualization{1}) || ~isempty(obj.MACVisualization{2})
                plotLiveMACMetrics(obj);
            end

            % PHY metrics visualization
            if ~isempty(obj.PhyVisualization)
                plotLivePhyMetrics(obj);
            end
        end

        function displayPerformanceIndicators(obj)

            if ismember(obj.UplinkIdx, obj.PlotIDs) % Uplink stats
                if obj.PlotSchedulerMetrics
                    ulTxRate = (obj.MACTxBytes(:, obj.UplinkIdx) .* 8) ./ (obj.SimTime * 1000 * 1000); % Mbps
                    ulThroughput = (obj.MACRxBytes(:, obj.UplinkIdx) .* 8) ./ (obj.SimTime * 1000 * 1000); % Mbps
                    ulPeakSpectralEfficiency = 1e6*obj.PeakDataRate(obj.UplinkIdx)/obj.Bandwidth(obj.UplinkIdx);
                    ulAchSpectralEfficiency = 1e6*sum(ulThroughput)/obj.Bandwidth(obj.UplinkIdx);
                    fprintf('Peak UL Throughput: %0.2f Mbps. Achieved Cell UL Throughput: %0.2f Mbps\n', obj.PeakDataRate(obj.UplinkIdx), sum(ulThroughput));
                    disp(['Achieved UL Throughput for each UE: [' num2str(round(ulThroughput, 2)') ']']);
                    fprintf('Peak UL spectral efficiency: %0.2f bits/s/Hz. Achieved UL spectral efficiency for cell: %0.2f bits/s/Hz \n', ulPeakSpectralEfficiency, ulAchSpectralEfficiency);
                end
                if obj.PlotPhyMetrics
                    ulBLER = obj.ULBLERInfo(:, 1) ./ obj.ULBLERInfo(:, 2);
                    ulBLER(isnan(ulBLER)) = 0;
                    fprintf(['Block error rate for each UE in the uplink direction: [' num2str(round(ulBLER, 3)') ']\n\n']);
                end
            end

            if ismember(obj.DownlinkIdx, obj.PlotIDs) % Downlink stats
                if obj.PlotSchedulerMetrics
                    dlTxRate = (obj.MACTxBytes(:, obj.DownlinkIdx) .* 8) ./ (obj.SimTime * 1000 * 1000); % Mbps
                    dlThroughput = (obj.MACRxBytes(:, obj.DownlinkIdx) .* 8) ./ (obj.SimTime * 1000 * 1000); % Mbps
                    dlPeakSpectralEfficiency = 1e6*obj.PeakDataRate(obj.DownlinkIdx)/obj.Bandwidth(obj.DownlinkIdx);
                    dlAchSpectralEfficiency = 1e6*sum(dlThroughput)/obj.Bandwidth(obj.DownlinkIdx);
                    fprintf('Peak DL Throughput: %0.2f Mbps. Achieved Cell DL Throughput: %0.2f Mbps\n', obj.PeakDataRate(obj.DownlinkIdx), sum(dlThroughput));
                    disp(['Achieved DL Throughput for each UE: [' num2str(round(dlThroughput, 2)') ']']);
                    fprintf('Peak DL spectral efficiency: %0.2f bits/s/Hz. Achieved DL spectral efficiency for cell: %0.2f bits/s/Hz\n', dlPeakSpectralEfficiency, dlAchSpectralEfficiency);
                end

                if obj.PlotPhyMetrics
                    dlBLER = obj.DLBLERInfo(:, 1) ./ obj.DLBLERInfo(:, 2);
                    dlBLER(isnan(dlBLER)) = 0;
                    fprintf(['Block error rate for each UE in the downlink direction: [' num2str(round(dlBLER, 3)') ']\n\n']);
                end
            end
        end

        function [dlPeakDataRate, ulPeakDataRate] = calculatePeakDataRate(obj)
            %calculatePeakDataRate Calculate peak data rate

            gNB = obj.GNB;
            ue = obj.UEs(1);
            numUEs = numel(obj.UEs);
            scs = gNB.SubcarrierSpacing/1e3;
            % Symbol duration for the given numerology
            symbolDuration = 1e-3/(14*(scs/15)); % Assuming normal cyclic prefix

            % Maximum number of transmission layers for each UE in DL
            numLayersDL = min(gNB.NumTransmitAntennas*ones(numUEs, 1), ue.NumReceiveAntennas);
            % Maximum number of transmission layers for each UE in UL
            numLayersUL = min(gNB.NumReceiveAntennas*ones(numUEs, 1), ue.NumTransmitAntennas);

            if strcmp(gNB.DuplexMode, "TDD")
                tddConfig = gNB.DLULConfigTDD;
                % Number of DL symbols in one DL-UL pattern
                numDLSymbols = tddConfig.NumDLSlots*14 + tddConfig.NumDLSymbols;
                % Number of UL symbols in one DL-UL pattern
                numULSymbols = tddConfig.NumULSlots*14 + tddConfig.NumULSymbols;
                % Number of symbols in one DL-UL pattern
                numSymbols = tddConfig.DLULPeriodicity*(scs/15)*14;
                % Normalized scalar considering the downlink symbol
                % allocation in the frame structure
                scaleFactorDL = numDLSymbols/numSymbols;
                % Normalized scalar considering the uplink symbol allocation
                % in the frame structure
                scaleFactorUL = numULSymbols/numSymbols;
            else % FDD
                % Normalized scalars in the DL and UL directions are 1 for
                % FDD mode
                scaleFactorDL = 1;
                scaleFactorUL = 1;
            end

            % Calculate uplink and downlink peak data rates as per 3GPP TS 37.910. The
            % number of layers used for the peak DL or UL data rate calculation is
            % taken as the average of maximum layers possible for each UE. The maximum
            % layers possible for a UE in DL direction is min(gNBTxAnts, ueRxAnts). For
            % UL direction, it is min(UETxAnts, gNBRxAnts)
            % Average of the peak DL, UL throughput values for each UE
            dlPeakDataRate = 1e-6*(sum(numLayersDL)/numUEs)*scaleFactorDL*8*(948/1024)*(gNB.NumResourceBlocks*12)/symbolDuration;
            ulPeakDataRate = 1e-6*(sum(numLayersUL)/numUEs)*scaleFactorUL*8*(948/1024)*(gNB.NumResourceBlocks*12)/symbolDuration;
        end

        function metrics = getMetrics(obj)
            %getMACMetrics Return the metrics after live visualization
            %
            % METRICS = getMetrics(OBJ) Returns the metrics corresponding to the
            % enabled metrics visualization.
            %
            % METRICS - It is a structure and returns simulation metrics corresponding
            % to the enabled visualizations. It has the following fields.
            %   MACMetrics - Metrics of MAC layer
            %   PhyMetrics - Metrics of Phy layer

            metrics = struct('MACMetrics',[],'PhyMetrics',[]);
            rntiList = [obj.UEs.RNTI];

            if obj.PlotSchedulerMetrics
                dlTxBytes = obj.MACTxBytes(:, obj.DownlinkIdx);
                dlThroughputBytes = obj.MACRxBytes(:, obj.DownlinkIdx);
                dlRBs = obj.ResourceShareMetrics(:, obj.DownlinkIdx);
                ulTxBytes = obj.MACTxBytes(:, obj.UplinkIdx);
                ulThroughputBytes = obj.MACRxBytes(:, obj.UplinkIdx);
                ulRBs = obj.ResourceShareMetrics(:, obj.UplinkIdx);
                macMetrics = table(rntiList', dlTxBytes, dlThroughputBytes, dlRBs, ...
                    ulTxBytes, ulThroughputBytes, ulRBs);
                macMetrics.Properties.VariableNames = {'RNTI', 'DL Tx Bytes', ...
                    'DL Throughput Bytes', 'DL RBs allocated', 'UL Tx Bytes', 'UL Throughput Bytes', 'UL RBs allocated'};
                metrics.MACMetrics = macMetrics;
            end

            if obj.PlotPhyMetrics
                phyMetrics = table(rntiList', obj.DLBLERInfo(rntiList, 2),obj.DLBLERInfo(rntiList, 1), ...
                    obj.ULBLERInfo(rntiList, 2), obj.ULBLERInfo(rntiList, 1));
                phyMetrics.Properties.VariableNames = {'RNTI', 'Number of Packets (DL)', ...
                    'Decode Failures (DL)', 'Number of Packets (UL)', 'Decode Failures (UL)'};
                metrics.PhyMetrics = phyMetrics;
            end
        end
    end

    methods(Access = private)
        function plotLiveRLCMetrics(obj)
            %plotLiveRLCMetrics Plots the RLC live metrics

            ueList = obj.UEs;
            numUEs = numel(ueList);
            txRate = zeros(numUEs, 2);
            ulTxBytes = zeros(numUEs, 1);
            dlTxBytes = zeros(numUEs, 1);

            if obj.LinkDirection ~= 1 % Downlink
                gNBStats = statistics(obj.GNB, "all");
                gNBRLCStats = gNBStats.RLC.Destinations;
                for idx = 1:numUEs
                    dlTxBytes(idx) = gNBRLCStats(idx).TransmittedBytes;
                    txRate(idx, 1) = ((dlTxBytes(idx) - obj.DLRLCMetrics(idx))* 8) / (obj.MetricsStepDuration * 1000);
                    obj.DLRLCMetrics(idx) = dlTxBytes(idx);
                end
            end

            if obj.LinkDirection ~= 0 % Uplink
                for idx = 1:numUEs
                    ueStats = statistics(obj.UEs(idx));
                    ulTxBytes(idx) = ueStats.RLC.TransmittedBytes;
                    txRate(idx, 2) = ((ulTxBytes(idx) - obj.ULRLCMetrics(idx))* 8) / (obj.MetricsStepDuration * 1000);
                    obj.ULRLCMetrics(idx) = ulTxBytes(idx);
                end
            end

            txRate = txRate(obj.UEOfInterestList, :);

            updateRLCMetrics(obj, txRate);
        end

        function plotLiveMACMetrics(obj)
            %plotLiveMACMetrics Plots the MAC live metrics

            ueList = obj.UEs;
            numUEs = numel(ueList);
            txRate = zeros(numUEs, 2);
            throughput = zeros(numUEs, 2);
            bufferstatus = zeros(numUEs, 2);
            resourceshare = zeros(numUEs, 2);
            cellTxRate = zeros(2, 2);
            cellThroughputMetrics = zeros(2, 2);
            gNBMAC = obj.GNB.MACEntity;
            if obj.LinkDirection ~= 0 % Uplink
                throughput(:, obj.UplinkIdx) = (gNBMAC.StatReceivedBytes - obj.MACRxBytes(:, obj.UplinkIdx))* 8 / (obj.MetricsStepDuration * 1000);
                obj.MACRxBytes(:, obj.UplinkIdx) = gNBMAC.StatReceivedBytes;
                for ueIdx = 1:numUEs
                    ueMAC = ueList(ueIdx).MACEntity;
                    txBytes = ueMAC.StatTransmittedBytes + ueMAC.StatRetransmittedBytes;
                    totalNumRBs = ueMAC.StatULTransmissionRB + ueMAC.StatULRetransmissionRB;

                    % Instant metrics calculation
                    txRate(ueIdx, obj.UplinkIdx) = (txBytes - obj.MACTxBytes(ueIdx, obj.UplinkIdx))* 8 / (obj.MetricsStepDuration * 1000);
                    resourceshare(ueIdx, obj.UplinkIdx) =  totalNumRBs - obj.ResourceShareMetrics(ueIdx, obj.UplinkIdx);

                    statusInfo = ueList(ueIdx).MACEntity.ueInformation;
                    bufferstatus(ueIdx, obj.UplinkIdx) = statusInfo.BufferSize / 1000; % In KB;

                    % Save the previous metrics
                    obj.MACTxBytes(ueIdx, obj.UplinkIdx) = txBytes;
                    obj.ResourceShareMetrics(ueIdx, obj.UplinkIdx) = totalNumRBs;
                end

                % Cell level metrics
                numRBScheduled = sum(resourceshare(:, obj.UplinkIdx));
                resourceshare(:, obj.UplinkIdx) = ((resourceshare(:, obj.UplinkIdx) ./ numRBScheduled) * 100); % Percent share
                cellTxRate(1, obj.UplinkIdx) = sum(txRate(:, obj.UplinkIdx)); % Cell Tx rate
                cellTxRate(2, obj.UplinkIdx) = obj.PeakDataRate(obj.UplinkIdx); % Peak datarate
                cellThroughputMetrics(1, obj.UplinkIdx) = sum(throughput(:, obj.UplinkIdx)); % Cell throughput
                cellThroughputMetrics(2, obj.UplinkIdx) = obj.PeakDataRate(obj.UplinkIdx); % Peak datarate
            end

            statusInfo = gNBMAC.ueInformation;
            if obj.LinkDirection ~= 1 % Downlink
                for ueIdx = 1:numUEs
                    ueMAC = ueList(ueIdx).MACEntity;
                    throughput(ueIdx, obj.DownlinkIdx) = (ueMAC.StatReceivedBytes - obj.MACRxBytes(ueIdx, obj.DownlinkIdx))* 8 / (obj.MetricsStepDuration * 1000);
                    obj.MACRxBytes(ueIdx, obj.DownlinkIdx) = ueMAC.StatReceivedBytes;
                    totalNumRBs = ueMAC.StatDLTransmissionRB + ueMAC.StatDLRetransmissionRB;
                    resourceshare(ueIdx, obj.DownlinkIdx) = totalNumRBs - obj.ResourceShareMetrics(ueIdx, obj.DownlinkIdx);
                    obj.ResourceShareMetrics(ueIdx, obj.DownlinkIdx) = totalNumRBs;
                end

                % Instant metrics calculation
                txBytes = gNBMAC.StatTransmittedBytes + gNBMAC.StatRetransmittedBytes;
                txRate(:, obj.DownlinkIdx) = (txBytes - obj.MACTxBytes(:, obj.DownlinkIdx))* 8 / (obj.MetricsStepDuration * 1000);
                bufferstatus(:, obj.DownlinkIdx) = [statusInfo.BufferSize]' ./ 1000; % In KB;

                % Cell level metrics
                numRBScheduled = sum(resourceshare(:, obj.DownlinkIdx));
                resourceshare(:, obj.DownlinkIdx) = (resourceshare(:, obj.DownlinkIdx) ./ numRBScheduled) * 100;
                cellTxRate(1, obj.DownlinkIdx) = sum(txRate(:, obj.DownlinkIdx)); % Cell Tx rate
                cellTxRate(2, obj.DownlinkIdx) = obj.PeakDataRate(obj.DownlinkIdx); % Peak datarate
                cellThroughputMetrics(1, obj.DownlinkIdx) = sum(throughput(:, obj.DownlinkIdx)); % Cell throughput
                cellThroughputMetrics(2, obj.DownlinkIdx) = obj.PeakDataRate(obj.DownlinkIdx); % Peak datarate

                % Save the previous metrics
                obj.MACTxBytes(:, obj.DownlinkIdx) = txBytes;
            end

            txRate = [txRate(obj.UEOfInterestList, :); cellTxRate];
            throughput = [throughput(obj.UEOfInterestList, :); cellThroughputMetrics];

            % Append downlink and uplink throughput values
            obj.CellThroughput = [obj.CellThroughput; cellThroughputMetrics(1,1), cellThroughputMetrics(1,2)];

            updateMACMetrics(obj, txRate', resourceshare', throughput', bufferstatus(obj.UEOfInterestList, :)');
        end

        function plotLivePhyMetrics(obj)
            %plotLivePhyMetrics Plots the Phy live metrics

            ueList = obj.UEs;
            numUEs = numel(ueList);
            blerData = zeros(numUEs, 2);
            dlBLERInfo = zeros(numUEs, 2);

            if obj.LinkDirection ~= 1 % Downlink
                for idx = 1:numUEs
                    dlBLERInfo(idx, :) = [ueList(idx).PhyEntity.StatDecodeFailures ueList(idx).PhyEntity.StatReceivedPackets];
                end
                blerData(:, obj.DownlinkIdx) = ((dlBLERInfo(:, 1) - obj.DLBLERInfo(:, 1)) ./ (dlBLERInfo(:, 2) - obj.DLBLERInfo(:, 2)));
                obj.DLBLERInfo = dlBLERInfo;
            end

            if obj.LinkDirection ~= 0 % Uplink
                ulBLERInfo = [obj.GNB.PhyEntity.StatDecodeFailures obj.GNB.PhyEntity.StatReceivedPackets];
                blerData(:, obj.UplinkIdx) = ((ulBLERInfo(:, 1) - obj.ULBLERInfo(:, 1)) ./ (ulBLERInfo(:, 2) - obj.ULBLERInfo(:, 2)));
                obj.ULBLERInfo = ulBLERInfo;
            end

            blerData = blerData(obj.UEOfInterestList, :)';

            % Calculate average BLER in the uplink and downlink directions
            numUEDL = nnz(~isnan(blerData(1,:)));
            numUEUL = nnz(~isnan(blerData(2,:)));
            avgBLERDL = sum(blerData(1,:),'omitnan')/numUEDL;
            avgBLERUL = sum(blerData(2,:),'omitnan')/numUEUL;

            % Append BLER values to the AvgBLER array
            obj.AvgBLER = [obj.AvgBLER; avgBLERDL, avgBLERUL];

            updatePhyMetrics(obj, blerData);
        end

        function updateRLCMetrics(obj, txRate)
            %updateRLCMetrics Update the RLC metrics

            txRate(isnan(txRate)) = 0; % To handle NaN

            % Determine the maximum UEs to plot the metrics
            numUEs = size(txRate, 1); % Number of UEs
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end

            % Update the plots
            if numel(obj.PlotIDs) == 1
                obj.RLCVisualization(txRate(1:numUEs, obj.PlotIDs)');
            else
                obj.RLCVisualization(txRate(1:numUEs, obj.DownlinkIdx)', txRate(1:numUEs, obj.UplinkIdx)');
            end
        end

        function updateMACMetrics(obj, txRate, resourceshare, throughput, bufferstatus)
            %updateMACMetrics Update the MAC metric plots

            % To handle NaN
            txRate(isnan(txRate)) = 0;
            resourceshare(isnan(resourceshare)) = 0;
            throughput(isnan(throughput)) = 0;
            bufferstatus(isnan(bufferstatus)) = 0;

            % Determine the maximum UEs to plot the metrics
            numUEs = size(bufferstatus, 2); % Number of UEs
            cellLevelMetricsIdx = [numUEs+1 numUEs+2];
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end
            cellLevelMetricsIdx = [(1:numUEs) cellLevelMetricsIdx];

            for plotIdx = 1:numel(obj.PlotIDs)
                plotId = obj.PlotIDs(plotIdx);
                obj.MACVisualization{plotId}(txRate(plotId, cellLevelMetricsIdx), resourceshare(plotId, 1:numUEs), throughput(plotId, cellLevelMetricsIdx), bufferstatus(plotId, 1:numUEs));
            end
        end

        function updatePhyMetrics(obj, blerData)
            %updatePhyMetrics Update the Phy metrics

            blerData(isnan(blerData)) = 0; % To handle NaN

            % Determine the maximum UEs to plot the metrics
            numUEs = size(blerData, 2); % Number of UEs
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end

            % Update the plots
            if numel(obj.PlotIDs) == 1
                obj.PhyVisualization(blerData(obj.PlotIDs, 1:numUEs));
            else
                obj.PhyVisualization(blerData(obj.DownlinkIdx, 1:numUEs), blerData(obj.UplinkIdx, 1:numUEs));
            end
        end

        function initLiveMetricPlots(obj, ~, ~)
            %initLiveMetricPlots Initialize metric plots

            networkSimulator = wirelessNetworkSimulator.getInstance();
            obj.SimTime = networkSimulator.EndTime; % Simulation time (in seconds)

            scs = obj.GNB.SubcarrierSpacing/1e3;
            % Interval at which metrics visualization updates in terms of number of
            % slots. Make sure that metric step size is an integer
            numSlotsSim = (obj.SimTime * scs)/15e-3;
            metricsStepSize = max(numSlotsSim/obj.NumMetricsSteps,1);
            obj.MetricsStepDuration = metricsStepSize * (15 / scs);
            % Create Phy visualization
            if obj.PlotPhyMetrics
                addPhyVisualization(obj);
            end

            % Create MAC visualization
            if obj.PlotSchedulerMetrics
                addMACVisualization(obj);
            end

            % Create RLC visualization
            if obj.PlotRLCMetrics
                addRLCVisualization(obj);
            end

            % Register periodic plot update event with network simulator
            if ~isempty(networkSimulator) && ~isempty(obj.GNB) && ~isempty(obj.UEs)
                scheduleAction(networkSimulator, @obj.plotLiveMetrics, [], obj.MetricsStepDuration*1e-3, obj.MetricsStepDuration*1e-3);
                if obj.PlotCDFMetrics && obj.PlotPhyMetrics % Plot BLER CDF
                    scheduleAction(networkSimulator, @obj.plotPHYCDF, [], obj.SimTime);
                end
                if obj.PlotCDFMetrics && obj.PlotSchedulerMetrics % Plot cell throughput
                    scheduleAction(networkSimulator, @obj.plotMACCDF, [], obj.SimTime);
                end
            end
        end

        function plotPHYCDF(obj, varargin)
            %plotPHYCDF Plot CDF plots for the BLER

            %  Create the visualization for BLER CDF plots
            titles = {'Average Cell DL BLER', 'Average Cell UL BLER'};
            obj.PHYCDFVisualizationFigHandle = uifigure('Name', 'ECDF of Block Error Rate (BLER)', 'HandleVisibility', 'on');
            % Use desktop theme to support dark theme mode
            matlab.graphics.internal.themes.figureUseDesktopTheme(obj.PHYCDFVisualizationFigHandle);
            subPlotAxes = createCDFVisualization(obj, obj.PHYCDFVisualizationFigHandle);

            for idx=1:numel(obj.PlotIDs)
                ax = subPlotAxes{idx};
                if obj.LinkDirection == 1 % Only uplink visualization is on
                    idx = 2;
                end
                data = obj.AvgBLER(:,idx);
                data(isnan(data)) = 0; % To handle NaN

                % Calculate and plot ecdf
                calculateAndPlotECDF(obj, ax, data, titles{idx}, 'Average BLER', 'BLER');
            end
        end

        function plotMACCDF(obj, varargin)
            %plotMACCDF Plot CDF plots for the cell throughput and average user throughput

            %  Create the visualization for cell throughput CDF plots
            titles = {'Cell DL Throughput', 'Cell UL Throughput'};
            obj.MACCDFVisualizationFigHandle = uifigure('Name', 'ECDF of Cell Throughput', 'HandleVisibility', 'on');
            % Use desktop theme to support dark theme mode
            matlab.graphics.internal.themes.figureUseDesktopTheme(obj.MACCDFVisualizationFigHandle);
            subPlotAxes = createCDFVisualization(obj, obj.MACCDFVisualizationFigHandle);

            for idx=1:numel(obj.PlotIDs)
                ax = subPlotAxes{idx};
                if obj.LinkDirection == 1 % Only uplink visualization is on
                    idx = 2;
                end
                data = obj.CellThroughput(:,idx);

                % Calculate and plot ecdf
                calculateAndPlotECDF(obj, ax, data, titles{idx}, 'Cell Throughput', 'Cell Throughput (Mbps)');
                hold off;
            end
        end

        function subPlotAxes = createCDFVisualization(obj, figureHandle)
            %createCDFVisualization Create visualization for a figure

            g = uigridlayout(figureHandle);
            g.RowHeight = {'1x'};
            g.ColumnWidth = {'1x'};
            panel = uipanel(g);
            panel.AutoResizeChildren = 'off';
            panel.BorderType = 'none';
            % Create subplot based on the PlotIDs
            subPlotAxes = cell(1,1);
            for idx=1:numel(obj.PlotIDs)
                subPlotAxes{idx} = subplot(numel(obj.PlotIDs),1,idx,'Parent', panel);
            end
        end

        function calculateAndPlotECDF(obj, ax, data, figureTitle, legendName, xLabel)
            %calculateAndPlotECDF Calculate and plot ecdf for data

            % Calculate the empirical cumulative distribution function F, evaluated at
            % x, using the data
            [x, F] = stairs(sort(data),(1:length(data))/length(data));
            % Include a starting value, required for accurate plot
            x = [x(1); x];
            F = [0; F];
            % Plot the estimated empirical cdf
            axes(ax);
            hold on;
            plot(x,F);
            % Plot a horizontal line corresponding to 5th and 95th percentile points in
            % the CDF plot
            points = [5 95];
            yline(points/100, '--');

            title(figureTitle);
            ax.YTick = 0:0.1:1;
            xlabel(xLabel);
            ylabel('ECDF');
            legend(legendName, 'Location','best');
            grid on;
            if isequal(xLabel, 'BLER') % Set x-axis limit for BLER metric plots
                ax.XLim = [0 1];
            end
            hold off;
        end
    end
end