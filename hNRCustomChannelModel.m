classdef hNRCustomChannelModel
    %hNRCustomChannelModel Create a custom channel model as an array of link-level CDL channels

    %   Copyright 2022-2023 The MathWorks, Inc.

    properties (SetAccess=private)
        %PHYAbstractionMethod Physical layer abstraction method as "linkToSystemMapping" or "none"
        PHYAbstractionMethod = "linkToSystemMapping"

        %PathlossMethod Pathloss type as "fspl" or "nrPathLoss"
        PathlossMethod = "fspl"

        %NRPathLossConfig NR path loss configuration as an object of type nrPathLossConfig
        % This property is only meaningful when property 'PathlossMethod' is set to value "nrPathLoss"
        NRPathLossConfig

        %ChannelModelMatrix Matrix of channel models for the links
        ChannelModelMatrix

        %MaxChannelDelayMatrix Matrix of maximum channel delay for the links
        MaxChannelDelayMatrix

        %PathFilter Matrix of path filters for the links
        PathFilter

        %Los Binary matrix to store if line-of-sight (LOS) exists between transmitter and receiver
        Los
    end

    properties(Access=private)
        %PHYAbstractionMethodNum Representation of PHYAbstractionMethod as a number (To speed up runtime check of PHY flavor)
        % Values 1 and 0 represent that PHYAbstractionMethod is set to
        % "linkToSystemMapping" and "none", respectively.
        PHYAbstractionMethodNum
    end

    methods
        % Constructor
        function obj = hNRCustomChannelModel(channelModelMatrix, varargin)
             % OBJ = hNRCustomChannelModel(CHANNELMODELMATRIX) creates a default
             % channel model. The default mode works with physical layer (PHY)
             % abstraction and assumes free-space-path-loss as pathloss type.
             %
             % CHANNELMODELMATRIX is a N-by-N array of link-level channels where N is
             % the number nodes
             %   
             % OBJ = hNRCustomChannelModel(CHANNELMODELMATRIX, CHANNELCONFIGURATION)
             % creates a channel model where you can specify the PHY flavor and pathloss
             % type. CHANNELCONFIGURATION is a structure which can contain these fields.
             % PHYAbstractionMethod - PHY abstraction method used. Value as
             %                        "linkToSystemMapping" (for abstract
             %                        PHY) or "none" (for full PHY). The default value
             %                        is "linkToSystemMapping".
             % PathlossMethod       - Pathloss method used. Value as "fspl" or
             %                       "nrPathloss". The default value
             %                        is "fspl".

            if nargin > 1
                % Set PHY abstraction and pathloss type
                param = varargin{1};
                if isfield(param, 'PHYAbstractionMethod')
                    obj.PHYAbstractionMethod = param.PHYAbstractionMethod;
                end
                if isfield(param, 'PathlossMethod')
                    obj.PathlossMethod = param.PathlossMethod;
                end
                if strcmp(obj.PathlossMethod, "nrPathloss")
                    obj.NRPathLossConfig = nrPathLossConfig;
                    % Set the configuration as per urban macro scenario. See <a
                    % href="matlab:help('nrPathLossConfig')">nrPathLossConfig</a> for
                    % customizing the configuration
                    obj.NRPathLossConfig.Scenario = 'UMa';  % Urban macrocell
                    obj.NRPathLossConfig.EnvironmentHeight = 1; % Average height of the environment in UMa/UMi
                end
            end
            obj.PHYAbstractionMethodNum = ~strcmp(obj.PHYAbstractionMethod, "none");
            obj.ChannelModelMatrix = channelModelMatrix;
            obj.MaxChannelDelayMatrix = zeros(size(obj.ChannelModelMatrix));
            obj.Los = zeros(size(obj.ChannelModelMatrix));
            for i=1:size(obj.ChannelModelMatrix,1)
                for j=1:size(obj.ChannelModelMatrix,2)
                    if ~isempty(obj.ChannelModelMatrix{i,j})
                        chInfo = info(obj.ChannelModelMatrix{i,j});
                        obj.MaxChannelDelayMatrix(i,j) = ceil(max(chInfo.PathDelays*obj.ChannelModelMatrix{i,j}.SampleRate)) + chInfo.ChannelFilterDelay;
                        obj.PathFilter{i,j} = getPathFilters(obj.ChannelModelMatrix{i,j}).';
                        kFactor = chInfo.KFactorFirstCluster; % dB
                        % Determine LOS between Tx and Rx based on Rician factor, K
                        obj.Los(i,j) = kFactor>-Inf;
                    end
                end
            end
        end

        function outputData = applyChannelModel(obj, rxInfo, txData)
            %applyChannelModel Apply the channel model to the transmitted data

            outputData = txData;
            if strcmp(obj.PathlossMethod, "fspl") % Free space pathloss
                distance = norm(txData.TransmitterPosition - rxInfo.Position);
                lambda = physconst('LightSpeed')/txData.CenterFrequency; % Wavelength
                pathLoss = fspl(distance, lambda);
            else % NR pathloss
                pathLoss = nrPathLoss(obj.NRPathLossConfig,txData.CenterFrequency,obj.Los(txData.TransmitterID,rxInfo.ID), ...
                    txData.TransmitterPosition',rxInfo.Position');
            end
            outputData.Power = outputData.Power - pathLoss;
            if ~isempty(obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID})
                % There is channel model between the Tx and Rx node
                obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}.InitialTime = outputData.StartTime;
                if obj.PHYAbstractionMethodNum == 0 % Full PHY
                    rxWaveform = [txData.Data; zeros(obj.MaxChannelDelayMatrix(txData.TransmitterID, rxInfo.ID), ...
                        size(txData.Data,2))];
                    [outputData.Data,outputData.Metadata.Channel.PathGains, outputData.Metadata.Channel.SampleTimes] = ...
                        obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}(rxWaveform);
                    outputData.Data = outputData.Data.*db2mag(-pathLoss);
                    outputData.Duration = outputData.Duration + (1/outputData.SampleRate)*obj.MaxChannelDelayMatrix(txData.TransmitterID, rxInfo.ID);
                else % Abstract PHY
                    obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}.NumTimeSamples =  ...
                    txData.Metadata.NumSamples + obj.MaxChannelDelayMatrix(txData.TransmitterID, rxInfo.ID);
                    [outputData.Metadata.Channel.PathGains, outputData.Metadata.Channel.SampleTimes] = ...
                        obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}();
                end
                outputData.Metadata.Channel.PathFilters = ...
                    obj.PathFilter{txData.TransmitterID, rxInfo.ID};
            else
                % There is no channel model between the Tx and Rx node
                outputData.Metadata.Channel.PathGains = permute(ones(outputData.NumTransmitAntennas,rxInfo.NumReceiveAntennas),[3 4 1 2]) / sqrt(rxInfo.NumReceiveAntennas);
                outputData.Metadata.Channel.PathFilters = 1;
                outputData.Metadata.Channel.SampleTimes = 0;
                if obj.PHYAbstractionMethodNum == 0 % Full PHY
                    numTxAnts = outputData.NumTransmitAntennas;
                    numRxAnts = rxInfo.NumReceiveAntennas;
                    H = fft(eye(max([numTxAnts numRxAnts])));
                    H = H(1:numTxAnts,1:numRxAnts);
                    H = H / norm(H);
                    outputData.Data = txData.Data * H; % Apply channel on the waveform
                end
            end
        end
    end
end