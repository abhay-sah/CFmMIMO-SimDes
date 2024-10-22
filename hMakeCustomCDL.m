%hMakeCustomCDL make CDL with Custom DelayProfile from preset CDL channel
%   CUSTOMCDL = hMakeCustomCDL(PRESETCDL) creates a copy of the input
%   nrCDLChannel object PRESETCDL and returns an equivalent CDL channel
%   object with 'Custom' DelayProfile CUSTOMCDL.

% Copyright 2022 The MathWorks, Inc.

function out = hMakeCustomCDL(cdl)

    % Clone the input channel and reconfigure it for custom delay profile
    out = clone(cdl);
    out.DelayProfile = 'Custom';

    % Get info from input channel
    cdlinfo = info(cdl);

    % Populate the delay profile from the info
    fields = ["PathDelays" "AveragePathGains" "AnglesAoD" "AnglesAoA" "AnglesZoD" "AnglesZoA"];
    for f = fields
        out.(f) = cdlinfo.(f);
    end

    % Configure LOS cluster if required
    out.HasLOSCluster = ~isinf(cdlinfo.KFactorFirstCluster);
    if (out.HasLOSCluster)

        % Configure K factor
        out.KFactorFirstCluster = cdlinfo.KFactorFirstCluster;

        % For LOS channels, the first cluster is split into LOS and NLOS
        % parts in the info, so combine these parts into a single cluster
        p = out.AveragePathGains(1:2);
        out.AveragePathGains(2) = 10*log10(sum(10.^(p/10)));
        for f = fields
            out.(f)(1) = [];
        end

    end

    % Configure AngleSpreads and XPR
    if ~strcmpi(cdl.DelayProfile,'Custom')
        clusterParams = wireless.internal.channelmodels.getCDLPerClusterParameters(cdl.DelayProfile);
        cellParams = struct2cell(clusterParams);
        out.AngleSpreads = [cellParams{1:4}];
        out.XPR = cellParams{5};
    end

end