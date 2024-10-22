classdef hPre6GCPUFullPHY < nr5g.internal.nrGNBFullPHY
     %hPre6GCPUFullPHY Implements pre6G CPU PHY functionality

    properties (SetAccess = protected, Hidden)
        %APInfo Struct array which stores APID and NumTransmitAntennas of
        % the APs connected to the CPU
        APInfo

        %UEsToAPsMap{i} Stores all the AP Node ID of those APs to whom a UE with RNTI=i is connected
        UEsToAPsMap

        %Split Specify the Split as "Centralized" or "Distributed" or "7.2x".
        %   The value "Centralized" represents Centralized Realization of Cell-Free.
        %   The value "Distributed" represents Distributed Realization of Cell-Free.
        %   The value "7.2x" represents Cell-Free will follow 7.2x Split of O-RAN Standards.
        Split

        %CSIMeasurementSignalDLType Select the DL CSI based on SRS at CPU. 
        % By default the value is true.
        CSIMeasurementSignalDLType (1, 1) = 1;
    end

    methods
        function obj = hPre6GCPUFullPHY(param, notificationFcn)
            % Call base class constructor
            obj = obj@nr5g.internal.nrGNBFullPHY(param, notificationFcn);

            % Set the Split Value
            obj.Split = param.Split;

            % Pre6G Packet param
            obj.PacketStruct.Abstraction = false; % Full PHY
            obj.PacketStruct.Metadata = struct('NCellID', obj.CarrierInformation.NCellID, 'RNTI', [], ...
                'PrecodingMatrix', [], 'NumSamples', [], 'Channel', obj.PacketStruct.Metadata.Channel, 'DirectID', 0);
        end

        function addConnectionToAP(obj, connectionConfig)
            % addConnectionToAP Adds AP connection context to the CPU PHY

            apParamName = ["ID", "NumTransmitAntennas"];
            apInfo = struct();
            for i=1:length(apParamName)
                apInfo.(apParamName(i)) = connectionConfig.(apParamName(i));
            end
            obj.APInfo = [obj.APInfo apInfo];
        end

        function addConnection(obj, connectionConfig)
            %addConnection Adds UE connection context to the CPU PHY

            obj.UEsToAPsMap{connectionConfig.RNTI} = connectionConfig.APID;

            % Call addConnection from base class
            addConnection@nr5g.internal.nrGNBFullPHY(obj, connectionConfig);
        end

        function nextInvokeTime = run(obj, currentTime, packets)
            %run Run the PHY layer operations and return the next invoke time (in nanoseconds)

            nextInvokeTime = Inf;
            if ~isempty(obj.CarrierInformation) % If carrier is configured
                symEndTimes = obj.CarrierInformation.SymbolTimings;
                slotDuration = obj.CarrierInformation.SlotDuration; % In nanoseconds

                % Find the duration completed in the current slot
                durationCompletedInCurrSlot = mod(currentTime, slotDuration);

                currTimeInfo = obj.CurrTimeInfo;
                currTimeInfo.Time = currentTime;
                currTimeInfo.NFrame = floor(currentTime/obj.FrameDurationInNS);
                currTimeInfo.NSlot = mod(floor(currentTime/slotDuration), obj.CarrierInformation.SlotsPerFrame);
                currTimeInfo.NSymbol = find(durationCompletedInCurrSlot < symEndTimes, 1) - 1;

                % PHY transmission
                phyTx(obj, currTimeInfo);

                % PHY reception
                phyRx(obj, currTimeInfo, packets);

                % Get the next invoke time for PHY
                nextInvokeTime = getNextInvokeTime(obj);
            end
            % Update the last run time
            obj.LastRunTime = currentTime;
        end

        function data = pdschData(obj, pdschInfo, macPDU)
            %pdschData Return the data depending upon the Split.
            % Centralized   - Returns the PDSCH Waveform
            % 7.2x          - Returns the PDSCH and DMRS Symbols with
            % Indices
            % Distributed   - Returns the coded transport block for PDSCH

            pdschInfo.PrecodingMatrix = pdschInfo.PrecodingMatrix{2};
            if strcmp(obj.Split, "Centralized")
                % PDSCH Grid
                pdschGrid = populatePDSCH(obj, pdschInfo, macPDU);
                % OFDM modulation
                txWaveform = nrOFDMModulate(obj.CarrierConfig, pdschGrid);
                % Transmit Tx Waveform as data
                data = txWaveform;
            else % 7.2x or Distributed
                data = populatePDSCH(obj, pdschInfo, macPDU);
            end
        end

        function data = csirsData(obj, csirsConfig)
            %csirsData Return the CSI-RS waveform for all the Splits

            % Check for active AP
            activeAPs =  unique([obj.UEsToAPsMap{:}]);
            if all(activeAPs ~= csirsConfig.NID)
                data = [];
                return
            end

            % Fill the slot grid with CSI-RS symbols
            csirsGrid = populateCSIRS(obj, csirsConfig);
            % OFDM modulation
            txWaveform = nrOFDMModulate(obj.CarrierConfig, csirsGrid);
            % Transmit Tx Waveform as data
            data = txWaveform;
        end

        function [packetInfo, sinr] = decodePUSCH(obj, puschInfoList, packetInfoList, carrierConfigInfo)
            % Return the decoded MAC PDUs along with the respective crc result

            numPUSCHs = length(puschInfoList);
            packetInfo = repmat(obj.MACPDUInfo, numPUSCHs, 1);
            sinr = -Inf(numPUSCHs, 1);

            for i=1:numPUSCHs % For each PUSCH to be received
                packetOfInterest = [];
                puschInfo = puschInfoList(i);
                packetInfo(i).RNTI = puschInfo.PUSCHConfig.RNTI;
                packetInfo(i).TBS = puschInfo.TBS;
                packetInfo(i).HARQID = puschInfo.HARQID;
                [puschStartTime, puschEndTime] = pktTiming(obj, carrierConfigInfo.NFrame, ...
                    carrierConfigInfo.NSlot, puschInfo.PUSCHConfig.SymbolAllocation(1), ...
                    puschInfo.PUSCHConfig.SymbolAllocation(2));
                channelDelay = 0;
                for j=1:length(packetInfoList) % Search PUSCH of interest in the list of received packets
                    packet = packetInfoList(j);
                    if (packet.Metadata.PacketType == obj.PXSCHPacketType) && ... % Check for PUSCH
                            (carrierConfigInfo.NCellID == packet.Metadata.NCellID) && ... % Check for PUSCH of interest
                            (puschInfo.PUSCHConfig.RNTI == packet.Metadata.RNTI) && ...
                            (puschStartTime == packet.StartTime)
                        packetOfInterest = [packetOfInterest; packet]; % Consider multiple Packets from multiple Channels
                        channelDelay = max(packet.Duration -(puschEndTime-puschStartTime), channelDelay);                        
                    end
                end
                if ~isempty(packetOfInterest)
                    numSampleChannelDelay = ceil(channelDelay*packet.SampleRate);
                    % PUSCH Rx processing
                    [packetInfo(i).MACPDU, packetInfo(i).CRCFlag] = puschRxProcessing(obj, puschInfo, ...
                        packetOfInterest, carrierConfigInfo, numSampleChannelDelay);
                    packetInfo(i).NodeID = packetOfInterest(1).TransmitterID;
                    packetInfo(i).Tags = packetOfInterest(1).Tags;
                end
            end
        end

        function [srsMeasurement, sinrList] = decodeSRS(obj, srsInfoList, packetInfoList, carrierConfigInfo)
            % Return SRS measurement for the UEs

            srsIdx = 0;
            % Channel measurement on SRS
            for i=1:length(srsInfoList)
                srsInfo = srsInfoList{i};
                packetOfInterest = [];
                for j=1:length(packetInfoList)
                    packet = packetInfoList(j);
                    if (packet.Metadata.PacketType == obj.SRSPacketType && ...
                            carrierConfigInfo.NCellID == packet.Metadata.NCellID && ...
                            srsInfo{1} == packet.Metadata.RNTI)
                        packetOfInterest = [packetOfInterest; packet]; % Consider Multiple Packets from Multiple Channels
                    end
                end
                [srsReport, sinr] = srsRxProcessing(obj, packetOfInterest, carrierConfigInfo);
                if ~isempty(srsReport)
                    srsIdx = srsIdx+1;
                    srsMeasurement(srsIdx) = srsReport;
                    sinrList(srsIdx) = sinr;
                end
            end

            if srsIdx==0
                % No valid SRS report found
                srsMeasurement = [];
                sinrList = -Inf;
            end
        end

        function pktList = pdschPacket(obj, pdschInfoList, pdschDataList, txStartTime)
            %pdschPacket Populate and return PDSCH packet

            packet = obj.PacketStruct;
            packet.Metadata.PacketType = obj.PXSCHPacketType;
            packet.StartTime = txStartTime;

            if strcmp(obj.Split, "Centralized")
                packet.Metadata.PacketConfig = [];
            else
                packet.Metadata.Info = []; % Will store PDSCH Info to be used at AP.
            end

            pdschConfigList = [pdschInfoList(:).PDSCHConfig];
            connectedAPs = [obj.APInfo(:).ID];
            % Initialize a packet for each active AP
            activeAPs = unique([obj.UEsToAPsMap{[pdschConfigList(:).RNTI]}]);
            numActiveAPs = numel(activeAPs);
            pktList = repmat(packet, numActiveAPs, 1);
            if strcmp(obj.Split, "Centralized")
                for i=1:numel(activeAPs)
                    apIdx = find(activeAPs(i) == connectedAPs);
                    pktList(i).Data = zeros(size(pdschDataList{1}, 1), obj.APInfo(apIdx).NumTransmitAntennas);
                end
            end
            minStartSym = Inf(numActiveAPs, 1);
            maxEndSym = zeros(numActiveAPs, 1);

            numPDSCH = numel(pdschInfoList);
            % Initialize an array, ueTagInfo, with dimensions 2N-by-1, where N represents
            % the number of PDSCH packets to be consolidated into a single packet. This
            % consolidated packet will incorporate tags from all individual PDSCH packets.
            % The array is designated to record the start and end indices of tags associated
            % with each PDSCH packet in the merged list. Specifically, for a given PDSCH
            % packet i, the start index of its tags is stored at position 2*i-1, and the end
            % index is stored at position 2*i within the ueTagInfo array
            ueTagInfo = cell(numel(activeAPs), 1);
            currentTagIdx = 1;

            % Assign corresponding precoding matrix to the PDSCH packet that is sent to
            % each of the serving APs.
            for i=1:numPDSCH
                pdschInfo = pdschInfoList(i);
                apNodeIDs = pdschInfo.PrecodingMatrix{1};
                to = 0;
                for j=1:numel(apNodeIDs)
                    apID = apNodeIDs(j);
                    apIdx = find(activeAPs == apID);
                    from = to + 1;
                    to = from + obj.APInfo(find(apID == connectedAPs)).NumTransmitAntennas - 1;
                    pktList(apIdx).Metadata.PrecodingMatrix{end+1} = pdschInfo.PrecodingMatrix{2}(:, (from:to), :);
                    if strcmp(obj.Split, "Centralized")
                        pktList(apIdx).Metadata.PacketConfig = [pktList(apIdx).Metadata.PacketConfig pdschInfo.PDSCHConfig]; % PDSCH Configuration
                        pktList(apIdx).Metadata.RNTI(end+1) = pdschInfo.PDSCHConfig.RNTI;
                        startSymIdx = pdschInfo.PDSCHConfig.SymbolAllocation(1)+1;
                        pdschNumSym = pdschInfo.PDSCHConfig.SymbolAllocation(2);
                        endSymIdx = startSymIdx+pdschNumSym-1;
                        if (startSymIdx < minStartSym(apIdx)) % Update min start symbol
                            minStartSym(apIdx) = startSymIdx;
                        end
                        if (endSymIdx > maxEndSym(apIdx))  % Update max end symbol
                            maxEndSym(apIdx) = endSymIdx;
                        end
                        pktList(apIdx).Data = pktList(apIdx).Data + pdschDataList{i}(:, (from:to));
                    else %  7.2x or Distributed
                        pktList(apIdx).Metadata.Info = [pktList(apIdx).Metadata.Info pdschInfo];
                        pktList(apIdx).Data{end+1} = pdschDataList{i};
                    end
                    % Append the tags of current PDSCH packet with the existing list of tags
                    pktList(apIdx).Tags = wirelessnetwork.internal.packetTags.append(pktList(apIdx).Tags, ...
                        obj.ReTxTagBuffer{pdschInfo.PDSCHConfig.RNTI, pdschInfo.HARQID+1});
                    % Record the start and end indices of tags associated with the current PDSCH
                    % packet in the merged list
                    ueTagInfo{apIdx} = [ueTagInfo{apIdx} currentTagIdx numel(packet.Tags)];
                    currentTagIdx = ueTagInfo{apIdx}(end) + 1;

                    if numel(pdschInfo.PrecodingMatrix{2}) == to
                        to=0;
                    end
                end
            end
            % For each Packet
            for i=1:numel(activeAPs)
                if strcmp(obj.Split, "Centralized")
                    pktList(i).Tags = wirelessnetwork.internal.packetTags.add(packet.Tags, ...
                        "UETagInfo", ueTagInfo{i}, [1 numel(pktList(i).Data)]);
                    [startSampleIdx, endSampleIdx] = sampleIndices(obj, pdschInfoList(1).NSlot, minStartSym(i)-1, maxEndSym(i)-1);
                    pktList(i).Duration = round(sum(obj.CarrierInformation.SymbolDurations(minStartSym(i):maxEndSym(i)))/1e9,9);
                    pktList(i).Metadata.NumSamples = endSampleIdx-startSampleIdx+1;
                    pktList(i).SampleRate = obj.WaveformInfo.SampleRate;
                else
                    pktList(i).Metadata.UETagInfo = ueTagInfo{i};
                end
                pktList(i).DirectToDestination = activeAPs(i);
            end
        end
    end

    methods(Hidden)
        function updateConnection(obj, connectionConfig)
            %updateConnection Update connection context for already connected UEs

            rnti = connectionConfig.RNTI;
            obj.UEsToAPsMap{rnti} = [obj.UEsToAPsMap{rnti} connectionConfig.APID];
        end
    end

    methods(Access=protected)
        function phyRx(obj, currTimingInfo, packets)
            %phyRx Physical layer reception

            puschRx(obj, currTimingInfo, packets); % Receive PUSCH(s)
            srsRx(obj, currTimingInfo, packets); % Receive SRS(s)
        end

        function puschRx(obj, currTimingInfo, packetList)
            %puschRx Process the received PUSCH packet(s) from AP

            % Read context of PUSCH(s) scheduled for current time
            symbolNumFrame = mod(currTimingInfo.NSlot*14 + currTimingInfo.NSymbol - 1, ...
                obj.CarrierInformation.SymbolsPerFrame); % Previous symbol in a 10 ms frame
            puschInfoList = obj.DataRxContext{symbolNumFrame+1};

            if isempty(puschInfoList) || isempty(packetList)
                return;
            end

            % Set carrier information
            carrierConfigInfo = obj.CarrierConfig;
            slotsPerSubframe = obj.WaveformInfo.SlotsPerSubframe;
            [carrierConfigInfo.NSlot, carrierConfigInfo.NFrame] = txSlotInfo(obj, slotsPerSubframe, currTimingInfo);

            % Decode the PUSCH(s) to extract MAC PDU(s), and
            % corresponding effective SINR
            [macPDUList, ~] = decodePUSCH(obj, cell2mat(puschInfoList), packetList, carrierConfigInfo);

            numPUSCH = numel(puschInfoList);
            % Send the PUSCH decode information to MAC and update the PHY stats
            for i=1:numPUSCH % For each PUSCH to be received
                macPDUInfo = macPDUList(i);
                % Rx callback to MAC
                obj.RxIndicationFcn(macPDUInfo, currTimingInfo.Time);
                % Increment the number of received packets for UE
                rnti = macPDUInfo.RNTI;
                obj.StatReceivedPackets(rnti) = obj.StatReceivedPackets(rnti) + 1;
                % Increment the number of decode failures received for UE
                obj.StatDecodeFailures(rnti) = obj.StatDecodeFailures(rnti) + macPDUInfo.CRCFlag;
            end
            obj.DataRxContext{symbolNumFrame+1} = {}; % Clear the context
        end

        function srsRx(obj, currTimingInfo, packetList)
            %srsRx Preocess the received SRS(s) from the AP

            % Read context of SRS scheduled for current time
            symbolNumFrame = mod(currTimingInfo.NSlot*14 + currTimingInfo.NSymbol - 1, ...
                obj.CarrierInformation.SymbolsPerFrame);
            srsInfoList = obj.SRSInfo{symbolNumFrame+1};

            if isempty(srsInfoList) || isempty(packetList)
                return;
            end

            % Set carrier information
            carrierConfigInfo = obj.CarrierConfig;
            slotsPerSubframe = obj.WaveformInfo.SlotsPerSubframe;
            [carrierConfigInfo.NSlot, carrierConfigInfo.NFrame] = txSlotInfo(obj, slotsPerSubframe, currTimingInfo);

            % Channel measurement on SRS
            [srsMeasurement, ~] = decodeSRS(obj, srsInfoList, packetList, carrierConfigInfo);

            % Report measurements to MAC
            for i=1:length(srsMeasurement)
                obj.SRSIndicationFcn(srsMeasurement(i));
            end
            obj.SRSInfo{symbolNumFrame + 1} = []; % Clear the context
        end
    end

    methods(Access=protected)
        function data = populatePDSCH(obj, pdschInfo, macPDU)
            %populatePDSCH Returns the data depending upon the Split.
            % Centralized   - Returns the Tx grid with PDSCH and DMRS
            %                 symbols after precoding and beamforming.
            % 7.2x          - Returns an array with PDSCH and DMRS symbols
            %                 on PDSCH and DMRS indices without precoding and
            %                 beamforming.
            % Distributed   - Returns the Coded transport block for PDSCH.

            if ~isempty(macPDU)
                % A non-empty MAC PDU is sent by MAC which indicates new
                % transmission
                macPDUBitmap = int2bit(macPDU, 8);
                macPDUBitmap = reshape(macPDUBitmap', [], 1); % Convert to column vector
                setTransportBlock(obj.DLSCHEncoders{pdschInfo.PDSCHConfig.RNTI}, macPDUBitmap, 0, pdschInfo.HARQID);
            end

            % Calculate PDSCH indices and information
            obj.CarrierConfig.NSlot = pdschInfo.NSlot;
            [pdschIndices, pdschIndicesInfo] = nrPDSCHIndices(obj.CarrierConfig, pdschInfo.PDSCHConfig);

            % Encode the DL-SCH transport blocks
            obj.DLSCHEncoders{pdschInfo.PDSCHConfig.RNTI}.TargetCodeRate = pdschInfo.TargetCodeRate;
            codedTrBlock = obj.DLSCHEncoders{pdschInfo.PDSCHConfig.RNTI}.step(pdschInfo.PDSCHConfig.Modulation, ...
                pdschInfo.PDSCHConfig.NumLayers, pdschIndicesInfo.G, pdschInfo.RV, pdschInfo.HARQID);

            % For Distributed Split data will be codedTrBlock
            data = codedTrBlock;

            if strcmp(obj.Split, "7.2x") || strcmp(obj.Split, "Centralized")
                % PDSCH Scrambling, Modulation and Layer Mapping
                pdschSymbols = nrPDSCH(obj.CarrierConfig, pdschInfo.PDSCHConfig, codedTrBlock);

                % Calculate DMRS Symbols and their Indices
                dmrsSymbols = nrPDSCHDMRS(obj.CarrierConfig, pdschInfo.PDSCHConfig);
                dmrsIndices = nrPDSCHDMRSIndices(obj.CarrierConfig, pdschInfo.PDSCHConfig);

                % Put PDSCH and DMRS symbols in a symbol array
                symbolArray(pdschIndices) = pdschSymbols;
                symbolArray(dmrsIndices) = dmrsSymbols;
                % Put PDSCH and DMRS indices in a indices array
                indicesArray(pdschIndices) = 1;
                indicesArray(dmrsIndices) = 2;

                % For 7.2x Split data will be PDSCH and DMRS symbols with
                % there indices
                data = {symbolArray.', indicesArray.'};
            end

            if strcmp(obj.Split, "Centralized")
                W = pdschInfo.PrecodingMatrix;
                numTxAntennas = size(W, 2);

                % Initialize Tx grid
                txGrid = zeros(obj.CarrierInformation.NumResourceBlocks*12, obj.WaveformInfo.SymbolsPerSlot, ...
                    numTxAntennas);
                obj.CarrierConfig.NSlot = pdschInfo.NSlot;

                % PDSCH precoding and mapping
                [pdschAntSymbols, pdschAntIndices] = nrPDSCHPrecode(obj.CarrierConfig, pdschSymbols, pdschIndices, W);
                txGrid(pdschAntIndices) = pdschAntSymbols;

                % PDSCH DM-RS precoding and mapping
                [dmrsAntSymbols, dmrsAntIndices] = nrPDSCHPrecode(obj.CarrierConfig, dmrsSymbols, dmrsIndices, W);
                txGrid(dmrsAntIndices) = dmrsAntSymbols;

                % PDSCH beamforming
                if ~isempty(pdschInfo.BeamIndex)
                    numPorts = size(txGrid, 3);
                    bfGrid = reshape(txGrid, [], numPorts)*repmat(obj.BeamWeightTable(:, pdschInfo.BeamIndex)', numPorts, 1);
                    txGrid = reshape(bfGrid, size(txGrid));
                end

                % For Centralized Split data will be the Tx grid
                data = txGrid;
            end
        end

        function txGrid = populateCSIRS(obj, csirsInfo)
            %populateCSIRS Populate CSI-RS symbols in the Tx grid for all
            % the Splits.

            % Populate Tx grid
            txGrid = zeros(obj.CarrierInformation.NumResourceBlocks*12, obj.WaveformInfo.SymbolsPerSlot, csirsInfo.NumCSIRSPorts);
            csirsInd = nrCSIRSIndices(obj.CarrierConfig, csirsInfo);
            csirsSym = nrCSIRS(obj.CarrierConfig, csirsInfo);
            txGrid(csirsInd) = csirsSym;
        end

        function [macPDU, crcFlag] = puschRxProcessing(obj, puschInfo, packetInfoList, carrierConfigInfo, numSampleChannelDelay)
            %puschRxProcessing Will do different processings for each Split.
            % Centralized   - Decode the PDSCH signal using Rx Waveforms
            % 7.2x          - Decode the PDSCH signal using Rx Grid
            % Distributed   - Decode final data bits using ulschLLRs

            if strcmp(obj.Split, "Centralized")
                % Combine Rx waveform
                rxWaveform = packetInfoList(1).Data;
                for i=2:length(packetInfoList)
                    rxWaveform = [rxWaveform packetInfoList(i).Data];
                end

                % Combine path gains
                pathGains = packetInfoList(1).Metadata.Channel.PathGains;
                for i=2:length(packetInfoList)
                    pathGains = cat(4, pathGains, packetInfoList(i).Metadata.Channel.PathGains);
                end
                % Number of Rx antennas for this perticular reception
                numRxAntennas = size(pathGains, 4);

                % Perfect Timing Estimate
                offset = nrPerfectTimingEstimate(pathGains, packetInfoList(1).Metadata.Channel.PathFilters.');

                % Perfect channel estimation
                estChannelGrid = nrPerfectChannelEstimate(pathGains, packetInfoList(1).Metadata.Channel.PathFilters.', ...
                    carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                    packetInfoList(1).Metadata.Channel.SampleTimes);

                % Initialize slot-length waveform
                [startSampleIdx, endSampleIdx] = sampleIndices(obj, puschInfo.NSlot, 0, carrierConfigInfo.SymbolsPerSlot-1);
                slotWaveform = zeros((endSampleIdx-startSampleIdx+1)+numSampleChannelDelay, numRxAntennas);

                % Populate the received waveform at appropriate indices in the slot-length waveform
                startSym = puschInfo.PUSCHConfig.SymbolAllocation(1);
                endSym = startSym+puschInfo.PUSCHConfig.SymbolAllocation(2)-1;
                [startSampleIdx, ~] = sampleIndices(obj, puschInfo.NSlot, startSym, endSym);
                slotWaveform(startSampleIdx : startSampleIdx+length(rxWaveform)-1, :) = rxWaveform;

                % Perform OFDM demodulation on the received data to recreate the
                % resource grid, including padding in the event that practical
                % synchronization results in an incomplete slot being demodulated
                slotWaveform = slotWaveform(1+offset:end, :);
                rxGrid = nrOFDMDemodulate(carrierConfigInfo, slotWaveform);
            end

            if strcmp(obj.Split, "Centralized") || strcmp(obj.Split, "7.2x")
                if strcmp(obj.Split, "7.2x")
                    % Combine Rx Grid coming from AP
                    rxGrid = packetInfoList(1).Data;
                    for i=2:length(packetInfoList)
                        rxGrid = cat(3, rxGrid, packetInfoList(i).Data);
                    end

                    % Calculate and combine channel estimates
                    pathGains = packetInfoList(1).Metadata.Channel.PathGains;
                    % Perfect Timing Estimate
                    offset = nrPerfectTimingEstimate(pathGains, packetInfoList(1).Metadata.Channel.PathFilters.');
                    % Perfect channel estimation
                    estChannelGrid = nrPerfectChannelEstimate(pathGains, packetInfoList(1).Metadata.Channel.PathFilters.', ...
                        carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                        packetInfoList(1).Metadata.Channel.SampleTimes);
                    for i=2:length(packetInfoList)
                        pathGains = packetInfoList(i).Metadata.Channel.PathGains;
                        % Perfect Timing Estimate
                        offset = nrPerfectTimingEstimate(pathGains, packetInfoList(i).Metadata.Channel.PathFilters.');
                        % Perfect channel estimation
                        estH = nrPerfectChannelEstimate(pathGains, packetInfoList(i).Metadata.Channel.PathFilters.', ...
                            carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                            packetInfoList(i).Metadata.Channel.SampleTimes);
                        estChannelGrid = cat(3, estChannelGrid, estH);
                    end
                    % Number of Rx antennas for this perticular reception
                    numRxAntennas = size(estChannelGrid, 3);
                end

                % Apply MIMO deprecoding to estChannelGrid to give an estimate
                % per transmission layer
                F = eye(puschInfo.PUSCHConfig.NumAntennaPorts, packetInfoList(1).NumTransmitAntennas);
                K = size(estChannelGrid,1);
                estChannelGrid = reshape(estChannelGrid,K*carrierConfigInfo.SymbolsPerSlot*numRxAntennas,packetInfoList(1).NumTransmitAntennas);
                estChannelGrid = estChannelGrid * F.';
                estChannelGrid = estChannelGrid * packetInfoList(1).Metadata.PrecodingMatrix.';
                estChannelGrid = reshape(estChannelGrid,K,carrierConfigInfo.SymbolsPerSlot,numRxAntennas,[]);

                % Noise variance
                noiseEst = calculateThermalNoise(obj);

                % Get PUSCH resource elements from the received grid
                [puschIndices, ~] = nrPUSCHIndices(carrierConfigInfo, puschInfo.PUSCHConfig);
                [puschRx, puschHest] = nrExtractResources(puschIndices, rxGrid, estChannelGrid);

                % Equalization
                [puschEq, csi] = nrEqualizeMMSE(puschRx, puschHest, noiseEst);

                % Decode PUSCH physical channel
                puschInfo.PUSCHConfig.TransmissionScheme = 'nonCodebook';
                [ulschLLRs, rxSymbols] = nrPUSCHDecode(carrierConfigInfo, puschInfo.PUSCHConfig, puschEq, noiseEst);

                csi = nrLayerDemap(csi);
                Qm = length(ulschLLRs) / length(rxSymbols);
                csi = reshape(repmat(csi{1}.',Qm,1),[],1);
                ulschLLRs = ulschLLRs .* csi;
            end

            if strcmp(obj.Split, "Distributed")
                ulschLLRs = packetInfoList(1).Data;
                for i=2:length(packetInfoList)
                    ulschLLRs = ulschLLRs + packetInfoList(i).Data; %ulschLLRs
                end
            end

            % Decode the UL-SCH transport channel
            obj.ULSCHDecoders{puschInfo.PUSCHConfig.RNTI}.TransportBlockLength = puschInfo.TBS*8;
            obj.ULSCHDecoders{puschInfo.PUSCHConfig.RNTI}.TargetCodeRate = puschInfo.TargetCodeRate;
            [decbits, crcFlag] = obj.ULSCHDecoders{puschInfo.PUSCHConfig.RNTI}.step(ulschLLRs, ...
                puschInfo.PUSCHConfig.Modulation, puschInfo.PUSCHConfig.NumLayers, puschInfo.RV, puschInfo.HARQID);

            if puschInfo.RV == obj.RVSequence(end)
                % The last redundancy version failed. Reset the soft buffer
                resetSoftBuffer(obj.ULSCHDecoders{puschInfo.PUSCHConfig.RNTI}, puschInfo.HARQID);
            end

            % Convert bit stream to byte stream
            macPDU = bit2int(decbits, 8);
        end

        function [srsMeasurement, sinrList] = srsRxProcessing(obj, packets, carrierConfigInfo)
            % SRS measurement on Rx waveform from packet data

            if strcmp(obj.Split, "Centralized")
                % Combine Path Gains
                pathGains = packets(1).Metadata.Channel.PathGains;
                for i=2:length(packets)
                    pathGains = cat(4, pathGains, packets(i).Metadata.Channel.PathGains);
                end

                % Perfect Timing Estimate
                offset = nrPerfectTimingEstimate(pathGains, packets(1).Metadata.Channel.PathFilters.');
                % Perfect Channel Estimate
                estChannelGrid = nrPerfectChannelEstimate(pathGains, packets(1).Metadata.Channel.PathFilters.', ...
                    carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                    packets(1).Metadata.Channel.SampleTimes);

            elseif strcmp(obj.Split, "7.2x")
                % Calculate and combine channel estimates
                pathGains = packets(1).Metadata.Channel.PathGains;
                % Perfect Timing and Channel Estimate
                offset = nrPerfectTimingEstimate(pathGains, packets(1).Metadata.Channel.PathFilters.');
                estChannelGrid = nrPerfectChannelEstimate(pathGains, packets(1).Metadata.Channel.PathFilters.', ...
                    carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                    packets(1).Metadata.Channel.SampleTimes);
                for i=2:length(packets)
                    pathGains = packets(i).Metadata.Channel.PathGains;
                    % Perfect Timing and Channel Estimate
                    offset = nrPerfectTimingEstimate(pathGains, packets(i).Metadata.Channel.PathFilters.');
                    estH = nrPerfectChannelEstimate(pathGains, packets(i).Metadata.Channel.PathFilters.', ...
                        carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                        packets(i).Metadata.Channel.SampleTimes);
                    estChannelGrid = cat(3, estChannelGrid, estH);
                end
            else 
                % Combine channel estimates coming from the APs
                estChannelGrid = packets(1).Data;
                for i=2:length(packets)
                    estChannelGrid = cat(3, estChannelGrid, packets(i).Data);
                end
            end

            rnti = packets(1).Metadata.RNTI;
            rank = obj.RankIndicator(rnti);
            srsSymbols = packets(1).Metadata.PacketConfig.SymbolStart + (1:packets(1).Metadata.PacketConfig.NumSRSSymbols);
            nVar = calculateThermalNoise(obj);
            [pmi, ~, ~] = nr5g.internal.nrPMISelect(rank, estChannelGrid(:,srsSymbols,:,:), nVar, obj.CarrierInformation.NumResourceBlocks);

            if ~any(isnan(pmi))
                % CQI Selection
                blerThreshold = 0.1;
                overhead = 0;
                puschConfiguration = nrPUSCHConfig;
                puschConfiguration.NumLayers = 1;
                puschConfiguration.PRBSet = (0:obj.CarrierConfig.NSizeGrid-1);
                wtx = nrPUSCHCodebook(rank,size(estChannelGrid,4),pmi);
                noiseEst = calculateThermalNoise(obj);
                [obj.L2SMsSRS(rnti),SINRs] = nr5g.internal.L2SM.linkQualityModel(obj.L2SMsSRS(rnti),obj.CarrierConfig,puschConfiguration,estChannelGrid,noiseEst,wtx);
                [obj.L2SMsSRS(rnti),mcs,mcsInfo] = nr5g.internal.L2SM.cqiSelect(obj.L2SMsSRS(rnti), ...
                    obj.CarrierConfig,puschConfiguration,overhead,SINRs,obj.MCSTableValues,blerThreshold);
                sinrList = mcsInfo.EffectiveSINR;
                % Fill SRS measurements
                srsMeasurement.RNTI = rnti;
                srsMeasurement.RankIndicator = rank;
                srsMeasurement.TPMI = pmi;
                srsMeasurement.MCSIndex = mcs;


                % Compute DL channel measurements based on TDD reciprocity
                PRGBundleSize = [];
                carrier = carrierConfigInfo;
                estChannelGrid = permute(estChannelGrid,[1 2 4 3]);
                mcsTable = "qam256";
                srsConfig = packets(1).Metadata.PacketConfig;
                pdschConfig = nrPDSCHConfig;
                pdschConfig.PRBSet = (0:carrierConfigInfo.NSizeGrid-1);
                enablePRGLevelMCS = 0;

                % Compute rank, precoder and MCS on SRS measurements
                [DLRank,Wp,MCSIndex] = nr5g.internal.nrSRSDLChannelMeasurements(carrier,srsConfig,pdschConfig,...
                    estChannelGrid,nVar,mcsTable,PRGBundleSize,enablePRGLevelMCS);

                % Set SRS measurement structure to include DL CSI
                srsBasedDLMeasurements.MCSIndex = MCSIndex;
                srsBasedDLMeasurements.W = Wp.';
                srsBasedDLMeasurements.RI = DLRank;
                srsBasedDLMeasurements.APOrder = [packets(:).TransmitterID];
                srsMeasurement.SRSBasedDLMeasurements = srsBasedDLMeasurements;
            else
                % Ignore SRS measurement report
                srsMeasurement = [];
                sinrList = -Inf;
            end
        end

        function nextInvokeTime = getNextInvokeTime(obj)
            %getNextInvokeTime Return the next invoke time in nanoseconds

            nextInvokeTime = min(obj.NextTxTime);
        end
    end
end