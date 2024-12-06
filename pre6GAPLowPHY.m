classdef pre6GAPLowPHY < nr5g.internal.nrGNBPHY

    properties(SetAccess=private)
        %APCellID Physical layer cell identity for the AP.
        APCellID

        %CPUID Node ID of the CPU to which AP is connected
        CPUNodeID

        % ConnectedUEs RNTI of the UEs connected to the AP, represented as vector of integers
        ConnectedUEs
    end

    % MAC Properties
    properties(Access=protected)
        %DuplexModeNumber Duplexing mode (FDD or TDD)
        % Value 0 means FDD and 1 means TDD
        DuplexModeNumber

        %NumDLULPatternSlots Number of slots in DL-UL pattern (for TDD mode)
        NumDLULPatternSlots

        %DLULSlotFormat Format of the slots in DL-UL pattern (for TDD mode)
        % N-by-14 matrix where 'N' is number of slots in DL-UL pattern. Each row
        % contains the symbol type of the 14 symbols in the slot. Value 0, 1 and 2
        % represent DL symbol, UL symbol, guard symbol, respectively.
        DLULSlotFormat

        %MCSTableUL MCS table used for uplink. It contains the mapping of MCS
        %indices with Modulation and Coding schemes
        MCSTableUL

        %PUSCHDMRSAdditionalPosTypeA Additional PUSCH DM-RS positions for type A (0..3)
        PUSCHDMRSAdditionalPosTypeA = 0;

        %PUSCHDMRSAdditionalPosTypeB Additional PUSCH DM-RS positions for type B (0..3)
        PUSCHDMRSAdditionalPosTypeB = 0;

        %NumSlotsFrame Number of slots in a 10 ms frame. Depends on the SCS used
        NumSlotsFrame

        %NumSymInFrame  Number of symbols in a 10 ms frame
        NumSymInFrame

        %SlotDurationInNS Slot duration in nanoseconds
        SlotDurationInNS

        %CarrierConfigUL nrCarrierConfig object for UL
        CarrierConfigUL

        %SRSRxInfo Contains the information about SRS receptions
        % It is an array of size N-by-2 where N is the number of unique
        % SRS periodicity, slot offset pairs configured for the UEs. Each
        % row of the array contains SRS reception periodicity (in
        % nanoseconds) and the next absolute reception start time (in
        % nanoseconds) from the UEs.
        SRSRxInfo = [Inf Inf]

        %SRSConfiguration Sounding reference signal (SRS) resource configuration for the UEs
        % Array containing the SRS configuration information. Each element is an
        % object of type nrSRSConfig. For a UE, it is an array of size 1. For a
        % AP, it is an array of size equal to number of UEs connected to the AP.
        % An element at index 'i' stores the SRS configuration of UE with RNTI 'i'.
        SRSConfiguration

        %UplinkRxContext Rx context used for PUSCH reception
        % N-by-P cell array where 'N' is the number of UEs and 'P' is the
        % number of symbols in a 10 ms frame. It stores uplink resource
        % assignment details done to UEs. This is used by AP in the
        % reception of uplink packets. An element at position (i, j) stores
        % the uplink grant corresponding to a PUSCH reception expected from
        % UE with RNTI 'i' starting at symbol 'j' from the start of the frame. If
        % there is no assignment, cell element is empty
        UplinkRxContext

        %PUSCHInfoStruct PUSCH information structure
        PUSCHInfo = struct('NSlot',[],'HARQID',[],'NewData',[],'RV',[],'TargetCodeRate',[],'TBS',[],'PUSCHConfig',nrPUSCHConfig);
    end

    properties(SetAccess=protected, Hidden)
        %L2SMsSRS L2SM context for SRS
        % It is an array of objects of length 'N' where N is the number of UEs in
        % the cell.
        L2SMsSRS

        %CurrDLULSlotIndex Slot index of the current running slot in the DL-UL pattern (for TDD mode)
        CurrDLULSlotIndex = 0;

        %LastRxTime Timestamp when MAC last instructed PHY to receive a packet (in nanoseconds)
        LastRxTime = -1;

        %PreviousSymbol Previous symbol in the current frame. This helps to
        %avoid running scheduler and performing CSI-RS/SRS related
        %operations multiple times in a symbol
        PreviousSymbol = -1;
    end

    properties (SetAccess = private, Hidden)
        %Split Specify the Split as "Centralized" or "Distributed" or "7.2x".
        %   The value "Centralized" represents Centralized Realization of Cell-Free.
        %   The value "Distributed" represents Distributed Realization of Cell-Free.
        %   The value "7.2x" represents Cell-Free will follow 7.2x Split of O-RAN Standards.
        Split
    end

    properties (Constant)
        %DLType Value to specify downlink direction or downlink symbol type
        DLType = nr5g.internal.MACConstants.DLType;

        %ULType Value to specify uplink direction or uplink symbol type
        ULType = nr5g.internal.MACConstants.ULType;

        %GuardType Value to specify guard symbol type
        GuardType = nr5g.internal.MACConstants.GuardType;
    end

    methods
        function obj = pre6GAPLowPHY(param, notificationFcn)
            % Call Constructor from Base Class
            obj = obj@nr5g.internal.nrGNBPHY(param, notificationFcn);
        end

        function addConnectionToCPU(obj, param)
            %addConnectionToCPU Add Connetion Context from CPU

            obj.APCellID = param.NCellID;
            obj.DuplexModeNumber = 0;
            slotDuration = 1/(param.SubcarrierSpacing/15); % In ms
            obj.SlotDurationInNS = slotDuration * 1e6; % In nanoseconds
            if strcmp(param.DuplexMode, "TDD")
                obj.DuplexModeNumber = 1;
                configTDD = param.DLULConfigTDD;
                numDLULPatternSlots = configTDD.DLULPeriodicity/slotDuration;
                obj.NumDLULPatternSlots = numDLULPatternSlots;

                numDLSlots = configTDD.NumDLSlots;
                numDLSymbols = configTDD.NumDLSymbols;
                numULSlots = configTDD.NumULSlots;
                numULSymbols = configTDD.NumULSymbols;
                % All the remaining symbols in DL-UL pattern are assumed to be guard symbols
                guardDuration = (numDLULPatternSlots * 14) - ...
                    (((numDLSlots + numULSlots)*14) + ...
                    numDLSymbols + numULSymbols);

                % Set format of slots in the DL-UL pattern. Value 0, 1 and 2 means symbol
                % type as DL, UL and guard, respectively
                obj.DLULSlotFormat = obj.GuardType * ones(numDLULPatternSlots, 14);
                obj.DLULSlotFormat(1:numDLSlots, :) = obj.DLType; % Mark all the symbols of full DL slots as DL
                obj.DLULSlotFormat(numDLSlots + 1, 1 : numDLSymbols) = obj.DLType; % Mark DL symbols following the full DL slots
                obj.DLULSlotFormat(numDLSlots + floor(guardDuration/14) + 1, (numDLSymbols + mod(guardDuration, 14) + 1) : end)  ...
                    = obj.ULType; % Mark UL symbols at the end of slot before full UL slots
                obj.DLULSlotFormat((end - numULSlots + 1):end, :) = obj.ULType; % Mark all the symbols of full UL slots as UL type
            end

            obj.PUSCHInfo.PUSCHConfig.NID = pre6GAP.getCPUCellID(obj.APCellID);

            inputParam = ["CPUNodeID", "Split"];
            for idx=1:numel(inputParam)
                obj.(char(inputParam(idx))) = param.(inputParam(idx));
            end

            % Set Carrier Information
            setCarrierInformation(obj, createCarrierStruct(obj, param));

            obj.NumSlotsFrame = obj.CarrierInformation.SlotsPerFrame;
            symbolsPerFrame = obj.CarrierInformation.SlotsPerSubframe*10*14;
            obj.NumSymInFrame = symbolsPerFrame;
            obj.SRSInfo = cell(symbolsPerFrame, 1);
            obj.NextRxTime = Inf*ones(symbolsPerFrame, 1);

            if isfield(param, "CQITable")
                setCQITable(obj, param.CQITable);
            end

            obj.CarrierConfigUL = nrCarrierConfig("SubcarrierSpacing",param.SubcarrierSpacing);
            obj.CarrierConfigUL.NSizeGrid = param.NumResourceBlocks;

            % 5G NR packet
            obj.PacketStruct.NumTransmitAntennas = obj.NumTransmitAntennas;
            obj.PacketStruct.CenterFrequency = obj.CarrierInformation.DLCarrierFrequency;
            obj.PacketStruct.Bandwidth = obj.CarrierInformation.ChannelBandwidth;
            obj.PacketStruct.Abstraction = false; % Full PHY
            obj.PacketStruct.Metadata = struct("NCellID", obj.CarrierInformation.NCellID, "RNTI", [], ...
                "PrecodingMatrix", [], "NumSamples", [], "Channel", obj.PacketStruct.Metadata.Channel);

            % Initialize interference buffer
            obj.RxBuffer = wirelessnetwork.internal.interferenceBuffer(CenterFrequency=obj.CarrierInformation.ULCarrierFrequency, ...
                Bandwidth=obj.CarrierInformation.ChannelBandwidth, SampleRate=obj.WaveformInfo.SampleRate);

            % Set the MCS tables as matrices
            obj.MCSTableUL = nr5g.internal.MACConstants.MCSTable;
        end

        function addConnection(obj, connectionConfig)
            %addConnection Adds connection context of UE

            % Call addConnection from base class
            addConnection@nr5g.internal.nrGNBPHY(obj, connectionConfig);

            obj.ConnectedUEs = [obj.ConnectedUEs connectionConfig.RNTI];

            obj.UplinkRxContext = cell(connectionConfig.RNTI, obj.NumSymInFrame);
            obj.SRSConfiguration = [obj.SRSConfiguration connectionConfig.SRSConfiguration];
            obj.SRSRxInfo = calculateSRSPeriodicity(obj, obj.SRSConfiguration);
            obj.L2SMsSRS = [obj.L2SMsSRS; nr5g.internal.L2SM.initialize(obj.CarrierConfig)];
        end

        function nextInvokeTime = run(obj, currentTime, packets)
            %run Run the PHY layer operations and return the next invoke time (in nanoseconds)

            symEndTimes = obj.CarrierInformation.SymbolTimings;
            slotDuration = obj.CarrierInformation.SlotDuration; % In nanoseconds

            absoluteSlotNum = floor(currentTime/slotDuration);

            % Find the duration completed in the current slot
            durationCompletedInCurrSlot = mod(currentTime, slotDuration);

            % Calculate the current AFN, slot and symbol
            currTimeInfo = obj.CurrTimeInfo;
            currTimeInfo.Timestamp = currentTime;
            currTimeInfo.NFrame = floor(currentTime/obj.FrameDurationInNS);
            currTimeInfo.NSlot = mod(floor(currentTime/slotDuration), obj.CarrierInformation.SlotsPerFrame);
            currTimeInfo.NSymbol = find(durationCompletedInCurrSlot < symEndTimes, 1) - 1;

            if obj.DuplexModeNumber % TDD
                % Current slot number in DL-UL pattern
                obj.CurrDLULSlotIndex = mod(absoluteSlotNum, obj.NumDLULPatternSlots);
            end

            elapsedTime = currentTime - obj.LastRunTime;

            % Run MAC oerations only once in the same symbol
            symNumFrame = currTimeInfo.NSlot * nr5g.internal.nrMAC.NumSymbols + currTimeInfo.NSymbol;
            if ~(obj.PreviousSymbol == symNumFrame && elapsedTime < obj.SlotDurationInNS/nr5g.internal.nrMAC.NumSymbols)

                dataRxMAC(obj, currTimeInfo);

                idxList = find(obj.SRSRxInfo(:, 2) == currentTime);
                if ~isempty(idxList)
                    ulControlRequestMAC(obj, currTimeInfo);
                    % Update the next SRS Rx times
                    obj.SRSRxInfo(idxList, 2) = obj.SRSRxInfo(idxList, 1) + currentTime;
                end

                % Update the previous symbol to the current symbol in the frame
                obj.PreviousSymbol = symNumFrame;
            end

            % PHY Operations
            [txPkts, rxPkts, controlPktsDL, controlPktsUL] = segregatePackets(obj, packets);

            % Send the control packets
            processControlPackets(obj, currTimeInfo, controlPktsDL, controlPktsUL);

            % Process the Tx Packets for DL Transmission
            phyTx(obj, txPkts);

            % Store Rx Packets in an interference buffer
            storeReception(obj, rxPkts);

            % Process the Rx Packets from the interference buffer
            phyRx(obj, currTimeInfo);

            % Get the next invoke time
            nextInvokeTime = getNextInvokeTime(obj);
        end
    end

    % MAC functions
    methods(Access=private, Hidden)
        function srsInfo = calculateSRSPeriodicity(obj, srsConfig)
            %calculateSRSPeriodicity Calculates SRS Periodicity

            srsInfo = inf(1, 2);
            count = 0;
            for idx=1:length(srsConfig)
                if isa(srsConfig(idx), 'nrSRSConfig')
                    if ischar(srsConfig(idx).SRSPeriod)
                        if strcmp(srsConfig(idx).SRSPeriod, 'on')
                            % SRS resource is present in all the slots
                            count = count + 1;
                            srsInfo(count, 1) = obj.SlotDurationInNS;
                            srsInfo(count, 2) = 0;
                        end
                    else
                        % SRS resource is present in specific slots
                        % represented as periodicity and slot offset pairs
                        count = count + 1;
                        srsInfo(count, 1) = max(srsConfig(idx).SRSPeriod) * obj.SlotDurationInNS;
                        srsInfo(count, 2) = min(srsConfig(idx).SRSPeriod) * obj.SlotDurationInNS;
                    end
                end
            end
            srsInfo = unique(srsInfo(1:end, :), 'rows');
        end

        function dataRxMAC(obj, currentTimeInfo)
            %dataRx Send Rx start request to PHY for the receptions scheduled to start now

            if ~isempty(obj.UplinkRxContext)
                gNBRxContext = obj.UplinkRxContext(:, (currentTimeInfo.NSlot * nr5g.internal.nrMAC.NumSymbols) + currentTimeInfo.NSymbol + 1); % Rx context of current symbol
                txUEs = find(~cellfun(@isempty, gNBRxContext)); % UEs which are assigned uplink grants starting at this symbol
                for i = 1:length(txUEs)
                    % For the UE, get the uplink grant information
                    uplinkGrant = gNBRxContext{txUEs(i)};
                    % Send the UE uplink Rx context to PHY
                    rxRequestToPHYFromMAC(obj, txUEs(i), uplinkGrant, currentTimeInfo);
                    obj.LastRxTime = currentTimeInfo.Time;
                end
                obj.UplinkRxContext(:, (currentTimeInfo.NSlot * nr5g.internal.nrMAC.NumSymbols) + currentTimeInfo.NSymbol + 1) = {[]}; % Clear uplink RX context
            end
        end

        function rxRequestToPHYFromMAC(obj, rnti, uplinkGrant, currTimingInfo)
            %rxRequestToPHY Send Rx request to PHY

            puschInfo = obj.PUSCHInfo; % Information to be passed to PHY for PUSCH reception
            puschInfo.PUSCHConfig.PRBSet = uplinkGrant.PRBSet;
            % Get the corresponding row from the mcs table
            mcsInfo = obj.MCSTableUL(uplinkGrant.MCSIndex + 1, :);
            modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme (stored in column 1)
            puschInfo.TargetCodeRate = mcsInfo(2)/1024; % Coderate (stored in column 2)
            % Modulation scheme and corresponding bits/symbol
            modScheme = nr5g.internal.getModulationScheme(modSchemeBits); % Get modulation scheme string
            puschInfo.PUSCHConfig.Modulation = modScheme(1);
            puschInfo.PUSCHConfig.RNTI = rnti;
            puschInfo.NSlot = currTimingInfo.NSlot;
            puschInfo.HARQID = uplinkGrant.HARQID;
            puschInfo.RV = uplinkGrant.RV;
            % For runtime optimization, fill fields in PUSCHConfig only if the value to
            % be filled is non-default
            if ~(uplinkGrant.StartSymbol == 0 && uplinkGrant.NumSymbols == 14)
                puschInfo.PUSCHConfig.SymbolAllocation = [uplinkGrant.StartSymbol uplinkGrant.NumSymbols];
            end
            if uplinkGrant.NumLayers ~= 1
                puschInfo.PUSCHConfig.NumLayers = uplinkGrant.NumLayers;
            end
            puschInfo.PUSCHConfig.TransmissionScheme = 'codebook';
            if uplinkGrant.NumAntennaPorts ~= 1
                puschInfo.PUSCHConfig.NumAntennaPorts = uplinkGrant.NumAntennaPorts;
            end
            puschInfo.PUSCHConfig.TPMI = uplinkGrant.TPMI;
            if isequal(uplinkGrant.MappingType, 'A')
                dmrsAdditonalPos = obj.PUSCHDMRSAdditionalPosTypeA;
            else
                puschInfo.PUSCHConfig.MappingType = uplinkGrant.MappingType;
                dmrsAdditonalPos = obj.PUSCHDMRSAdditionalPosTypeB;
            end
            if uplinkGrant.DMRSLength ~= 1
                puschInfo.PUSCHConfig.DMRS.DMRSLength = uplinkGrant.DMRSLength;
            end
            if dmrsAdditonalPos ~= 0
                puschInfo.PUSCHConfig.DMRS.DMRSAdditionalPosition = dmrsAdditonalPos;
            end
            if uplinkGrant.NumCDMGroupsWithoutData ~=2
                puschInfo.PUSCHConfig.DMRS.NumCDMGroupsWithoutData = uplinkGrant.NumCDMGroupsWithoutData;
            end
            % Carrier configuration
            carrierConfig = obj.CarrierConfigUL;
            carrierConfig.NSlot = puschInfo.NSlot;

            % Calculate TBS
            puschInfo.TBS = uplinkGrant.TBS; % TBS in bytes
            puschInfo.NewData = strcmp(uplinkGrant.Type, "newTx");

            % Call PHY to start receiving PUSCH
            obj.rxDataRequest(puschInfo, currTimingInfo);
        end

        function ulControlRequestMAC(obj, currTimingInfo)
            %ulControlRequest Request from MAC to PHY to receive non-data UL transmissions

            if ~isempty(obj.SRSConfiguration) % Check if SRS is enabled
                % Check if current slot is a slot with UL symbols. For FDD
                % (value 0), there is no need to check as every slot is a
                % UL slot. For TDD (value 1), check if current slot has any
                % UL symbols
                if obj.DuplexModeNumber == 0 || ~isempty(find(obj.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, :) == obj.ULType, 1))
                    ulControlType = zeros(1, length(obj.ConnectedUEs));
                    ulControlPDUs = cell(1, length(obj.ConnectedUEs));
                    numSRSUEs = 0; % Initialize number of UEs from which SRS is expected in this slot
                    % Set carrier configuration object
                    carrier = obj.CarrierConfigUL;
                    carrier.NSlot = currTimingInfo.NSlot;
                    carrier.NFrame = currTimingInfo.NFrame;
                    for rnti=1:length(obj.ConnectedUEs) % Send SRS reception request to PHY for the UEs
                        srsConfigUE = obj.SRSConfiguration(rnti);
                        if ~isempty(srsConfigUE)
                            srsLocations = srsConfigUE.SymbolStart : (srsConfigUE.SymbolStart + srsConfigUE.NumSRSSymbols-1); % SRS symbol locations
                            % Check whether the mode is FDD OR if it is TDD then all the SRS symbols must be UL symbols
                            if obj.DuplexModeNumber == 0 || all(obj.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, srsLocations+1) == obj.ULType)
                                srsInd = nrSRSIndices(carrier, srsConfigUE);
                                if ~isempty(srsInd) % Empty value means SRS is not scheduled to be received in the current slot for this UE
                                    numSRSUEs = numSRSUEs+1;
                                    ulControlType(numSRSUEs) = 1; % SRS PDU
                                    ulControlPDUs{numSRSUEs}{1} = rnti;
                                    ulControlPDUs{numSRSUEs}{2} = srsConfigUE;
                                end
                            end
                        end
                    end
                    ulControlType = ulControlType(1:numSRSUEs);
                    ulControlPDUs = ulControlPDUs(1:numSRSUEs);
                    obj.ulControlRequest(ulControlType, ulControlPDUs, currTimingInfo); % Send UL control request to PHY
                    if numSRSUEs > 0
                        obj.LastRxTime = currTimingInfo.Timestamp;
                    end
                end
            end
        end
    end

    methods(Hidden)
        function updateSRSPeriod(obj, rnti, srsPeriod)
            %updateSRSPeriod Update the SRS periodicity of UE
            idx = find(obj.ConnectedUEs == rnti, 1);

            obj.SRSConfiguration(idx).SRSPeriod = srsPeriod;
            % Calculate unique SRS reception time and periodicity
            obj.SRSRxInfo = calculateSRSPeriodicity(obj, obj.SRSConfiguration);
        end
    end

    % PHY functions
    methods(Access=protected)
        function processControlPackets(obj, currTimeInfo, controlPktsDL, controlPktsUL)
            %processControlPackets Process Control Packets for UL and DL Direction.

            % Process DL Control Packets
            for i=1:size(controlPktsDL, 1)
                packet = controlPktsDL(i);

                if packet.Metadata.PacketType == nr5g.internal.nrMAC.ULGrant
                    grant = packet.Data;
                    rnti = packet.Metadata.RNTI;
                    slotNum = mod(currTimeInfo.NSlot + grant.SlotOffset, obj.NumSlotsFrame); % Slot number in the frame for the grant
                    obj.UplinkRxContext{rnti, slotNum*nr5g.internal.nrMAC.NumSymbols + grant.StartSymbol + 1} = grant;
                end

                packet.Metadata.NCellID = obj.APCellID;
                destination = packet.Metadata.DirectID;
                packet.DirectToDestination = destination;
                obj.SendPacketFcn(packet);
            end

            % Process UL Control Packets
            for i=1:size(controlPktsUL, 1)
                packet = controlPktsUL(i);
                packet.Metadata.NCellID = pre6GAP.getCPUCellID(obj.APCellID);
                packet.DirectToDestination = obj.CPUNodeID;
                packet.Metadata.DirectID = 1;
                obj.SendPacketFcn(packet);
            end
        end

        function phyTx(obj, packets)
            %phyTx process and transmit the PDSCH or CSIRS packet(s)
            % receieved from CPU

            pdschPkts = []; csirsPkts = [];
            for i=1:length(packets)
                if packets(i).Metadata.PacketType == obj.PXSCHPacketType
                    pdschPkts = [pdschPkts; packets(i)];
                else
                    csirsPkts = [csirsPkts; packets(i)];
                end
            end
            if ~isempty(pdschPkts)
                pdschTx(obj, pdschPkts); % Transmit PDSCH(s)
            end
            if ~isempty(csirsPkts)
                csirsTx(obj, csirsPkts); % Transmit CSIRS(s)
            end
        end

        function phyRx(obj, currTimingInfo)
            %phyRx Physical layer reception

            % symbol number in the 10 ms frame
            symbolNumFrame = mod(currTimingInfo.NSlot*14 + currTimingInfo.NSymbol-1, ...
                obj.CarrierInformation.SymbolsPerFrame);

            if obj.NextRxTime(symbolNumFrame+1) ~= Inf % Check if any Rx is scheduled now
                puschRx(obj, currTimingInfo); % Receive PUSCH(s)
                srsRx(obj, currTimingInfo); % Receive SRS(s)
                obj.NextRxTime(symbolNumFrame+1) = Inf; % Reset
            end
        end

        function pdschTx(obj, pdschPkts)
            % Transmit the PDSCH(s) coming from CPU

            if strcmp(obj.Split, "Centralized")
                % Send the packet(s) directly to the Tx buffer
                for i=1:length(pdschPkts)
                    packet = pdschPkts(i);
                    % Signal amplitude. Account for FFT occupancy factor
                    signalAmp = db2mag(obj.TransmitPower-30)*sqrt(obj.WaveformInfo.Nfft^2/(12*obj.CarrierConfig.NSizeGrid *obj.NumTransmitAntennas));
                    % Apply the Tx power
                    packet.Data = signalAmp*packet.Data;
                    packet.Power = mag2db(signalAmp) + 30; %dBm
                    packet.DirectToDestination = 0;
                    packet.Metadata.NCellID = obj.APCellID;
                    obj.SendPacketFcn(packet);
                end
            else % 7.2x or Distributed Split
                for i=1:length(pdschPkts)
                    pktFromCPU = pdschPkts(i);
                    pdschInfoList = pktFromCPU.Metadata.Info;
                    cpuPDUs = pktFromCPU.Data;
                    pdschDataList = cell(length(pdschInfoList), 1);
                    % For each pdschInfo
                    for j=1:length(pdschInfoList)
                        % Update the precoding matrix in PDSCH info
                        pdschInfoList(j).PrecodingMatrix = pktFromCPU.Metadata.PrecodingMatrix{j};
                        % Get the PDSCH data after complete PHY processing
                        pdschDataList{j} = pdschData(obj, pdschInfoList(j), cpuPDUs{j});
                    end
                    packet = pdschPacket(obj, pdschInfoList, pdschDataList, pktFromCPU.StartTime, ...
                        pktFromCPU.Metadata.UETagInfo);
                    for j=1:numel(packet)
                        obj.SendPacketFcn(packet(j));
                    end
                end
            end
        end

        function csirsTx(obj, csirsPkts)
            % Transmit the CSIRS(s) coming from CPU for all Splits

            for i=1:size(csirsPkts, 1)
                packet = csirsPkts(i);
                % Apply Transmit Power to the signal amplitude
                signalAmp = db2mag(obj.TransmitPower-30)*sqrt(obj.WaveformInfo.Nfft^2/(12*obj.CarrierConfig.NSizeGrid *obj.NumTransmitAntennas));
                packet.Data = signalAmp*packet.Data;
                packet.Power = mag2db(signalAmp) + 30; %dBm
                packet.DirectToDestination = 0;
                packet.Metadata.NCellID = obj.APCellID;
                obj.SendPacketFcn(packet);
            end
        end

        function puschRx(obj, currTimingInfo)
            %puschRx Receive the PUSCH(s) scheduled for current time

            % Read context of PUSCH(s) scheduled for current time
            symbolNumFrame = mod(currTimingInfo.NSlot*14 + currTimingInfo.NSymbol - 1, ...
                obj.CarrierInformation.SymbolsPerFrame); % Previous symbol in a 10 ms frame
            puschInfoList = obj.DataRxContext{symbolNumFrame+1};

            if isempty(puschInfoList)
                return;
            end
            % Set carrier information
            carrierConfigInfo = obj.CarrierConfig;
            slotsPerSubframe = obj.WaveformInfo.SlotsPerSubframe;
            [carrierConfigInfo.NSlot, carrierConfigInfo.NFrame] = txSlotInfo(obj, slotsPerSubframe, currTimingInfo);

            % Initializations
            minStartTime = Inf;
            maxEndTime = 0;

            numPUSCH = length(puschInfoList);
            % Calculate the time window of PUSCH(s) to be received now
            for i=1:numPUSCH
                puschInfo = puschInfoList{i};
                [pktStartTime, pktEndTime] = pktTiming(obj, carrierConfigInfo.NFrame, ...
                    carrierConfigInfo.NSlot, puschInfo.PUSCHConfig.SymbolAllocation(1), ...
                    puschInfo.PUSCHConfig.SymbolAllocation(2));
                minStartTime = min([minStartTime pktStartTime]);
                maxEndTime = max([maxEndTime pktEndTime]);
            end

            decodePUSCH(obj, cell2mat(puschInfoList), minStartTime, maxEndTime, carrierConfigInfo)
            obj.DataRxContext{symbolNumFrame+1} = {};
        end

        function srsRx(obj, currTimingInfo)
            %srsRx Receive SRS(s) scheduled for current time

            % Read context of SRS scheduled for current time
            symbolNumFrame = mod(currTimingInfo.NSlot*14 + currTimingInfo.NSymbol - 1, ...
                obj.CarrierInformation.SymbolsPerFrame);
            srsInfoList = obj.SRSInfo{symbolNumFrame+1};
            if isempty(srsInfoList)
                return;
            end

            % Set carrier information
            carrierConfigInfo = obj.CarrierConfig;
            slotsPerSubframe = obj.WaveformInfo.SlotsPerSubframe;
            [carrierConfigInfo.NSlot, carrierConfigInfo.NFrame] = txSlotInfo(obj, slotsPerSubframe, currTimingInfo);

            [startTime, endTime] = pktTiming(obj, carrierConfigInfo.NFrame, ...
                carrierConfigInfo.NSlot, 0, carrierConfigInfo.SymbolsPerSlot);

            decodeSRS(obj, startTime, endTime, carrierConfigInfo);

            obj.SRSInfo{symbolNumFrame + 1} = [];
        end
    end

    methods(Hidden)
        function data = pdschData(obj, pdschInfo, cpuPDU)
            % Return the PDSCH waveform for 7.2x and Distributed Split

            % Fill the slot grid with PDSCH symbols
            pdschGrid = populatePDSCH(obj, pdschInfo, cpuPDU);
            % OFDM modulation
            txWaveform = nrOFDMModulate(obj.CarrierConfig, pdschGrid);
            % Signal amplitude. Account for FFT occupancy factor
            signalAmp = db2mag(obj.TransmitPower-30)*sqrt(obj.WaveformInfo.Nfft^2/(size(pdschGrid, 1)*obj.NumTransmitAntennas));
            % Apply the Tx power
            data = signalAmp*txWaveform;
        end

        function packet = pdschPacket(obj, pdschInfoList, pdschDataList, startTime, ueTagInfo)
            % Populate and return PDSCH packet to send it to Tx Buffer

            packet = obj.PacketStruct;
            scaledPower = db2mag(obj.TransmitPower-30) * sqrt((obj.WaveformInfo.Nfft^2) / (12*obj.CarrierConfig.NSizeGrid * obj.NumTransmitAntennas));
            packet.Power = mag2db(scaledPower) + 30; %dBm
            packet.Metadata.PacketType = obj.PXSCHPacketType;
            packet.StartTime = startTime;
            minStartSym = Inf;
            maxEndSym = 0;

            % Fill packet fields. A single packet is sent representing the combined
            % PDSCH waveform
            combinedWaveform = zeros(size(pdschDataList(1)));
            for i=1:numel(pdschInfoList) % For each PDSCH
                pdschInfo = pdschInfoList(i);
                packet.Metadata.PrecodingMatrix{i} = pdschInfo.PrecodingMatrix;
                packet.Metadata.PacketConfig(i) = pdschInfo.PDSCHConfig; % PDSCH Configuration
                packet.Metadata.RNTI(i) = pdschInfo.PDSCHConfig.RNTI;
                startSymIdx = pdschInfo.PDSCHConfig.SymbolAllocation(1)+1;
                pdschNumSym = pdschInfo.PDSCHConfig.SymbolAllocation(2);
                endSymIdx = startSymIdx+pdschNumSym-1;
                if (startSymIdx < minStartSym) % Update min start symbol
                    minStartSym = startSymIdx;
                end
                if (endSymIdx > maxEndSym)  % Update max end symbol
                    maxEndSym = endSymIdx;
                end
                combinedWaveform = combinedWaveform + pdschDataList{i};
            end
            packet.Tags = wirelessnetwork.internal.packetTags.add(packet.Tags, ...
                "UETagInfo", ueTagInfo, [1 numel(combinedWaveform)]);
            % Trim txWaveform to span only the transmission symbols
            [startSampleIdx, endSampleIdx] = sampleIndices(obj, pdschInfoList(1).NSlot, minStartSym-1, maxEndSym-1);
            packet.Data = combinedWaveform(startSampleIdx:endSampleIdx, :);
            packet.Duration = round(sum(obj.CarrierInformation.SymbolDurations(minStartSym:maxEndSym))/1e9,9);
            packet.Metadata.NumSamples = endSampleIdx-startSampleIdx+1;
            packet.SampleRate = obj.WaveformInfo.SampleRate;
        end

        function csirsData(~, ~); end

        function csirsPacket(~, ~, ~, ~); end

        function decodePUSCH(obj, puschInfoList, startTime, endTime, carrierConfigInfo)
            %decodePUSCH Process the PUSCH Signal according to the split
            % and sends it to CPU for further processing

            packetInfoList = packetList(obj.RxBuffer, startTime, endTime);

            for i=1:length(puschInfoList) % For each PUSCH to be received
                packetOfInterest = [];
                puschInfo = puschInfoList(i);
                [puschStartTime, puschEndTime] = pktTiming(obj, carrierConfigInfo.NFrame, ...
                    carrierConfigInfo.NSlot, puschInfo.PUSCHConfig.SymbolAllocation(1), ...
                    puschInfo.PUSCHConfig.SymbolAllocation(2));
                for j=1:length(packetInfoList) % Search PUSCH of interest in the list of received packets
                    packet = packetInfoList(j);

                    if (packet.Metadata.PacketType == obj.PXSCHPacketType) && ... % Check for PUSCH
                            any(carrierConfigInfo.NCellID == packet.Metadata.NCellID) && ... % Check for PUSCH of interest
                            (puschInfo.PUSCHConfig.RNTI == packet.Metadata.RNTI) && ...
                            (puschStartTime == packet.StartTime)
                        packetOfInterest = packet;
                        % Read the combined waveform received during packet's duration
                        rxWaveform = resultantWaveform(obj.RxBuffer, puschStartTime, puschStartTime+packet.Duration);
                        channelDelay = packet.Duration -(puschEndTime-puschStartTime);
                        numSampleChannelDelay = ceil(channelDelay*packet.SampleRate);
                        break;
                    end
                end

                if ~isempty(packetOfInterest)
                    if strcmp(obj.Split, "Centralized")
                        % Apply Rx Gain and Thermal Noise to Rx Waveform
                        rxWaveform = applyRxGain(obj, rxWaveform);
                        rxWaveform = applyThermalNoise(obj, rxWaveform);
                        % Scale Path Gains
                        pathGains = packetOfInterest.Metadata.Channel.PathGains * db2mag(packetOfInterest.Power-30) * db2mag(obj.ReceiveGain);
                        % Update the packet
                        packetOfInterest.Metadata.Channel.PathGains = pathGains;
                        packetOfInterest.Data = rxWaveform;
                    else
                        % PUSCH Rx processing
                        rxData = puschRxProcessing(obj, rxWaveform, puschInfo, ...
                            packetOfInterest, carrierConfigInfo, numSampleChannelDelay);
                        % Scale Path Gains (for 7.2x)
                        pathGains = packetOfInterest.Metadata.Channel.PathGains * db2mag(packetOfInterest.Power-30) * db2mag(obj.ReceiveGain);
                        % Update the packet
                        packetOfInterest.Metadata.Channel.PathGains = pathGains;
                        % Set Rx grid / ulschLLRs as data to the packet
                        packetOfInterest.Data = rxData;
                    end

                    % Send the packet to CPU
                    packetOfInterest.Metadata.NCellID = pre6GAP.getCPUCellID(obj.APCellID);
                    packetOfInterest.DirectToDestination = obj.CPUNodeID;
                    packetOfInterest.Metadata.DirectID = 0;
                    obj.SendPacketFcn(packetOfInterest);
                end
            end
        end

        function decodeSRS(obj, startTime, endTime, carrierConfigInfo)
            % Return SRS measurement for the UEs

            % Read all the relevant packets (i.e. either of interest or sent on same
            % carrier frequency) received in the time window
            rxWaveform = resultantWaveform(obj.RxBuffer, startTime, endTime);
            packetInfoList = packetList(obj.RxBuffer, startTime, endTime);

            for j=1:length(packetInfoList)
                packet = packetInfoList(j);
                if (packet.Metadata.PacketType == obj.SRSPacketType && ...
                        any(carrierConfigInfo.NCellID == packet.Metadata.NCellID))
                    if strcmp(obj.Split, "Centralized") || strcmp(obj.Split, "7.2x")
                        % Apply Rx Gain and Thermal Noise to Rx Waveform
                        rxWaveform = applyRxGain(obj, rxWaveform);
                        rxWaveform = applyThermalNoise(obj, rxWaveform);
                        % Scale Path Gains
                        pathGains = packet.Metadata.Channel.PathGains * db2mag(packet.Power-30) * db2mag(obj.ReceiveGain);
                        % Update the packet
                        packet.Metadata.Channel.PathGains = pathGains;
                        packet.Data = rxWaveform;
                    else % Distributed
                        % Process the SRS to get channel estimates and set
                        % them as packet data
                        packet.Data = srsRxProcessing(obj, rxWaveform, packet);
                    end
                    % Send the packet to CPU
                    packet.Metadata.NCellID = pre6GAP.getCPUCellID(obj.APCellID);
                    packet.DirectToDestination = obj.CPUNodeID;
                    packet.Metadata.DirectID = 0;
                    obj.SendPacketFcn(packet);
                end
            end
        end
    end

    methods(Access=protected, Hidden)
        function txGrid = populatePDSCH(obj, pdschInfo, cpuPDU)
            %populatePDSCH Populate PDSCH symbols in the Tx grid for
            % 7.2x or Distributed Split

            if strcmp(obj.Split, "Distributed")
                % Calculate PDSCH indices
                obj.CarrierConfig.NSlot = pdschInfo.NSlot;
                [pdschIndices, ~] = nrPDSCHIndices(obj.CarrierConfig, pdschInfo.PDSCHConfig);

                % PDSCH Scrambling, Modulation and Layer Mapping
                pdschSymbols = nrPDSCH(obj.CarrierConfig, pdschInfo.PDSCHConfig, cpuPDU);

                % Calculate DMRS Symbols and Indices
                dmrsIndices = nrPDSCHDMRSIndices(obj.CarrierConfig, pdschInfo.PDSCHConfig);
                dmrsSymbols = nrPDSCHDMRS(obj.CarrierConfig, pdschInfo.PDSCHConfig);

            else % 7.2x Split
                symbolArray = cpuPDU{1};
                indicesArray = cpuPDU{2};

                % Extract PDSCH indices and symbols form the CPU Packet
                pdschIndices = find(indicesArray == 1);
                pdschSymbols = symbolArray(pdschIndices);

                % Extract DMRS indices and symbols form the CPU Packet
                dmrsIndices = find(indicesArray == 2);
                dmrsSymbols = symbolArray(dmrsIndices);
            end

            % Initialize Tx grid
            txGrid = zeros(obj.CarrierInformation.NumResourceBlocks*12, obj.WaveformInfo.SymbolsPerSlot, obj.NumTransmitAntennas);

            W = pdschInfo.PrecodingMatrix;
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
        end

        function rxData = puschRxProcessing(obj, rxWaveform, puschInfo, packetInfo, carrierConfigInfo, numSampleChannelDelay)
            % Decode PUSCH out of Rx waveform

            rxWaveform = applyRxGain(obj, rxWaveform);
            rxWaveform = applyThermalNoise(obj, rxWaveform);
            pathGains = packetInfo.Metadata.Channel.PathGains * db2mag(packetInfo.Power-30) * db2mag(obj.ReceiveGain);

            % Initialize slot-length waveform
            [startSampleIdx, endSampleIdx] = sampleIndices(obj, puschInfo.NSlot, 0, carrierConfigInfo.SymbolsPerSlot-1);
            slotWaveform = zeros((endSampleIdx-startSampleIdx+1)+numSampleChannelDelay, obj.NumReceiveAntennas);

            % Populate the received waveform at appropriate indices in the slot-length waveform
            startSym = puschInfo.PUSCHConfig.SymbolAllocation(1);
            endSym = startSym+puschInfo.PUSCHConfig.SymbolAllocation(2)-1;
            [startSampleIdx, ~] = sampleIndices(obj, puschInfo.NSlot, startSym, endSym);
            slotWaveform(startSampleIdx : startSampleIdx+length(rxWaveform)-1, :) = rxWaveform;

            % Perfect timing estimation
            offset = nrPerfectTimingEstimate(pathGains, packetInfo.Metadata.Channel.PathFilters.');

            % Perform OFDM demodulation on the received data to recreate the
            % resource grid, including padding in the event that practical
            % synchronization results in an incomplete slot being demodulated
            slotWaveform = slotWaveform(1+offset:end, :);
            rxGrid = nrOFDMDemodulate(carrierConfigInfo, slotWaveform);

            rxData = rxGrid;

            if strcmp(obj.Split, "Distributed")
                % Perfect channel estimation
                estChannelGrid = nrPerfectChannelEstimate(pathGains,packetInfo.Metadata.Channel.PathFilters.', ...
                    carrierConfigInfo.NSizeGrid,carrierConfigInfo.SubcarrierSpacing,carrierConfigInfo.NSlot,offset, ...
                    packetInfo.Metadata.Channel.SampleTimes);

                % Apply MIMO deprecoding to estChannelGrid to give an estimate
                % per transmission layer
                F = eye(puschInfo.PUSCHConfig.NumAntennaPorts, packetInfo.NumTransmitAntennas);
                K = size(estChannelGrid,1);
                estChannelGrid = reshape(estChannelGrid,K*carrierConfigInfo.SymbolsPerSlot*obj.NumReceiveAntennas,packetInfo.NumTransmitAntennas);
                estChannelGrid = estChannelGrid * F.';
                estChannelGrid = estChannelGrid * packetInfo.Metadata.PrecodingMatrix.';
                estChannelGrid = reshape(estChannelGrid,K,carrierConfigInfo.SymbolsPerSlot,obj.NumReceiveAntennas,[]);

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

                rxData = ulschLLRs;
            end
        end

        function estChannelGrid = srsRxProcessing(obj, ~, packet)
            % Estimate local channel grid using Rx waveform for Distributed
            % Split

            % Apply receive gain
            pathGains = packet.Metadata.Channel.PathGains * db2mag(packet.Power-30) * db2mag(obj.ReceiveGain);

            % Perfect channel estimation
            offset = nrPerfectTimingEstimate(pathGains, packet.Metadata.Channel.PathFilters.');
            estChannelGrid = nrPerfectChannelEstimate(pathGains,packet.Metadata.Channel.PathFilters.', ...
                obj.CarrierConfig.NSizeGrid,obj.CarrierConfig.SubcarrierSpacing,obj.CarrierConfig.NSlot,offset, ...
                packet.Metadata.Channel.SampleTimes);
        end
    
        function nextInvokeTime = getNextInvokeTime(obj)
            %getNextInvokeTime Return the next invoke time in nanoseconds

            % Next Rx start symbol
            nextRxTime = min(obj.NextRxTime);

            % Next control reception time
            controlRxStartTime = min(obj.SRSRxInfo(:, 2));

            nextInvokeTime = min([nextRxTime controlRxStartTime]);
        end

        function [txPkts, rxPkts, controlPktsDL, controlPktsUL] = segregatePackets(~, packets)
            %segregatePackets Segregate different kind of packets form the
            % receieved buffer.

            txPkts = []; rxPkts = []; controlPktsDL = []; controlPktsUL = [];
            for i = 1:numel(packets)
                packetInfo = packets(i);
                if strcmp(packetInfo.Metadata.LastTransmitterType, 'CPU')
                    if packetInfo.Metadata.DirectID == 0
                        txPkts = [txPkts; packetInfo];
                    else
                        controlPktsDL = [controlPktsDL; packetInfo];
                    end
                else % From UE
                    if packetInfo.DirectToDestination ~= 0
                        controlPktsUL = [controlPktsUL; packetInfo];
                    else
                        rxPkts = [rxPkts; packetInfo];
                    end
                end
            end

        end

        function waveformOut = applyRxGain(obj, waveformIn)
            %applyRxGain Apply receiver antenna gain

            scale = 10.^(obj.ReceiveGain/20);
            waveformOut = waveformIn.* scale;
        end

        function waveformOut = applyThermalNoise(obj, waveformIn)
            %applyThermalNoise Apply thermal noise

            noiseFigure = 10^(obj.NoiseFigure/10);
            % Thermal noise (in Watts)
            Nt = physconst('Boltzmann') * (obj.AntNoiseTemperature + 290*(noiseFigure-1)) * obj.WaveformInfo.SampleRate;
            noise = sqrt(Nt/2)*complex(randn(size(waveformIn)),randn(size(waveformIn)));
            waveformOut = waveformIn + noise;
        end
    end
end