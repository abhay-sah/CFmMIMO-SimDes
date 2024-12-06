classdef pre6GUEFullPHY < nr5g.internal.nrUEFullPHY

    properties (SetAccess = protected)
        %APCellIDs are Cell IDs of AP Nodes to which this UE is connected to
        APCellIDs
    end

    methods
        function obj = pre6GUEFullPHY(param, notificationFcn)
            % Call base class constructor
            obj = obj@nr5g.internal.nrUEFullPHY(param, notificationFcn);
        end

        function addConnection(obj, connectionConfig)
            %addConnection Adds CPU connection context to the UE PHY

            % Call addConnection from base class
            addConnection@nr5g.internal.nrUEFullPHY(obj, connectionConfig);

            obj.APCellIDs = [obj.APCellIDs; connectionConfig.NCellID];
            obj.PacketStruct.Metadata.NCellID = obj.APCellIDs;
        end

        function [MACPDU, CRCFlag, sinr] = decodePDSCH(obj, pdschInfo, pktStartTime, pktEndTime, carrierConfigInfo)
            % Return the decoded MAC PDU along with the crc result

            % Initialization
            packetInfo = obj.MACPDUInfo;
            packetInfo.TBS = pdschInfo.TBS;
            packetInfo.HARQID = pdschInfo.HARQID;
            sinr = -Inf;

            packetInfoList = packetList(obj.RxBuffer, pktStartTime, pktEndTime);
            packetOfInterest = [];
            for j=1:length(packetInfoList) % Search PDSCH of interest in the list of received packets
                packet = packetInfoList(j);
                if (packet.Metadata.PacketType == obj.PXSCHPacketType) && ... % Check for PDSCH
                        any(obj.APCellIDs == packet.Metadata.NCellID) && ... % Check for PDSCH of interest
                        any(pdschInfo.PDSCHConfig.RNTI == packet.Metadata.RNTI) && ...
                        (pktStartTime == packet.StartTime)
                    packetOfInterest = [packetOfInterest; packet]; % Consider Multiple Packets from Multiple Channels
                    % Read the combined waveform received during packet's duration
                    rxWaveform = resultantWaveform(obj.RxBuffer, pktStartTime, pktStartTime+packet.Duration);
                    channelDelay = packet.Duration -(pktEndTime-pktStartTime);
                    numSampleChannelDelay = ceil(channelDelay*packet.SampleRate);
                end
            end

            if ~isempty(packetOfInterest)
                % PUSCH Rx processing
                [MACPDU, CRCFlag] = pdschRxProcessing(obj, rxWaveform, pdschInfo, packetOfInterest, carrierConfigInfo, numSampleChannelDelay);
                % Remove the "UETagInfo" tag from the tag list, which
                % includes the relevant information to identify the tags of a UE
                [~, phyTag] = ...
                    wirelessnetwork.internal.packetTags.remove(packetOfInterest(1).Tags, ...
                    "UETagInfo");
                % Identify the index of the UE based on the RNTI match between
                % the packet metadata and the PDSCH configuration
                numUEsScheduled = 1:numel(packetOfInterest(1).Metadata.RNTI);
                ueRNTIIdx = numUEsScheduled(pdschInfo.PDSCHConfig.RNTI == ...
                    packetOfInterest(1).Metadata.RNTI);
                % Use the retrieved tag indexing information to find the
                % specific tags related to the UE of interest within the packet
                ueTagIndices = phyTag.Value(2*ueRNTIIdx-1:2*ueRNTIIdx);
                % Extract the relevant tags for the UE from the packet based on
                % the identified indices
                packetInfo.Tags = packetOfInterest(1).Tags(ueTagIndices(1):ueTagIndices(2));
                % Get the transmitter ID of the packet, identifying the packet's source
                packetInfo.NodeID = packetOfInterest(1).TransmitterID;
            end
        end
    
        function [dlRank, pmiSet, cqiRBs, precodingMatrix, sinr] = decodeCSIRS(obj, csirsConfig, pktStartTime, pktEndTime, carrierConfigInfo)
            % Return CSI-RS measurement

            rxWaveform = resultantWaveform(obj.RxBuffer, pktStartTime, pktEndTime);
            packetInfoList = packetList(obj.RxBuffer, pktStartTime, pktEndTime);

            packetOfInterest = [];
            for j=1:length(packetInfoList) % Search CSI-RS of interest in the list of received packets
                packet = packetInfoList(j);
                if (packet.Metadata.PacketType == obj.CSIRSPacketType) && ...
                        any(obj.APCellIDs == packet.Metadata.NCellID)
                    packetOfInterest = [packetOfInterest; packet]; % Consider Multiple Packets from Multiple Channels
                end
            end

            [dlRank, pmiSet, cqiRBs, precodingMatrix, sinr] = csirsRxProcessing(obj, rxWaveform, csirsConfig, ...
                packetOfInterest, carrierConfigInfo);

            % Received power of gNB at UE for pathloss calculation
            obj.GNBReceivedPower = mean([packetOfInterest.Power]);
         end
    end

    methods(Hidden)
        function updateConnection(obj, connectionConfig)
            %updateConnection Updates CPU connection context to the UE PHY

            obj.APCellIDs = [obj.APCellIDs; connectionConfig.NCellID];
            obj.PacketStruct.Metadata.NCellID = obj.APCellIDs;
        end
    end

    methods(Access=protected)
        function [macPDU, crcFlag] = pdschRxProcessing(obj, rxWaveform, pdschInfo, packetInfoList, carrierConfigInfo, numSampleChannelDelay)
            % Decode PDSCH out of Rx waveform

            rxWaveform = applyRxGain(obj, rxWaveform);
            rxWaveform = applyThermalNoise(obj, rxWaveform);

            pathGains = packetInfoList(1).Metadata.Channel.PathGains  * db2mag(packetInfoList(1).Power-30) * db2mag(obj.ReceiveGain);
            for i=2:length(packetInfoList)
                pg = packetInfoList(i).Metadata.Channel.PathGains * db2mag(packetInfoList(i).Power-30) * db2mag(obj.ReceiveGain);
                pathGains = cat(3, pathGains, pg);
            end

            % Initialize slot-length waveform
            [startSampleIdx, endSampleIdx] = sampleIndices(obj, pdschInfo.NSlot, 0, carrierConfigInfo.SymbolsPerSlot-1);
            slotWaveform = zeros((endSampleIdx-startSampleIdx+1)+numSampleChannelDelay, obj.NumReceiveAntennas);

            % Populate the received waveform at appropriate indices in the slot-length waveform
            startSym = pdschInfo.PDSCHConfig.SymbolAllocation(1);
            endSym = startSym+pdschInfo.PDSCHConfig.SymbolAllocation(2)-1;
            [startSampleIdx, ~] = sampleIndices(obj, pdschInfo.NSlot, startSym, endSym);
            slotWaveform(startSampleIdx : startSampleIdx+length(rxWaveform)-1, :) = rxWaveform;

            % Perfect timing estimation
            offset = nrPerfectTimingEstimate(pathGains, packetInfoList(1).Metadata.Channel.PathFilters.');
            slotWaveform = slotWaveform(1+offset:end, :);

            % Perform OFDM demodulation on the received data to recreate the
            % resource grid, including padding in the event that practical
            % synchronization results in an incomplete slot being demodulated
            rxGrid = nrOFDMDemodulate(carrierConfigInfo, slotWaveform);

            % Perfect channel estimation
            estChannelGrid = nrPerfectChannelEstimate(pathGains,packetInfoList(1).Metadata.Channel.PathFilters.', ...
                carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                packetInfoList(1).Metadata.Channel.SampleTimes);

            % Extract PDSCH resources
            [pdschIndices, ~] = nrPDSCHIndices(carrierConfigInfo, pdschInfo.PDSCHConfig);
            [pdschRx, pdschHest, ~, pdschHestIndices] = nrExtractResources(pdschIndices, rxGrid, estChannelGrid);

            % Noise variance
            noiseEst = calculateThermalNoise(obj);

            % Apply precoding to channel estimate
            ueIdx = find(packetInfoList(1).Metadata.RNTI == obj.RNTI, 1);
            precodingMatrix = packetInfoList(1).Metadata.PrecodingMatrix{ueIdx};
            for i=2:length(packetInfoList)
                ueIdx = find(packetInfoList(i).Metadata.RNTI == obj.RNTI, 1);
                precodingMatrix = cat(2, precodingMatrix, packetInfoList(i).Metadata.PrecodingMatrix{ueIdx});
            end

            pdschHest = nrPDSCHPrecode(carrierConfigInfo,pdschHest,pdschHestIndices,permute(precodingMatrix,[2 1 3]));

            % Equalization
            [pdschEq, csi] = nrEqualizeMMSE(pdschRx,pdschHest, noiseEst);

            % PDSCH decoding
            [dlschLLRs, rxSymbols] = nrPDSCHDecode(pdschEq, pdschInfo.PDSCHConfig.Modulation, pdschInfo.PDSCHConfig.NID, ...
                pdschInfo.PDSCHConfig.RNTI, noiseEst);

            % Scale LLRs by CSI
            csi = nrLayerDemap(csi); % CSI layer demapping

            cwIdx = 1;
            Qm = length(dlschLLRs{1})/length(rxSymbols{cwIdx}); % bits per symbol
            csi{cwIdx} = repmat(csi{cwIdx}.',Qm,1);   % expand by each bit per symbol
            dlschLLRs{cwIdx} = dlschLLRs{cwIdx} .* csi{cwIdx}(:);   % scale

            obj.DLSCHDecoder.TransportBlockLength = pdschInfo.TBS*8;
            obj.DLSCHDecoder.TargetCodeRate = pdschInfo.TargetCodeRate;

            [decbits, crcFlag] = obj.DLSCHDecoder(dlschLLRs, pdschInfo.PDSCHConfig.Modulation, ...
                pdschInfo.PDSCHConfig.NumLayers, pdschInfo.RV, pdschInfo.HARQID);

            if pdschInfo.RV == obj.RVSequence(end)
                % The last redundancy version failed. Reset the soft
                % buffer
                resetSoftBuffer(obj.DLSCHDecoder, 0, pdschInfo.HARQID);
            end

            % Convert bit stream to byte stream
            macPDU = bit2int(decbits, 8);
        end

        function  [rank, pmiSet, cqiRBs, precodingMatrix, sinr] = csirsRxProcessing(obj, ~, csirsConfig, packets, carrierConfigInfo)
            % CSI-RS measurement on Rx waveform

            % Concatenate Path Gains
            pathGains = packets(1).Metadata.Channel.PathGains  * db2mag(packets(1).Power-30) * db2mag(obj.ReceiveGain);
            for i=2:length(packets)
                pg = packets(i).Metadata.Channel.PathGains  * db2mag(packets(i).Power-30) * db2mag(obj.ReceiveGain);
                pathGains = cat(3, pathGains, pg);
            end

            % Perfect Timing and Channel Estimation
            offset = nrPerfectTimingEstimate(pathGains, packets(1).Metadata.Channel.PathFilters.');
            Hest = nrPerfectChannelEstimate(pathGains, packets(1).Metadata.Channel.PathFilters.', ...
                carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                packets(1).Metadata.Channel.SampleTimes);

            % Noise Variance
            nVar = calculateThermalNoise(obj);

            if obj.NumReceiveAntennas > 1
                % Select rank based on maximum spectral efficiency. Replace 'MaxSE' with 'MaxSINR' to use maximum SINR based rank selection
                rank = nr5g.internal.nrRISelect(carrierConfigInfo, csirsConfig, obj.CSIReportConfig, Hest, nVar, 'MaxSE');
                % Restricting the number of transmission layers to 4 as
                % only single codeword is supported
                rank = min(rank, 4);
            else
                rank = 1;
            end

            [cqi, pmiSet, ~, pmiInfo] = nr5g.internal.nrCQISelect(carrierConfigInfo, csirsConfig, obj.CSIReportConfig, rank, Hest, nVar);
            cqi = max([cqi, 1]); % Ensure minimum CQI as 1
            cqiRBs(1:obj.CarrierInformation.NumResourceBlocks) = cqi; % Wideband CQI
            precodingMatrix = {[packets(:).TransmitterID] pmiInfo.W};
            sinr = empty();
        end
    end
end