classdef hPre6GAP < wirelessnetwork.internal.wirelessNode
    %hPre6GAP Implements pre6G access point (AP) Node
    %   AP = hPre6GAP creates a default AP.
    %
    %   AP = hPre6GAP(Name=Value) creates one or more similar APs with the
    %   specified property Name set to the specified Value. You can specify
    %   the following properties.
    %
    %   hPre6GAP properties (configurable through N-V pair only):
    %
    %   Name                 - Node name
    %   Position             - Node position
    %   NumTransmitAntennas  - Number of transmit antennas
    %   NumReceiveAntennas   - Number of receive antennas
    %   TransmitPower        - Transmit power in dBm
    %   NoiseFigure          - Noise figure in dB
    %   ReceiveGain          - Receiver antenna gain in dB
    %
    %   hPre6GAP properties (read-only):
    %
    %   ID                   - Node identifier
    %   CPUNodeID            - Node ID of CPU to which this AP is connected
    %   ConnectionState      - Connection state of AP, "Idle" or "Connected"
    %   APCellID             - Physical Cell ID of the AP, calculated as
    %                          APCellID = 3 * APIndex + CPUCellID
    %   ConnectedUEs         - Radio network temporary identifier (RNTI) of the
    %                          connected UEs
    %   UENodeIDs            - ID of the connected UEs
    %   UENodeNames          - Name of the connected UEs

    properties(SetAccess = private)
        %NoiseFigure Noise figure in dB
        %   Specify the noise figure in dB. The default value is 6.
        NoiseFigure(1,1) {mustBeNumeric, mustBeFinite, mustBeNonnegative} = 6;

        %ReceiveGain Receiver gain in dB
        %   Specify the receiver gain in dB. The default value is 0.
        ReceiveGain(1,1) {mustBeNumeric, mustBeFinite, mustBeNonnegative} = 0;

        %TransmitPower Peak transmit power of a UE in dBm
        %   Peak transmit power, specified as a finite numeric scalar.
        %   Units are in dBm. The maximum value of transmit power you can
        %   specify is 60 dBm. The default value is 23 dBm.
        TransmitPower (1,1) {mustBeNumeric, mustBeFinite, mustBeLessThanOrEqual(TransmitPower, 60)} = 23

        %NumTransmitAntennas Number of transmit antennas on UE
        %   Specify the number of transmit antennas on UE. The allowed values are
        %   1, 2, 4. The default value is 1.
        NumTransmitAntennas (1, 1) {mustBeMember(NumTransmitAntennas, ...
            [1 2 4])} = 1;

        %NumReceiveAntennas Number of receive antennas on UE
        %   Specify the number of receive antennas on UE. The allowed values are
        %   1, 2, 4. The default value is 1.
        NumReceiveAntennas (1, 1) {mustBeMember(NumReceiveAntennas, ...
            [1 2 4])} = 1;

        %CarrierFrequency Frequency of the carrier served by CPU in Hz
        %   Specify the carrier frequency in Hz. The default value is 2.6e9 Hz.
        %   It will be set according to the value passed by CPU.
        CarrierFrequency (1,1) {mustBeNumeric, mustBeFinite, mustBeGreaterThanOrEqual(CarrierFrequency, 600e6)} = 2.6e9;

        %SubcarrierSpacing Subcarrier spacing (SCS) used across the CF-mMIMO
        %   Specify the subcarrier spacing for the CF-mMIMO in Hz. All the UE(s)
        %   connecting to the AP operates in this SCS. The allowed values are
        %   15e3, 30e3, 60e3 and 120e3. The default value is 15e3.
        %   It will be set according to the value passed by CPU.
        SubcarrierSpacing (1, 1) {mustBeNumeric, mustBeMember(SubcarrierSpacing, [15e3 30e3 60e3 120e3])} = 15e3;

        %NumResourceBlocks Number of resource blocks in carrier bandwidth
        %   Specify the number of resource blocks in carrier bandwidth. In FDD
        %   mode, each of the DL and UL bandwidth contains these many resource
        %   blocks. In TDD mode, both DL and UL bandwidth share these resource
        %   blocks. It will be set according to the value passed by CPU.
        NumResourceBlocks (1,1) {mustBeNumeric, mustBeInteger, mustBeFinite, mustBeGreaterThanOrEqual(NumResourceBlocks, 4)} = 25;
    
        %ChannelBandwidth Bandwidth of the carrier served by CPU in Hz
        %   Specify the carrier bandwidth in Hz. In TDD mode, both DL and UL share
        %   single band of this size. The default value is 5e6 Hz.
        ChannelBandwidth (1,1) {mustBeMember(ChannelBandwidth, ...
            [5e6 10e6 15e6 20e6 25e6 30e6 35e6 40e6 45e6 50e6 60e6 70e6 80e6 90e6 100e6 200e6 400e6])} = 5e6;
    end

    properties (SetAccess = protected)
        %CPUNodeID Node ID of the CPU to which AP is connected
        CPUNodeID

        %ConnectionState Connection state of the AP as "Idle" or "Connected"
        ConnectionState = "Idle"

        %APCellID Physical layer cell identity for the AP.
        APCellID

        %ConnectedUEs RNTI of the UEs connected to the AP, returned as vector of integers
        ConnectedUEs

        %UENodeIDs ID of the UEs connected to the AP, returned as vector of integers
        UENodeIDs

        %UENodeNames Name of the UEs connected to the AP, returned as array of strings
        UENodeNames = strings(0,1);
    end

    properties(Access = protected, Hidden)
        %ConnectUEToCPUFcn Callback Function to add connection of UE to CPU
        ConnectUEToCPUFcn

        %LastRunTime Timestamp (in seconds) when the node last ran
        LastRunTime = [];

        %PHYAbstraction true or false depending upon PHY Abstraction method
        PHYAbstraction
    end

    properties(Hidden)
        %PhyEntity Physical layer entity
        PhyEntity
    end

    properties(Constant)
        %PHYAbstractionMethod PHY abstraction method
        % The value "none" represents full PHY processing.
        PHYAbstractionMethod = "none";
    end

    methods
        function obj = hPre6GAP(varargin)

            if nargin > 0
                % N-V pair check
                coder.internal.errorIf(mod(nargin, 2) == 1,'MATLAB:system:invalidPVPairs');
                % N-V pair validation
                param = obj.validateAPInputs(varargin);
                names = param(1:2:end);
                % Check for 'Position' N-V pair argument to calculate
                % the number of APs user intends to create
                positionIdx = find(strcmp([names{:}], 'Position'), 1, 'last');
                numAPs = 1;
                if ~isempty(positionIdx)
                    position = param{2*positionIdx}; % Read value of Position N-V argument
                    validateattributes(position, {'numeric'}, {'nonempty', 'ncols', 3, 'finite'}, mfilename, 'Position');
                    numAPs = size(position, 1);
                end
                % Check for 'Name' N-V pair argument
                nameIdx = find(strcmp([names{:}], 'Name'), 1, 'last');
                if ~isempty(nameIdx)
                    nodeName = param{2*nameIdx}; % Read value of Position N-V argument
                end
                % Create AP(s)
                obj(1:numAPs) = obj;
                for i=2:numAPs
                    obj(i) = hPre6GAP();
                end
                % Set the configuration of AP(s) as per the N-V pairs
                for i=1:2:nargin-1
                    paramName = param{i};
                    paramValue = param{i+1};
                    switch (paramName)
                        case 'Position'
                            % Set position for AP(s)
                            for j = 1:numAPs
                                obj(j).Position = position(j, :);
                            end
                        case 'Name'
                            % Set name for AP(s). If name is not supplied for all APs then leave the
                            % trailing APs with default names
                            nameCount = min(numel(nodeName), numAPs);
                            for j=1:nameCount
                                obj(j).Name = nodeName(j);
                            end
                        otherwise
                            % Make all the APs identical by setting same value for all the configurable
                            % properties, except position and name
                            [obj.(char(paramName))] = deal(paramValue);
                    end
                end
            end

            % Configure internal layers for each AP
            for idx=1:numel(obj)
                ap = obj(idx);

                subcarrierSpacingInKHz = ap.SubcarrierSpacing/1e3;

                phyParam = struct('NCellID', 1, 'TransmitPower', ap.TransmitPower, 'NumTransmitAntennas', ap.NumTransmitAntennas, ...
                    'NumReceiveAntennas', ap.NumReceiveAntennas, 'NoiseFigure', ap.NoiseFigure, 'ReceiveGain', ap.ReceiveGain, ...
                    'SubcarrierSpacing', subcarrierSpacingInKHz, 'NumResourceBlocks', ap.NumResourceBlocks,...
                    'ChannelBandwidth', ap.ChannelBandwidth, 'DLCarrierFrequency', ap.CarrierFrequency, 'ULCarrierFrequency', ap.CarrierFrequency, ...
                    'DuplexMode', "TDD");

                ap.PhyEntity = hPre6GAPLowPHY(phyParam, @ap.processEvents);
                registerTxHandle(ap.PhyEntity, @ap.addToTxBuffer);
            end
        end

        function connectUE(obj, UE, varargin)
            %connectUE Connect one or more UEs to the AP

            % First argument must be scalar object
            validateattributes(obj, {'hPre6GAP'}, {'scalar'}, mfilename, 'obj');
            validateattributes(UE, {'hPre6GUE'}, {'vector'}, mfilename, 'UE');

            if strcmp(obj.ConnectionState,'Idle')
                error('AP must be connected to the CPU before establising the connection to the UEs');
            end

            % N-V pair check
            coder.internal.errorIf(mod(numel(varargin), 2) == 1, 'MATLAB:system:invalidPVPairs');

            connectionConfigStruct = struct('RNTI', 0, 'APID', obj.ID, ...
                'GNBName', obj.Name, 'UEID', 0, 'UEName', [], 'NCellID', obj.APCellID, ...
                'SubcarrierSpacing', [], 'SchedulingType', 0, 'NumHARQ', 0, 'DuplexMode', "TDD", ...
                'CSIRSConfiguration', [], 'CSIReportConfiguration', [],  'SRSConfiguration', [], ...
                'SRSSubbandSize', [], 'NumResourceBlocks', [], 'ChannelBandwidth', [], 'DLCarrierFrequency', [], ...
                'ULCarrierFrequency', [], 'BSRPeriodicity', 5, 'CSIReportPeriodicity', [], ...
                'CSIReportPeriodicityRSRP', 1, 'RBGSizeConfiguration', 1, 'DLULConfigTDD', [], ...
                'NumTransmitAntennas', 0, 'NumReceiveAntennas', 0, 'InitialMCSIndexDL', 11,...
                'PoPUSCH', [], 'AlphaPUSCH', [], 'GNBTransmitPower', [], 'InitialMCSIndexUL', 11, ...
                'InitialCQIDL', 0, 'FullBufferTraffic', "off", ...
                'RLCBearerConfig', [], 'RVSequence', [], 'CSIMeasurementSignalDLType', 'SRS', 'CustomContext', []);

            numUEs = length(UE);
            % Initialize connection configuration for UE
            connectionConfig = connectionConfigStruct;

            % Form array of connection configuration (1 for each UE)
            for idx=1:2:nargin-2
                name = varargin{idx};
                value = nr5g.internal.nrNodeValidation.validateConnectUEInputs(name, varargin{idx+1});
                % Set same value per connection
                [connectionConfig.(char(name))] = deal(value);
            end

            % Information to configure connection information at AP PHY
            phyConnectionParam = ["RNTI", "UEID", "UEName", "SRSSubbandSize", "SRSConfiguration", "NumHARQ", "DuplexMode"];

            cpuCellIDOfAP = hPre6GAP.getCPUCellID(obj.APCellID);
            for i=1:numUEs
                %Check if the UE is connected to the AP
                if strcmp(UE(i).ConnectionState, "Connected") && ismember(UE(i).RNTI, obj.ConnectedUEs)
                    error("UE at index "+i+" is already connected to the AP");
                end

                if ~isempty(UE(i).NCellID)
                    cpuCellIDOfUE = hPre6GAP.getCPUCellID(UE(i).NCellID);
                    %Check whether the UE is connected to a different CPU or not
                    if cpuCellIDOfAP ~= cpuCellIDOfUE
                        error('UE at index %d is already connected to a different CPU', i);
                    end
                end
                
                connectionConfig.UEID = UE(i).ID;
                connectionConfig.UEName = UE(i).Name;
                connectionConfig.NumTransmitAntennas = UE(i).NumTransmitAntennas;
                connectionConfig.NumReceiveAntennas = UE(i).NumReceiveAntennas;

                % Pass the UE connection context to the CPU
                connectionConfig = obj.ConnectUEToCPUFcn(UE(i), connectionConfig);

                % Update list of connected UEs
                obj.ConnectedUEs(end+1) = connectionConfig.RNTI;
                obj.UENodeIDs(end+1) = UE(i).ID;
                obj.UENodeNames(end+1) = UE(i).Name;

                if ~isempty(connectionConfig.SRSConfiguration)
                    connectionConfig.SRSConfiguration.NSRSID = obj.APCellID;
                end
                if ~isempty(connectionConfig.CSIRSConfiguration)
                    connectionConfig.CSIRSConfiguration.NID = obj.APCellID;
                end

                phyConnectionInfo = struct();
                for j=1:numel(phyConnectionParam)
                    phyConnectionInfo.(phyConnectionParam(j)) = connectionConfig.(phyConnectionParam(j));
                end
                obj.PhyEntity.addConnection(phyConnectionInfo);

                UE(i).addConnection(connectionConfig);
            end

        end

        function nextInvokeTime = run(obj, currentTime)
            %run Run the Pre6G AP node and return the next invoke time (in nanoseconds)

            obj.LastRunTime = currentTime;
            lastRunTimeInNanoseconds = round(currentTime * 1e9); % Convert time into nanoseconds

            if obj.ReceiveBufferIdx ~= 0 % Rx buffer has data to be processed
                % Pass the data to layers for processing
                nextInvokeTime = run(obj.PhyEntity, lastRunTimeInNanoseconds, [obj.ReceiveBuffer{1:obj.ReceiveBufferIdx}]);
                obj.ReceiveBufferIdx = 0;
            else
                nextInvokeTime = run(obj.PhyEntity, lastRunTimeInNanoseconds, []);
            end
            nextInvokeTime = nextInvokeTime * 1e-9;
        end
    end

    methods(Hidden)
        function addConnection(obj, connectionConfig, connectUEToCPUFcn)
            %addConnection Add connection context to AP, and set the
            % properties sent by CPU in connectionConfig

            apConnectionParam = ["CPUNodeID", "CarrierFrequency",...
                "SubcarrierSpacing", "NumResourceBlocks", "ReceiveFrequency"];
            % Set AP parameters
            for j=1:numel(apConnectionParam)
                obj.(apConnectionParam(j)) = connectionConfig.(apConnectionParam(j));
            end
            % Get AP Cell ID from AP Index and CPU Cell ID
            obj.APCellID = hPre6GAP.getAPCellID(connectionConfig.APIndex, connectionConfig.CPUCellID);

            % Set CPU connection context function to send UE connection context
            % to CPU
            obj.ConnectUEToCPUFcn = connectUEToCPUFcn;

            % Add connection to LowPHY Layer.
            phyParam = ["CPUNodeID", "DuplexMode", "ChannelBandwidth", "DLCarrierFrequency", ...
                "ULCarrierFrequency", "NumResourceBlocks", "SubcarrierSpacing",...
                "CQITable", "Split", "DLULConfigTDD"];
            phyInfo = struct();
            for j=1:numel(phyParam)
                phyInfo.(phyParam(j)) = connectionConfig.(phyParam(j));
            end
            phyInfo.NCellID = obj.APCellID;
            subcarrierSpacingInKHZ = connectionConfig.SubcarrierSpacing/1e3;
            phyInfo.SubcarrierSpacing = subcarrierSpacingInKHZ;
            obj.PhyEntity.addConnectionToCPU(phyInfo);

            % Modify the connection status
            obj.ConnectionState = "Connected";
        end

        function updateSRSPeriod(obj, rnti, srsPeriod)
            %updateSRSPeriod Update the period of existing SRS configuration

            updateSRSPeriod(obj.PhyEntity, rnti, srsPeriod);
        end

        function addToTxBuffer(obj, packet)
            %addToTxBuffer Adds the packet to the transmit Buffer

            packet.TransmitterID = obj.ID;
            packet.TransmitterPosition = obj.Position;

            packet.Metadata.LastTransmitterType = "AP";
            obj.TransmitterBuffer = [obj.TransmitterBuffer packet];
        end

        function pushReceivedData(obj, packet)
            %pushReceivedData Push the received packet to node

            % Copy the received packet to the buffer
            obj.ReceiveBufferIdx = obj.ReceiveBufferIdx + 1;
            obj.ReceiveBuffer{obj.ReceiveBufferIdx} = packet;
        end
        
        function [flag, rxInfo] = isPacketRelevant(obj, packet)
            %isPacketRelevant Check whether packet is relevant for the node

            [flag, rxInfo] = isPacketRelevant@wirelessnetwork.internal.wirelessNode(obj, packet);
            rxInfo.NumReceiveAntennas = obj.NumReceiveAntennas;

            % Reject packets from other APs
            if strcmp(packet.Metadata.LastTransmitterType, "AP")
                flag = false;
            end
        end

        function processEvents(obj, eventName, data)
            % Send the event notification to listeners

            if event.hasListener(obj, eventName)
                data.CurrentTime = obj.LastRunTime;
                % Create an event data object
                eventDataObj = wirelessnetwork.internal.nodeEventData;
                eventDataObj.Data = data;
                % Notify listeners about the event
                notify(obj, eventName, eventDataObj);
            end
        end
    end

    methods(Access=private)
        function param = validateAPInputs(~, param)
            %validateAPInputs Validates AP input parameters

            allowedProps = ["Name", "Position", "TransmitPower", "ReceiveGain", "NoiseFigure", ...
                "NumTransmitAntennas", "NumReceiveAntennas"];

            % Convert the character vectors to strings
            paramLength = numel(param);
            for idx=1:2:paramLength
                param{idx} = string(param{idx});
                if isstring(param{idx+1})||ischar(param{idx+1})||iscellstr(param{idx+1})
                    param{idx+1} = string(param{idx+1});
                end
            end
            names = [param{1:2:end}];
            unMatchedNamesFlag = ~ismember(names, allowedProps);
            coder.internal.errorIf(sum(unMatchedNamesFlag) > 0, 'nr5g:nrNode:InvalidNVPair', names(find(unMatchedNamesFlag, 1)))
        end
    end

    methods(Static, Hidden)
        function apCellID = getAPCellID(apIndex, cpuCellID)
            %getAPCellID Calculate AP Cell ID using AP index (Index of AP at CPU)
            % and CPU Cell ID

            validateattributes(apIndex, {'numeric'}, {'scalar', 'integer', 'nonnegative'}, mfilename, 'AP Index');
            validateattributes(cpuCellID, {'numeric'}, {'scalar', 'integer', 'nonnegative'}, mfilename, 'CPU Cell ID');

            apCellID = (3 * apIndex) + cpuCellID;
        end

        function id = getCPUCellID(apCellID)
            %getCPUCellID Calculate CPU Cell ID using the AP Cell ID

            validateattributes(apCellID, {'numeric'}, {'scalar', 'integer', 'nonnegative'}, mfilename, 'AP Cell ID');

            id = mod(apCellID, 3);
        end
    end
end