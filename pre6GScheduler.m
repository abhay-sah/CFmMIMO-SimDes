classdef pre6GScheduler < nrScheduler
    %pre6GScheduler 

    methods
        function obj = pre6GScheduler()
            % Invoke the super class constructor to initialize the properties
            obj = obj@nrScheduler();
        end

        function addConnectionContext(obj, connectionConfig)
            %addConnectionContext Configures the scheduler with UE connection information

            % Call base class constructor
            addConnectionContext@nrScheduler(obj, connectionConfig);

            % Only Supports SRS based DL CSI
            schedulerParam = ["ResourceAllocationType", "MaxNumUsersPerTTI", "PFSWindowSize", "FixedMCSIndexDL", "FixedMCSIndexUL", ...
                "MUMIMOConfigDL", "LinkAdaptationConfigDL", "LinkAdaptationConfigUL", "RVSequence", "CSIMeasurementSignalDLType"];
            for i=1:numel(schedulerParam)
                schedulerInfo.(schedulerParam(i)) = obj.SchedulerConfig.(schedulerParam(i));
            end
            schedulerInfo.CSIMeasurementSignalDLType = 1;
            obj.SchedulerConfig = nr5g.internal.nrSchedulerConfig(schedulerInfo);

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

    methods(Access=protected, Hidden)
        function [rank, W] = selectRankAndPrecodingMatrixDL(obj, rnti, csiMeasurement, numCSIRSPorts)
            % %selectRankAndPrecodingMatrixDL Select rank and precoding matrix based on the channel measurements using CSI-RS or SRS
            %   [RANK, W] = selectRankAndPrecodingMatrixDL(OBJ, RNTI,
            %   CSIREPORT, SRSREPORT, NUMCSIRSPORTS) selects the rank and precoding
            %   matrix for a UE.
            %
            %   RNTI is the RNTI of the connected UE
            %
            %   CSIMEASUREMENT Wideband DL channel measurement, as reported by the UE node based
            %   on CSI-RS reception, and the wideband DL channel measurement extracted by the
            %   gNB from the SRS, specified as a structure with these fields.
            %       CSIRS — A structure with these fields:
            %           RI — Rank indicator
            %           PMISet — Precoder matrix indications (PMI) set
            %           CQI — Channel quality indicator
            %           W — Precoding matrix
            %
            %       SRS — A structure with these fields:
            %           RI — Rank indicator
            %           W — Precoding matrix
            %           MCSIndex — Modulation and coding scheme index
            %
            %   RANK is the selected rank i.e. the number of transmission
            %   layers
            %
            %   NUMCSIRSPORTS is number of CSI-RS ports for the UE
            %
            %   W is an array of size RANK-by-P-by-NPRG, where NPRG is the
            %   number of PRGs in the carrier and P is the number of CSI-RS
            %   ports. W defines a different precoding matrix of size
            %   RANK-by-P for each PRG. The effective PRG bundle size
            %   (precoder granularity) is Pd_BWP = ceil(NRB / NPRG). Valid
            %   PRG bundle sizes are given in TS 38.214 Section 5.1.2.3, and
            %   the corresponding values of NPRG, are as follows:
            %   Pd_BWP = 2 (NPRG = ceil(NRB / 2))
            %   Pd_BWP = 4 (NPRG = ceil(NRB / 4))
            %   Pd_BWP = 'wideband' (NPRG = 1)
            %
            % Rank selection procedure followed: Select the advised rank in the CSI report
            % Precoder selection procedure followed: Form the combined precoding matrix for
            % all the PRGs in accordance with the CSI report.
            %
            % The function can be modified to return rank and precoding
            % matrix of choice.

            if obj.SchedulerConfig.CSIMeasurementSignalDLType
                report = csiMeasurement.SRS;
                if isempty(report)
                    report.W = csiMeasurement.CSIRS.W;
                    report.RI = csiMeasurement.CSIRS.RI;
                end
            else
                report = csiMeasurement.CSIRS;
            end
            W = report.W;
            rank = report.RI;
            if numCSIRSPorts == 1 || isempty(report.W)
                % Single antenna port or no PMI report received
                W = 1;
            else
                numPRGs =  ceil(obj.CellConfig.NumResourceBlocks/obj.UEContext(rnti).PrecodingGranularity);
                if ~obj.SchedulerConfig.CSIMeasurementSignalDLType || ndims(W) ~= 3 && size(W,1) ~= rank
                    W = complex(zeros(rank, size(W,1), numPRGs,1));
                    for i=1:numPRGs
                        W(:,:,i) = report.W.';
                    end
                end
            end
        end
    end
end