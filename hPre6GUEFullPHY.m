classdef hPre6GUEFullPHY < nr5g.internal.nrUEFullPHY
    %hPre6GUEFullPHY Implements UE PHY functionality

    properties (SetAccess = protected)
        %APCellIDs An array of AP Cell IDs this UE is connected to
        APCellIDs
    end

    methods
        function obj = hPre6GUEFullPHY(param, notificationFcn)
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

        function [MACPDU, crcFlag, sinr] = decodePDSCH(obj, pdschInfo, pktStartTime, pktEndTime, carrierConfigInfo)
            % Return the decoded MAC PDU along with the crc result
            crcFlag = 1;
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
                end
            end

            if ~isempty(packetOfInterest)
                pktDuration = max([packetOfInterest.Duration]);
                % Read the combined waveform received during packet's duration
                rxWaveform = resultantWaveform(obj.RxBuffer, pktStartTime, pktStartTime+pktDuration);
                channelDelay = pktDuration -(pktEndTime-pktStartTime);
                numSampleChannelDelay = ceil(channelDelay*packet.SampleRate);
                % PUSCH Rx processing
                [MACPDU, crcFlag] = pdschRxProcessing(obj, rxWaveform, pdschInfo, packetOfInterest, carrierConfigInfo, numSampleChannelDelay);

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
            Qm = length(dlschLLRs{1})/length(rxSymbols{cwIdx}); % Bits per symbol
            csi{cwIdx} = repmat(csi{cwIdx}.',Qm,1);   % Expand by each bit per symbol
            dlschLLRs{cwIdx} = dlschLLRs{cwIdx} .* csi{cwIdx}(:);

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
    end
end