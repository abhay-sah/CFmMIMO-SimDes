classdef pre6GCPU < nrGNB
    %pre6GCPU CPU Node for pre6G simulation
    %   CPU = pre6GCPU creates a default CPU.
    %
    %   CPU = pre6GCPU(Name=Value) creates one or more similar CPUs with the
    %   specified property Name set to the specified Value. You can Specify all the properties that
    %   are there in nrGNB along with some new properties listed below.
    %
    %   pre6GCPU properties (configurable through N-V pair only):
    %
    %   Split                - Can Be defined as "Centralized", "7.2x" or "Distributed"
    %
    %   pre6GCPU properties (read-only):
    %
    %   ID                   - Node identifier
    %   ConnectedAPs         - Node ID of APs connected to the CPU
    %   UEsToAPsMap          - A map of UE RNTI to AP Node IDs

    properties(SetAccess=protected)
        %UEsToAPsMap Element at index 'i' stores all the AP Node ID of those APs
        % to whom a UE with RNTI=i is connected
        UEsToAPsMap

        %ConnectedAPs Node Id of connected APs
        ConnectedAPs

        %Split Specify the Split as "Centralized" or "Distributed" or "7.2x"
        %   The value "Centralized" represents Centralized Realization of Cell-Free.
        %   The value "Distributed" represents Distributed Realization of Cell-Free.
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
        %Split_Values Splits supported by pre6g CPU
        Split_Values  = ["Centralized", "Distributed", "7.2x"];
    end

    methods
        function obj = pre6GCPU(varargin)
            % Initialize the pr6gCPU object

            % Name-value pair check
            coder.internal.errorIf(mod(nargin, 2) == 1,'MATLAB:system:invalidPVPairs');

            % Remove the CPU specific param form from the vararrgin
            [gNBParam, split] = pre6GCPU.getGNBParam(varargin);

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
                "ReceiveGain", "SubcarrierSpacing", "CQITable", "Split"];

            for idx=1:numel(obj) % For each CPU
                CPU = obj(idx);
                % Get NCellID / CPUCellID for the CPU
                CPU.NCellID = CPU.generateCPUCellID();
                % Check CPU Cell ID (must be less then 3)
                if CPU.NCellID > 2
                    error("CPU at index %d exceeds the NCellID limit of 2", idx);
                end
                % PHY Abstraction must be none.
                if ~strcmp(CPU.PHYAbstractionMethod, "none")
                    error('Provide PHYAbstractionMethod="none" as a N-V pair');
                end

                % Set up MAC
                macInfo = struct();
                for j=1:numel(macParam)
                    macInfo.(macParam(j)) = CPU.(macParam(j));
                end
                % Convert the SCS value from Hz to kHz
                subcarrierSpacingInKHZ = CPU.SubcarrierSpacing/1e3;
                macInfo.SubcarrierSpacing = subcarrierSpacingInKHZ;
                CPU.MACEntity = pre6GCPUMAC(macInfo, @CPU.processEvents);

                % Set up PHY
                phyInfo = struct();
                for j=1:numel(phyParam)
                    phyInfo.(phyParam(j)) = CPU.(phyParam(j));
                end
                phyInfo.SubcarrierSpacing = subcarrierSpacingInKHZ;
                if strcmp(CPU.PHYAbstractionMethod, "none")
                    CPU.PhyEntity = pre6GCPUFullPHY(phyInfo, @CPU.processEvents); % Full PHY
                    CPU.PHYAbstraction = 0;
                end

                % Configure the Scheduler for the CPU
                configureScheduler(CPU, Scheduler=pre6GScheduler());
                CPU.SchedulerDefaultConfig = true;
                CPU.MACEntity.Scheduler.EnableCustomSchedulingValidation = false;

                % Set inter-layer interfaces
                CPU.setLayerInterfaces();
            end
        end

        function connectAP(obj, AP)
            %connectAP Connect one or more APs to the CPU
            %
            %   connectAP(OBJ, AP) connects one or more APs to CPU.

            % First argument must be scalar object
            validateattributes(obj, {'pre6GCPU'}, {'scalar'}, mfilename, 'obj');
            validateattributes(AP, {'pre6GAP'}, {'vector'}, mfilename, 'AP');

            coder.internal.errorIf(~isempty(obj.LastRunTime), 'nr5g:nrNode:NotSupportedOperation', 'ConnectAP');

            connectionConfigStruct = struct('CPUCellID', obj.NCellID, 'CPUNodeID', obj.ID, ...
                'CarrierFrequency', obj.CarrierFrequency, 'SubcarrierSpacing', obj.SubcarrierSpacing, ...
                'NumResourceBlocks', obj.NumResourceBlocks, 'ReceiveFrequency', obj.ReceiveFrequency, ...
                'ChannelBandwidth', obj.ChannelBandwidth, 'DLCarrierFrequency', obj.DLCarrierFrequency, ...
                'ULCarrierFrequency', obj.ULCarrierFrequency, 'DuplexMode', obj.DuplexMode, ...
                'Split', obj.Split, 'CQITable', obj.CQITable, 'DLULConfigTDD', obj.DLULConfigTDD);

            numAPs = length(AP);
            % Initialize connection configuration array for APs
            connectionConfigList = repmat(connectionConfigStruct, numAPs, 1);

            % Set connection for each AP
            for i=1:numAPs
                if numAPs == 1
                    if strcmpi(AP(i).ConnectionState, "Connected") && ismember(AP(i).ID, obj.ConnectedAPs)
                        error('The AP is already connected to the CPU');
                    end
                    if strcmpi(AP(i).ConnectionState, "Connected") && ~isempty(AP(i).CPUNodeID)
                        error(['The AP is already connected to a CPU with NodeID ' AP(i).CPUNodeID]);
                    end
                else
                    if strcmpi(AP(i).ConnectionState, "Connected") && ismember(AP(i).ID, obj.ConnectedAPs)
                        error(['The AP at index ' i ' is already connected to the CPU']);
                    end
                    if strcmpi(AP(i).ConnectionState, "Connected") && ~isempty(AP(i).CPUNodeID)
                        error(['The AP at index ' i ' is already connected to a CPU with NodeID ' AP(i).CPUNodeID]);
                    end
                end

                apIndex = length(obj.ConnectedAPNodes) + 1;
                % Update connection information
                connectionConfig = connectionConfigList(i); % AP specific configuration
                connectionConfig.APIndex = apIndex;

                % Add PHY connection context
                phyConnectionParam = ["ID", "NumTransmitAntennas"];
                for j=1:numel(phyConnectionParam)
                    phyConnectionInfo.(phyConnectionParam(j)) = AP(i).(phyConnectionParam(j));
                end
                obj.PhyEntity.addConnectionToAP(phyConnectionInfo);

                % Update list of connected APs
                obj.ConnectedAPs(end+1) = AP(i).ID;
                obj.ConnectedAPNodes{end+1} = AP(i);

                % Add connection in AP
                AP(i).addConnection(connectionConfig, @obj.connectUEViaAP);
            end
        end

        function connectUE(~, ~)
            % CPU does not suport this function
            coder.internal.error('nr5g:nrNode:NotSupportedOperation', 'ConnectUE');
        end    
    end

    methods(Hidden)
        function connectionConfig = connectUEViaAP(obj, UE, connectionConfig)
            %connectUEViaAP Add or Update connection context of UE and return the connection configuration
            % to the AP.

            coder.internal.errorIf(~isempty(obj.LastRunTime), 'nr5g:nrNode:NotSupportedOperation', 'Connect UE Via AP');

            % Information to configure connection information at CPU MAC
            macConnectionParam = ["RNTI", "UEID", "UEName", "APID", "SRSConfiguration", "CSIRSConfiguration", "InitialCQIDL"];
            % Information to configure connection information at CPU PHY
            phyConnectionParam = ["RNTI", "UEID", "UEName", "APID", "SRSSubbandSize", "NumHARQ", "DuplexMode", "CSIMeasurementSignalDLType"];
            % Information to configure connection information at CPU scheduler
            schedulerConnectionParam = ["RNTI", "UEID", "UEName", "NumTransmitAntennas", "NumReceiveAntennas", ...
                "CSIRSConfiguration", "SRSConfiguration", "SRSSubbandSize", "InitialCQIDL", "InitialCQIUL","InitialMCSIndexUL", "CustomContext"];
            % Information to configure connection information at CPU RLC
            rlcConnectionParam = ["RNTI", "FullBufferTraffic", "RLCBearerConfig"];

            % Set initial CQI for UL and DL
            connectionConfig.InitialCQIDL = nrGNB.getCQIIndex(connectionConfig.InitialMCSIndexDL);
            connectionConfig.InitialCQIUL = nrGNB.getCQIIndex(connectionConfig.InitialMCSIndexUL);

            apIndex = floor(connectionConfig.NCellID / 3);

            % Calculate total number of transmit antennas for a UE
            numTxAntennasForUE = obj.ConnectedAPNodes{apIndex}.NumTransmitAntennas;
            for i=1:numel(UE.APCellIDs)
                idx = floor(UE.APCellIDs(i) / 3);
                numTxAntennasForUE = numTxAntennasForUE + obj.ConnectedAPNodes{idx}.NumTransmitAntennas;
            end

            if ~strcmpi(UE.ConnectionState, "Connected")
                % Add UE connection to the CPU

                configParam = ["SubcarrierSpacing", "NumHARQ", "DuplexMode", "NumResourceBlocks", "ChannelBandwidth", ...
                    "DLCarrierFrequency", "ULCarrierFrequency", "DLULConfigTDD", "CSIReportType", "CSIRSConfiguration", ...
                    "RVSequence", "CSIMeasurementSignalDLType"];
                for j=1:numel(configParam)
                    connectionConfig.(configParam(j)) = obj.(configParam(j));
                end

                %connectionConfig.CSIRSConfiguration.NID = obj.NCellID;    % This is for internal Layers of CPU
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
                % fill connection config
                connectionConfig.RNTI = rnti;
                connectionConfig.SRSConfiguration = obj.SRSConfiguration(rnti);
                % Update the UE to AP connection map
                obj.UEsToAPsMap{rnti}(end+1) = connectionConfig.APID;
            end
            % Only Supports SRS Based DL CSI
            connectionConfig.CSIMeasurementSignalDLType = 1;

            % connection context to CPU MAC
            macConnectionInfo = struct();
            for j=1:numel(macConnectionParam)
                macConnectionInfo.(macConnectionParam(j)) = connectionConfig.(macConnectionParam(j));
            end
            if ~strcmpi(UE.ConnectionState, "Connected")
                obj.MACEntity.addConnection(macConnectionInfo);
            else
                obj.MACEntity.updateConnection(macConnectionInfo);
            end

            % connection context to CPU PHY
            phyConnectionInfo = struct();
            for j=1:numel(phyConnectionParam)
                phyConnectionInfo.(phyConnectionParam(j)) = connectionConfig.(phyConnectionParam(j));
            end
            if ~strcmpi(UE.ConnectionState, "Connected")
                obj.PhyEntity.addConnection(phyConnectionInfo);
                connectionConfig.GNBTransmitPower = obj.PhyEntity.scaleTransmitPower;
            else
                obj.PhyEntity.updateConnection(phyConnectionInfo);
            end

            % connection context to CPU scheduler
            schedulerConnectionInfo = struct();
            for j=1:numel(schedulerConnectionParam)
                schedulerConnectionInfo.(schedulerConnectionParam(j)) = connectionConfig.(schedulerConnectionParam(j));
            end
            schedulerConnectionInfo.NumTransmitAntennasForUE = numTxAntennasForUE;
            if ~strcmpi(UE.ConnectionState, "Connected")
                obj.MACEntity.Scheduler.addConnectionContext(schedulerConnectionInfo);
            else
                obj.MACEntity.Scheduler.updateConnectionContext(schedulerConnectionInfo);
            end

            % connection context to CPU RLC entity
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

            % If the packets are PUSCH or SRS process them via PHY Layer
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
            %isPacketRelevant Checks the relavency of in-band packets
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
            %getGNBParam returns GNB specific parameters which can be passed through GNB after
            %removing Split type from CPU parameters and return it saperately

            paramLength = numel(param);
            gnbParams = {};
            splitVal = "Centralized";
            notAllowedParams = ["NumTransmitAntennas", "NumReceiveAntennas", "TransmitPower", ...
                "NoiseFigure", "ReceiveGain", "CSIMeasurementSignalDL"];

            for idx=1:2:paramLength
                paramName = string(param{idx});
                if any(paramName == notAllowedParams)
                    error(['Do not provide "' char(paramName) '" as a NV pair for pre6GCPU'])
                elseif ~strcmp(paramName, "Split")
                    gnbParams = [gnbParams {paramName, param{idx+1}}];
                else
                    if isstring(param{idx+1})||ischar(param{idx+1})||iscellstr(param{idx+1})
                        splitVal = string(param{idx+1});
                    end
                end
            end

            % Validate Split
            validateattributes(splitVal, {'string','char'}, {'nonempty', 'scalartext'}, mfilename, 'Split')
            splitVal = validatestring(splitVal, pre6GCPU.Split_Values, mfilename, "Split");

            % For Scheduler to by-pass 1X1 Precoding matrix in case of 1 Tx
            % Antennas
            gnbParams = [gnbParams {"NumTransmitAntennas", 2, "NumReceiveAntennas", 2}];
        end

        function varargout = generateCPUCellID(varargin)
            % Generate/Reset the CPU Cell ID counter
            %
            % ID = generateCPUCellID() Returns the next CPU Cell ID. The CPU Cell ID
            % counter starts from 0

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
            % reset() Reset the CPU Cell ID counter. Invoke this method to
            % reset the CPU Cell ID counter before creating nodes in the simulation
            pre6GCPU.generateCPUCellID(0);
        end
    end
end