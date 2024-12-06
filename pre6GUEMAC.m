classdef pre6GUEMAC < nr5g.internal.nrUEMAC

    methods
        function obj = pre6GUEMAC(notificationFcn)
              obj = obj@nr5g.internal.nrUEMAC(notificationFcn); % Call base class constructor
        end

        function addConnection(obj, connectionInfo)
            %addConnection Adds CPU connection context to the UE MAC

            % Call addConnection from base class
            addConnection@nr5g.internal.nrUEMAC(obj, connectionInfo);
    
            cpuCellID = pre6GAP.getCPUCellID(connectionInfo.NCellID);
            obj.PDSCHInfo.PDSCHConfig.NID = cpuCellID;
            obj.PUSCHInfo.PUSCHConfig.NID = cpuCellID;
        end
    end
end