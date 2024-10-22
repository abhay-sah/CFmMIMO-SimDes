classdef hPre6GCPU < nrGNB
    %hPre6GCPU Implements pre6G CPU Node
    %   CPU = hPre6GCPU creates a default CPU.
    %
    %   CPU = hPre6GCPU(Name=Value) creates one or more similar CPUs with the
    %   specified property Name set to the specified Value. You can specify all the properties that
    %   are there in nrGNB along with some new properties listed below.
    %
    %   hPre6GCPU properties (configurable through N-V pair only):
    %
    %   Split                - Can Be defined as "Centralized", "7.2x" or "Distributed"
    %
    %   hPre6GCPU properties (read-only):
    %
    %   ID                   - Node identifier
    %   ConnectedAPs         - Node ID of APs connected to the CPU
    %   UEsToAPsMap          - A map of UE RNTI to AP Node IDs

    properties(SetAccess=protected)
        %UEsToAPsMap It is an array which stores all the AP Node ID a UE is
        %connected.
        UEsToAPsMap

        %ConnectedAPs Node Id of connected APs
        ConnectedAPs

        %Split Specify the Split as "Centralized" or "Distributed" or "7.2x"
        %   The value "Centralized" represents centralized realization of Cell-Free.
        %   The value "Distributed" represents distributed realization of Cell-Free.
        %   The value "7.2x" represents Cell-Free will follow 7.2x Split of O-RAN Standards.
        %   The default value is "Centralized"
        Split = "Centralized"
    end

    properties(SetAccess = protected, Hidden)
        %ConnectedAPNodes Cell array of AP node objects connected to the CPU
        ConnectedAPNodes = {}
    end

    % Constant, hidden properties
    properties (Constant,Hidden)
        %Split_Values Splits supported by hPre6G CPU
        Split_Values  = ["Centralized", "Distributed", "7.2x"];
    end

    methods
        function obj = hPre6GCPU(varargin)
            % Initialize the pre6gCPU object

            % N-V pair check
            coder.internal.errorIf(mod(nargin, 2) == 1,'MATLAB:system:invalidPVPairs');

            % Remove the CPU specific param from the varargin
            [gNBParam, split] = hPre6GCPU.getGNBParam(varargin);

            % Check for position matrix
            names = gNBParam(1:2:end);
            positionIdx = find(strcmp([names{:}], 'Position'), 1, 'last');
            if ~isempty(positionIdx)
                position = gNBParam{2*positionIdx}; % Read value of Position N-V argument
                if size(position,1) > 1
                    error("Does not support vectorized initialization, Create one CPU at a time")
                end
            end

            obj = obj@nrGNB(gNBParam{:}); % Call base class constructor
            obj.Split = split;

            % Param for internal layer of CPU
            macParam = ["NCellID", "NumHARQ", "SubcarrierSpacing", ...
                "NumResourceBlocks", "DuplexMode","DLULConfigTDD"];
            phyParam = ["NCellID", "DuplexMode", "ChannelBandwidth", "DLCarrierFrequency", ...
                "ULCarrierFrequency", "NumResourceBlocks", "TransmitPower", ...
                "NumTransmitAntennas", "NumReceiveAntennas", "NoiseFigure", ...
                "ReceiveGain", "SubcarrierSpacing", "CQITable", "MCSTable", "Split"];

            for idx=1:numel(obj) % For each CPU
                CPU = obj(idx);
                % Get NCellID/CPUCellID for the CPU
                CPU.NCellID = CPU.generateCPUCellID();
                % Check CPU Cell ID (must be less then 3)
                if CPU.NCellID > 2
                    error("CPU at index %d exceeds the NCellID limit of 2", idx);
                end
                % PHY Abstraction must be none.
                if ~strcmp(CPU.PHYAbstractionMethod, "none")
                    error('Set PHYAbstractionMethod = "none" as a N-V pair');
                end

                % Set up MAC
                macInfo = struct();
                for j=1:numel(macParam)
                    macInfo.(macParam(j)) = CPU.(macParam(j));
                end
                % Convert the SCS value from Hz to kHz
                subcarrierSpacingInKHZ = CPU.SubcarrierSpacing/1e3;
                macInfo.SubcarrierSpacing = subcarrierSpacingInKHZ;
                CPU.MACEntity = hPre6GCPUMAC(macInfo, @CPU.processEvents);

                % Set up PHY
                phyInfo = struct();
                for j=1:numel(phyParam)
                    phyInfo.(phyParam(j)) = CPU.(phyParam(j));
                end
                phyInfo.SubcarrierSpacing = subcarrierSpacingInKHZ;
                CPU.PhyEntity = hPre6GCPUFullPHY(phyInfo, @CPU.processEvents); % Full PHY
                CPU.PHYAbstraction = 0;

                % Configure the Scheduler for the CPU
                configureScheduler(CPU, Scheduler=hPre6GScheduler());
                CPU.SchedulerDefaultConfig = true;
                CPU.MACEntity.Scheduler.EnableCustomSchedulingValidation = false;

                % Set inter-layer interfaces
                CPU.setLayerInterfaces();
            end
        end

        function connectAP(obj, AP)
            %connectAP Connect one or more APs to the CPU

            % First argument must be scalar object
            validateattributes(obj, {'hPre6GCPU'}, {'scalar'}, mfilename, 'obj');
            validateattributes(AP, {'hPre6GAP'}, {'vector'}, mfilename, 'AP');

            coder.internal.errorIf(~isempty(obj.LastRunTime), 'nr5g:nrNode:NotSupportedOperation', 'ConnectAP');

            connectionConfigStruct = struct('CPUCellID', obj.NCellID, 'CPUNodeID', obj.ID, ...
                'CarrierFrequency', obj.CarrierFrequency, 'SubcarrierSpacing', obj.SubcarrierSpacing, ...
                'NumResourceBlocks', obj.NumResourceBlocks, 'ReceiveFrequency', obj.ReceiveFrequency, ...
                'ChannelBandwidth', obj.ChannelBandwidth, 'DLCarrierFrequency', obj.DLCarrierFrequency, ...
                'ULCarrierFrequency', obj.ULCarrierFrequency, 'DuplexMode', obj.DuplexMode, ...
                'Split', obj.Split, 'CQITable', obj.CQITable, 'DLULConfigTDD', obj.DLULConfigTDD, ...
                'InitialMCSIndexUL', 11, 'InitialCQIDL', 0);

            numAPs = length(AP);
            % Initialize connection configuration for the APs
            connectionConfig = connectionConfigStruct;

            % Set connection for each AP
            for i=1:numAPs
                if numAPs == 1
                    if strcmp(AP(i).ConnectionState, "Connected") && ismember(AP(i).ID, obj.ConnectedAPs)
                        error('The AP is already connected to the CPU');
                    end
                    if strcmp(AP(i).ConnectionState, "Connected") && ~isempty(AP(i).CPUNodeID)
                        error(['The AP is already connected to a CPU with NodeID ' AP(i).CPUNodeID]);
                    end
                else
                    if strcmp(AP(i).ConnectionState, "Connected") && ismember(AP(i).ID, obj.ConnectedAPs)
                        error("The AP at index "+i+" is already connected to the CPU");
                    end
                    if strcmp(AP(i).ConnectionState, "Connected") && ~isempty(AP(i).CPUNodeID)
                        error("The AP at index " +i+ " is already connected to a CPU with NodeID"+AP(i).CPUNodeID);
                    end
                end

                apIndex = length(obj.ConnectedAPNodes) + 1;
                % Update connection information
                connectionConfig.APIndex = apIndex;

                % Add PHY connection context
                phyConnectionParam = ["ID", "NumTransmitAntennas"];
                for j=1:numel(phyConnectionParam)
                    phyConnectionInfo.(phyConnectionParam(j)) = AP(i).(phyConnectionParam(j));
                end
                obj.PhyEntity.addConnectionToAP(phyConnectionInfo);

                % Update the list of connected APs
                obj.ConnectedAPs(end+1) = AP(i).ID;
                obj.ConnectedAPNodes{end+1} = AP(i);

                % Add connection in AP
                AP(i).addConnection(connectionConfig, @obj.connectUEViaAP);
            end

        end

        function configureScheduler(obj, varargin)
            %configureScheduler Configure scheduler at the CPU

            validateattributes(obj, {'hPre6GCPU'}, {'scalar'}, mfilename, 'obj');
            
            coder.internal.errorIf(any(~cellfun(@isempty, {obj.LastRunTime})), 'nr5g:nrNode:NotSupportedOperation', 'configureScheduler');
            coder.internal.errorIf(any(~cellfun(@isempty, {obj.ConnectedUEs})), 'nr5g:nrGNB:ConfigSchedulerAfterConnectUE');
            coder.internal.errorIf(any(~[obj.SchedulerDefaultConfig]),'nr5g:nrGNB:MultipleConfigureSchedulerCalls')

            if nargin>1
                coder.internal.errorIf(mod(nargin-1, 2) == 1,'MATLAB:system:invalidPVPairs');
                schedulerInfo = struct(Scheduler='RoundRobin', PFSWindowSize=20, ResourceAllocationType=1, ...
                    FixedMCSIndexUL=[], FixedMCSIndexDL=[], MaxNumUsersPerTTI=8, ...
                    MUMIMOConfigDL=[], LinkAdaptationConfigDL=[], LinkAdaptationConfigUL=[], RVSequence=obj(1).RVSequence, CSIMeasurementSignalDL="SRS");

                isCustomScheduler = false;
                % Get the user specified parameters for scheduler
                for idx=1:2:nargin-1
                    name = varargin{idx};
                    schedulerInfo.(char(name)) = nr5g.internal.nrNodeValidation.validateConfigureSchedulerInputs(name, varargin{idx+1});
                    if name=="Scheduler" && isa(schedulerInfo.Scheduler, 'nrScheduler')
                        isCustomScheduler = 1;
                    elseif name=="RVSequence"
                        obj.RVSequence = schedulerInfo.RVSequence;
                    end
                end

                coder.internal.errorIf(~isempty(schedulerInfo.MUMIMOConfigDL) && strcmp(schedulerInfo.CSIMeasurementSignalDL, "SRS"),'nr5g:nrGNB:InvalidDLCSIConfigWithMUMIMO','CSIMeasurementSignalDL','MUMIMOConfigDL');

                % If user has supplied a custom scheduler then keep only
                % relevant configuration
                if isCustomScheduler
                    % Read user-supplied scheduler object
                    scheduler = schedulerInfo.Scheduler;
                    customSchedulerParam = struct(Scheduler=[], ResourceAllocationType=1, MaxNumUsersPerTTI=8, RVSequence=[0 3 2 1], CSIMeasurementSignalDL="SRS");
                    fields = fieldnames(customSchedulerParam);
                    for i=1:length(fields)
                        customSchedulerParam.(char(fields{i})) = schedulerInfo.(char(fields{i}));
                    end
                    schedulerInfo = customSchedulerParam;
                end
                % Get the required parameters for scheduler from node
                schedulerParam = ["DuplexMode", "NumResourceBlocks", "DLULConfigTDD", ...
                    "NumHARQ", "NumTransmitAntennas", "NumReceiveAntennas", "SRSReservedResource", "SubcarrierSpacing"];
                for nodeIdx = 1:numel(obj)
                    gNB = obj(nodeIdx);
                    for idx=1:numel(schedulerParam)
                        schedulerInfo.(schedulerParam(idx)) = gNB.(schedulerParam(idx));
                    end
                    obj(nodeIdx).CSIMeasurementSignalDLType = strcmp(schedulerInfo.CSIMeasurementSignalDL, "SRS");
                    % Convert the SCS value from Hz to kHz
                    schedulerInfo.SubcarrierSpacing = gNB.SubcarrierSpacing/1e3;
                    % Get the DMRSTypeAPosition from gNB MAC
                    schedulerInfo.DMRSTypeAPosition = gNB.MACEntity.DMRSTypeAPosition;
                    addScheduler(gNB.MACEntity, scheduler(nodeIdx));
                    configureScheduler(scheduler(nodeIdx), schedulerInfo);
                    if strcmp(gNB.PHYAbstractionMethod, "none")
                        gNB.PhyEntity.RVSequence = schedulerInfo.RVSequence;
                    end
                    gNB.SchedulerDefaultConfig = false;
                end
            end
        end


        function connectUE(~, ~)
            % CPU does not suport this function
            error('This method is not supported in CF-mMIMO. CPU uses connectUEViaAP method to connect UE');
        end
    end

    methods(Hidden)
        function connectionConfig = connectUEViaAP(obj, UE, connectionConfig)
            %connectUEViaAP Add or update connection context of UE and return the connection configuration
            % to the AP.

            coder.internal.errorIf(~isempty(obj.LastRunTime), 'nr5g:nrNode:NotSupportedOperation', 'Connect UE Via AP');

            % Information to configure connection parameters at CPU MAC
            macConnectionParam = ["RNTI", "UEID", "UEName", "APID", "SRSConfiguration", "CSIRSConfiguration", "InitialCQIDL"];
            % Information to configure connection information at CPU PHY
            phyConnectionParam = ["RNTI", "UEID", "UEName", "APID", "SRSSubbandSize", "NumHARQ", "DuplexMode", "CSIMeasurementSignalDLType"];
            % Information to configure connection information at CPU scheduler
            schedulerConnectionParam = ["RNTI", "UEID", "UEName", "NumTransmitAntennas", "NumReceiveAntennas", ...
                "CSIRSConfiguration", "SRSConfiguration", "SRSSubbandSize", "InitialCQIDL", "InitialMCSIndexUL","CustomContext"];
            % Information to configure connection information at CPU RLC
            rlcConnectionParam = ["RNTI", "FullBufferTraffic", "RLCBearerConfig"];

            % Set initial CQI for the DL transmission
            connectionConfig.InitialCQIDL = nrGNB.getCQIIndex(connectionConfig.InitialMCSIndexDL);

            apIndex = floor(connectionConfig.NCellID / 3);

            % Calculate total number of transmit antennas for a UE
            numTxAntennasForUE = obj.ConnectedAPNodes{apIndex}.NumTransmitAntennas;
            for i=1:numel(UE.APCellIDs)
                idx = floor(UE.APCellIDs(i) / 3);
                numTxAntennasForUE = numTxAntennasForUE + obj.ConnectedAPNodes{idx}.NumTransmitAntennas;
            end

            if ~strcmp(UE.ConnectionState, "Connected")
                % Add UE connection to the CPU

                configParam = ["SubcarrierSpacing", "NumHARQ", "DuplexMode", "NumResourceBlocks", "ChannelBandwidth", ...
                    "DLCarrierFrequency", "ULCarrierFrequency", "DLULConfigTDD", "CSIReportType", "CSIRSConfiguration", ...
                    "RVSequence", "CSIMeasurementSignalDLType"];
                for j=1:numel(configParam)
                    connectionConfig.(configParam(j)) = obj.(configParam(j));
                end

                % Only supports SRS Based DL CSI
                connectionConfig.CSIMeasurementSignalDLType = true;

                % Configure UL power control parameters
                connectionConfig.PoPUSCH = obj.ULPowerControlParameters.PoPUSCH;
                connectionConfig.AlphaPUSCH = obj.ULPowerControlParameters.AlphaPUSCH;

                % Generate UE RNTI
                rnti = length(obj.ConnectedUEs)+1;
                connectionConfig.RNTI = rnti;

                % Find Free SRS resource index and update that
                freeSRSIndex = find(obj.SRSOccupancyStatus==0, 1); % First free SRS resource index
                if isempty(freeSRSIndex)
                    % No free SRS configuration. Increase the per-UE periodicity
                    % of SRS to accommodate more UEs
                    updateSRSPeriodicity(obj);
                    freeSRSIndex = find(obj.SRSOccupancyStatus==0, 1); % First free SRS resource index
                end
                % Fill connection configuration
                srsConfig = obj.SRSConfiguration(freeSRSIndex);
                srsConfig.NumSRSPorts = UE.NumTransmitAntennas;
                srsConfig.NSRSID = obj.NCellID;    % This is for internal Layers of CPU
                connectionConfig.SRSConfiguration = srsConfig;

                % Validate connection information
                connectionConfig = nr5g.internal.nrNodeValidation.validateConnectionConfig(connectionConfig);
                connectionConfig.CSIReportConfiguration.CQITable = obj.CQITable;
                % Clear the CSIRS Configuration
                connectionConfig.CSIRSConfiguration = [];

                % Mark the SRS resource as occupied
                obj.SRSConfiguration(freeSRSIndex) = srsConfig;
                obj.SRSOccupancyStatus(freeSRSIndex) = 1;

                % Update list of connected UEs
                obj.ConnectedUEs(end+1) = rnti;
                obj.UENodeIDs(end+1) = UE.ID;
                obj.UENodeNames(end+1) = UE.Name;
                obj.ConnectedUENodes{end+1} = UE;
                % Update the UE to AP connection map
                obj.UEsToAPsMap{rnti} = connectionConfig.APID;
            else
                % Update UE connection to the CPU

                % Get UE RNTI
                rnti = UE.RNTI;
                % Fill connection config
                connectionConfig.RNTI = rnti;
                connectionConfig.SRSConfiguration = obj.SRSConfiguration(rnti);
                % Update the UE to AP connection map
                obj.UEsToAPsMap{rnti}(end+1) = connectionConfig.APID;
            end

            % Connection context to CPU MAC
            macConnectionInfo = struct();
            for j=1:numel(macConnectionParam)
                macConnectionInfo.(macConnectionParam(j)) = connectionConfig.(macConnectionParam(j));
            end
            if ~strcmp(UE.ConnectionState, "Connected")
                obj.MACEntity.addConnection(macConnectionInfo);
            else
                obj.MACEntity.updateConnection(macConnectionInfo);
            end

            % Connection context to CPU PHY
            phyConnectionInfo = struct();
            for j=1:numel(phyConnectionParam)
                phyConnectionInfo.(phyConnectionParam(j)) = connectionConfig.(phyConnectionParam(j));
            end
            if ~strcmp(UE.ConnectionState, "Connected")
                obj.PhyEntity.addConnection(phyConnectionInfo);
                connectionConfig.GNBTransmitPower = obj.PhyEntity.scaleTransmitPower;
            else
                obj.PhyEntity.updateConnection(phyConnectionInfo);
            end

            % Connection context to CPU scheduler
            schedulerConnectionInfo = struct();
            for j=1:numel(schedulerConnectionParam)
                schedulerConnectionInfo.(schedulerConnectionParam(j)) = connectionConfig.(schedulerConnectionParam(j));
            end
            schedulerConnectionInfo.NumTransmitAntennasForUE = numTxAntennasForUE;
            if ~strcmp(UE.ConnectionState, "Connected")
                obj.MACEntity.Scheduler.addConnectionContext(schedulerConnectionInfo);
            else
                obj.MACEntity.Scheduler.updateConnectionContext(schedulerConnectionInfo);
            end

            % Connection context to CPU RLC entity
            rlcConnectionInfo = struct();
            for j=1:numel(rlcConnectionParam)
                rlcConnectionInfo.(rlcConnectionParam(j)) = connectionConfig.(rlcConnectionParam(j));
            end
            obj.FullBufferTraffic(rnti) = rlcConnectionInfo.FullBufferTraffic;
            addRLCBearer(obj, rlcConnectionInfo);
        end

        function addToTxBuffer(obj, packet)
            %addToTxBuffer Adds the packet to the Transmit Buffer

            packet.Metadata.LastTransmitterType = 'CPU';
            addToTxBuffer@wirelessnetwork.internal.nrNode(obj, packet);
        end

        function pushReceivedData(obj, packet)
            %pushReceivedData Adds the packet to Receive Buffer

            % PUSCH and SRS packets are added to the receiver buffer
            if(packet.Metadata.DirectID == 0)
                packet.DirectToDestination = 0;
            else
                packet.DirectToDestination = obj.ID;
            end

            if ~packet.DirectToDestination && (packet.Abstraction ~= obj.PHYAbstraction)
                coder.internal.error('nr5g:nrNode:MixedPHYFlavorNotSupported')
            end

            obj.ReceiveBufferIdx = obj.ReceiveBufferIdx + 1;
            obj.ReceiveBuffer{obj.ReceiveBufferIdx} = packet;
        end

        function [flag, rxInfo] = isPacketRelevant(obj, packet)
            %isPacketRelevant Checks the relevance of the in-band packets
            [~, rxInfo] = isPacketRelevant@wirelessnetwork.internal.wirelessNode(obj, packet);

            %Reject all in-band packet
            flag = false;
        end
    end

    methods(Access=protected)
        function updateSRSPeriodicity(obj)
            %updateSRSPeriodicity Updates SRS periodicity of each UE and
            % sends the information to each Ap of interesrt

            % Call updateSRSPeriodicity from base class
            updateSRSPeriodicity@nrGNB(obj);

            % Send the updated info to each AP of interest
            for j=1:length(obj.ConnectedUEs)
                rnti = obj.ConnectedUEs(j);
                newSRSPeriod = obj.SRSConfiguration(j).SRSPeriod;
                apIDs = obj.UEsToAPsMap{rnti};
                for i=1:length(apIDs)
                    idx = obj.ConnectedAPs == apIDs(i);
                    obj.ConnectedAPNodes{idx}.updateSRSPeriod(rnti, newSRSPeriod);
                end
            end
        end
    end

    methods(Access=private, Static)
        function [gnbParams, splitVal] = getGNBParam(param)
            %getGNBParam returns gNB specific parameters which can be passed through GNB after
            %removing Split type from CPU parameters and return it separately

            paramLength = numel(param);
            gnbParams = {};
            splitVal = "Centralized";
            notAllowedParams = ["TransmitPower", ...
                "NoiseFigure", "ReceiveGain", "CSIMeasurementSignalDLType"];

            for idx=1:2:paramLength
                paramName = string(param{idx});
                if any(paramName == notAllowedParams)
                    error(['hPre6GCPU does not support "' char(paramName) '" as a NV pair'])
                elseif ~strcmp(paramName, "Split")
                    gnbParams = [gnbParams {paramName, param{idx+1}}];
                else
                    if isstring(param{idx+1})||ischar(param{idx+1})||iscellstr(param{idx+1})
                        splitVal = string(param{idx+1});
                    end
                end
            end

            % Set PHYAbstractionMethod to use Full PHY and duplex mode to TDD
            gnbParams = [gnbParams {"PHYAbstractionMethod", "none"} {"DuplexMode", "TDD"}];

            % Validate Split
            validateattributes(splitVal, {'string','char'}, {'nonempty', 'scalartext'}, mfilename, 'Split')
            splitVal = validatestring(splitVal, hPre6GCPU.Split_Values, mfilename, "Split");
        end

        function varargout = generateCPUCellID(varargin)
            % Generate/Reset the CPU Cell ID counter
            %
            % ID = generateCPUCellID() Returns the next CPU Cell ID.
            persistent count;
            if(isempty(varargin))
                if isempty(count)
                    count = 0;
                else
                    count = count + 1;
                end
                varargout{1} = count;
            else
                count = -1;
            end
        end
    end

    methods (Static)
        function reset()
            %reset Reset the CPU Cell ID counter
            %
            % reset() Reset the CPU Cell ID counter.
            hPre6GCPU.generateCPUCellID(0);
        end
    end
end