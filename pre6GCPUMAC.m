classdef pre6GCPUMAC < nr5g.internal.nrGNBMAC

    properties(SetAccess=protected)
        %UEsToAPsMap{i} stores all the AP Node ID of those APs to whom
        % a UE with RNTI=i is connected
        UEsToAPsMap

        %APsOrderInW stores the order of AP Node IDs in which W is calculated
        APsOrderInW
    end

    methods
        function obj = pre6GCPUMAC(param, notificationFcn)
            % Call base class constructor
            obj = obj@nr5g.internal.nrGNBMAC(param, notificationFcn);
        end

        function addConnection(obj, ueInfo)
            %addConnection Adds UE connection context to the CPU MAC

            % Call base class constructor
            addConnection@nr5g.internal.nrGNBMAC(obj, ueInfo);
            % Add AP ID to the Map
            obj.UEsToAPsMap{ueInfo.RNTI} = ueInfo.APID;
            obj.APsOrderInW{ueInfo.RNTI} = ueInfo.APID;
        end

        function srsIndication(obj, csiMeasurement)
            %srsIndication Reception of SRS measurements from PHY

            % Store the AP Order for a perticular srsIndication
            obj.APsOrderInW{csiMeasurement.RNTI} = csiMeasurement.SRSBasedDLMeasurements.APOrder;

            updateChannelQualityUL(obj.Scheduler, csiMeasurement);
        end
    end

    methods(Hidden)
        function updateConnection(obj, ueInfo)
            %updateConnection Updates connection context for already connected UEs

            obj.UEsToAPsMap{ueInfo.RNTI}(end+1) = ueInfo.APID;
            obj.APsOrderInW{ueInfo.RNTI}(end+1) = ueInfo.APID;
        end

        function dataTx(obj, currentTime)
            % dataTx Adds the order of APs for W (Precoding matrix) to the grant
            % and call dataTx from base class that construct and send the DL MAC PDUs
            % scheduled for current symbol to PHY

            symbolNumFrame = obj.CurrSlot*obj.NumSymbols + obj.CurrSymbol; % Current symbol number in the 10 ms frame
            for rnti = 1:length(obj.UEs) % For all UEs
                downlinkGrant = obj.DownlinkTxContext{rnti, symbolNumFrame + 1};
                % If there is any downlink grant corresponding to which a transmission is scheduled at the current symbol
                if ~isempty(downlinkGrant)
                    % Add the APsOrderInW for that RNTI in Precoding Matrix
                    obj.DownlinkTxContext{rnti, symbolNumFrame + 1}.W = ...
                        {obj.APsOrderInW{rnti} downlinkGrant.W};
                end
            end
            % Call dataTx from base class
            dataTx@nr5g.internal.nrGNBMAC(obj,currentTime);
        end

        function controlTx(obj, resourceAssignmentsUL, resourceAssignmentsDL)
            %controlTx Construct and send the uplink and downlink
            % assignments to the APs

            scheduledResources = obj.ScheduledResources;
            scheduledResources.NCellID = obj.NCellID;
            scheduledResources.TimingInfo = [mod(obj.CurrFrame, 1024) obj.CurrSlot obj.CurrSymbol];
            % Construct and send uplink grants
            if ~isempty(resourceAssignmentsUL)
                scheduledResources.ULGrants = resourceAssignmentsUL;
                pktInfo = obj.PacketStruct;
                uplinkGrant = obj.UplinkGrantStruct;
                grantFieldNames = obj.ULGrantFieldNames;
                grantFieldNames = [grantFieldNames(:)' {'Type'}];
                for i = 1:length(resourceAssignmentsUL) % For each UL assignment
                    grant = resourceAssignmentsUL(i);
                    for ind = 1:length(grantFieldNames)
                        uplinkGrant.(grantFieldNames{ind}) = grant.(grantFieldNames{ind});
                    end
                    % Construct packet information
                    pktInfo.Data = uplinkGrant;
                    pktInfo.Metadata.PacketType = obj.ULGrant;
                    pktInfo.Metadata.RNTI = grant.RNTI;
                    pktInfo.Metadata.DirectID = obj.UEInfo(grant.RNTI).ID;
                    % Send the packet to all the APs of Interest
                    apNodeIds = obj.UEsToAPsMap{grant.RNTI};
                    for idx=1:length(apNodeIds)
                        pktInfo.DirectToDestination = apNodeIds(idx);
                        obj.TxOutofBandFcn(pktInfo); % Send the UL grant out-of-band to UE's MAC through AP
                    end
                end
            end

            % Construct and send downlink grants
            if ~isempty(resourceAssignmentsDL)
                scheduledResources.DLGrants = resourceAssignmentsDL;
                pktInfo = obj.PacketStruct;
                downlinkGrant = obj.DownlinkGrantStruct;
                grantFieldNames = obj.DLGrantFieldNames;
                for i = 1:length(resourceAssignmentsDL) % For each DL assignment
                    grant = resourceAssignmentsDL(i);
                    for ind = 1:obj.DLGrantFieldNamesCount
                        downlinkGrant.(grantFieldNames{ind}) = grant.(grantFieldNames{ind});
                    end
                    % Construct packet information and send the DL grant out-of-band to UE's MAC
                    pktInfo.Data = downlinkGrant;
                    pktInfo.Metadata.PacketType = obj.DLGrant;
                    pktInfo.Metadata.RNTI = grant.RNTI;
                    pktInfo.Metadata.DirectID = obj.UEInfo(grant.RNTI).ID;
                    % Send the packet to all the APs of Interest
                    apNodeIds = obj.UEsToAPsMap{grant.RNTI};
                    for idx=1:length(apNodeIds)
                        pktInfo.DirectToDestination = apNodeIds(idx);
                        obj.TxOutofBandFcn(pktInfo); % Send the UL grant out-of-band to UE's MAC through AP
                    end
                end
            end

            % Notify the node about resource allocation event
            obj.NotificationFcn('ScheduledResources', scheduledResources);
        end
    end
end