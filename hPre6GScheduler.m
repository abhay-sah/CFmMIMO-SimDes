classdef hPre6GScheduler < nrScheduler
    %hPre6GScheduler Inherits scheduler functionality

    methods
        function obj = hPre6GScheduler()
            % Invoke the super class constructor to initialize the properties
            obj = obj@nrScheduler();
        end

        function addConnectionContext(obj, connectionConfig)
            %addConnectionContext Configures the scheduler with UE connection information

            % Call base class constructor
            addConnectionContext@nrScheduler(obj, connectionConfig);
            
            cellConfig = obj.CellConfig;
            % Add additional connection configuration required to maintain in UE context
            additionalConnectionConfig = ["NumHARQ", "PUSCHPreparationTime", "PUSCHDMRSConfigurationType", "PUSCHDMRSLength", ...
                "PUSCHDMRSAdditionalPosTypeA", "PUSCHDMRSAdditionalPosTypeB", "PDSCHDMRSConfigurationType", "PDSCHDMRSLength", ...
                "PDSCHDMRSAdditionalPosTypeA", "PDSCHDMRSAdditionalPosTypeB", "RBGSizeConfig"];
            for idx=1:numel(additionalConnectionConfig)
                connectionConfig.(additionalConnectionConfig(idx)) = obj.(additionalConnectionConfig(idx));
            end
            % Update the Num Transmit Antennas GNB for a UE
            connectionConfig.NumTransmitAntennasGNB = connectionConfig.NumTransmitAntennasForUE;

            % Initialize and append UE context object
            ueContext = nr5g.internal.nrUEContext(connectionConfig, cellConfig, obj.SchedulerConfig);
            obj.UEContext(connectionConfig.RNTI) = ueContext;
        end

        function updateConnectionContext(obj, connectionConfig)
             % Add additional connection configuration required to maintain in UE context
            additionalConnectionConfig = ["NumHARQ", "PUSCHPreparationTime", "PUSCHDMRSConfigurationType", "PUSCHDMRSLength", ...
                "PUSCHDMRSAdditionalPosTypeA", "PUSCHDMRSAdditionalPosTypeB", "PDSCHDMRSConfigurationType", "PDSCHDMRSLength", ...
                "PDSCHDMRSAdditionalPosTypeA", "PDSCHDMRSAdditionalPosTypeB", "RBGSizeConfig"];
            for idx=1:numel(additionalConnectionConfig)
                connectionConfig.(additionalConnectionConfig(idx)) = obj.(additionalConnectionConfig(idx));
            end
            % Update the Num Transmit Antennas GNB for a UE
            connectionConfig.NumTransmitAntennasGNB = connectionConfig.NumTransmitAntennasForUE;

            % Initialize and update UE context object
            ueContext = nr5g.internal.nrUEContext(connectionConfig, obj.CellConfig, obj.SchedulerConfig);
            obj.UEContext(connectionConfig.RNTI) = ueContext;
        end
    end
end