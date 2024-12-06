classdef pre6GUE < nrUE
    %pre6GUE user equipment (UE) node
    %   UE = pre6GUE creates a default UE.
    %
    %   UE = pre6GUE(Name=Value) creates one or more similar UEs with the
    %   specified property Name set to the specified Value. You can Specify all the properties that
    %   are there in nrUE.
    %
    %   pre6GUE properties (read-only):
    %
    %   ID                   - Node identifier
    %   APCellIDs            - Cell ID of APs to which the UE is connected.
    %   ConnectedAPs         - Node ID of Connected APs

    properties (SetAccess = protected)
        %APCellIDs Cell IDs of APs to which this UE is connected
        APCellIDs

        %ConnectedAPs Node ID of Connected APs
        ConnectedAPs
    end

    methods
        function obj = pre6GUE(varargin)

            % Check for position matrix
            names = varargin(1:2:end);
            positionIdx = find(strcmp([names{:}], 'Position'), 1, 'last');
            if ~isempty(positionIdx)
                position = varargin{2*positionIdx}; % Read value of Position N-V argument
                if size(position,1) > 1
                    error("Does not support vectorized initialization, Create one UE at a time")
                end
            end

            % Call base class constructor
            obj = obj@nrUE(varargin{:});

            % Create internal layers for each UE
            phyParam = {'TransmitPower', 'NumTransmitAntennas', 'NumReceiveAntennas', ...
                'NoiseFigure', 'ReceiveGain', 'Position'};

            for idx=1:numel(obj)
                ue = obj(idx);
                if ~strcmp(ue.PHYAbstractionMethod, "none")
                    error('Provide PHYAbstractionMethod="none" as a N-V pair');
                end

                % Set up MAC
                ue.MACEntity = pre6GUEMAC(@ue.processEvents);

                % Set up PHY
                phyInfo = struct();
                for j=1:numel(phyParam)
                    phyInfo.(char(phyParam{j})) = ue.(char(phyParam{j}));
                end
                if strcmp(ue.PHYAbstractionMethod, "none")
                    ue.PhyEntity = pre6GUEFullPHY(phyInfo, @ue.processEvents); % Full PHY
                    ue.PHYAbstraction = 0;
                end

                % Set inter-layer interfaces
                ue.setLayerInterfaces();
            end
        end
    end

    methods(Hidden)
        function addConnection(obj, connectionConfig)
            %addConnection Add connection context to UE

            obj.APCellIDs = [obj.APCellIDs; connectionConfig.NCellID];
            obj.ConnectedAPs = [obj.ConnectedAPs; connectionConfig.APID];

            % If already connected just update certain param
            if strcmpi(obj.ConnectionState, "Connected")
                % Update PHY
                phyConnectionInfo.NCellID = connectionConfig.NCellID;
                obj.PhyEntity.updateConnection(phyConnectionInfo);
                return;
            end

            connectionConfig.GNBID = connectionConfig.APID;
            % Call addConnection form base class
            obj.addConnection@nrUE(connectionConfig);
        end

        function addToTxBuffer(obj, packet)
            %addToTxBuffer Adds packets to the Tx Buffer

            packet.Metadata.LastTransmitterType = 'UE';
            addToTxBuffer@wirelessnetwork.internal.nrNode(obj, packet);
        end
    
        function flag = intracellPacketRelevance(obj, packet)
            %intracellPacketRelevance Intracell Packet Relevance Check

            flag = 1;
            if packet.Type==2 &&  ~obj.MUMIMOEnabled && any(packet.Metadata.NCellID==obj.NCellID) && ...
                    packet.Metadata.PacketType==nr5g.internal.nrPHY.PXSCHPacketType && ...
                    ~any(packet.Metadata.RNTI == obj.RNTI)
                % If MU-MIMO is disabled then reject any intra-cell PDSCH packet not intended for this UE
                flag = 0;
            end
        end
    end
end