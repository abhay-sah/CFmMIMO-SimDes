classdef hPre6GUEMAC < nr5g.internal.nrUEMAC
    %hPre6GUEMAC Inherits UE MAC functionality
    methods
        function obj = hPre6GUEMAC(notificationFcn)
              obj = obj@nr5g.internal.nrUEMAC(notificationFcn); % Call base class constructor
        end

        function addConnection(obj, connectionInfo)
            %addConnection Adds CPU connection context to the UE MAC

            % Call addConnection from base class
            addConnection@nr5g.internal.nrUEMAC(obj, connectionInfo);
            
            % Get CPU cell ID
            cpuCellID = hPre6GAP.getCPUCellID(connectionInfo.NCellID);
            obj.PDSCHInfo.PDSCHConfig.NID = cpuCellID;
            obj.PUSCHInfo.PUSCHConfig.NID = cpuCellID;
        end
    end
end