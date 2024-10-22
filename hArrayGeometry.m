%hArrayGeometry antenna array geometry for CDL channel model

%   Copyright 2018-2022 The MathWorks, Inc.

function cdl = hArrayGeometry(cdl,NTxAnts,NRxAnts,varargin)

    if (nargin==3)
        linkDirection = 'downlink';
    else
        linkDirection = varargin{1};
    end

    if (strcmpi(linkDirection,'downlink'))
        txArray = bsArrayGeometry(cdl.TransmitAntennaArray,NTxAnts);
        rxArray = ueArrayGeometry(cdl.ReceiveAntennaArray,NRxAnts);
    else % uplink
        txArray = ueArrayGeometry(cdl.TransmitAntennaArray,NTxAnts);
        rxArray = bsArrayGeometry(cdl.ReceiveAntennaArray,NRxAnts);
    end

    % Update CDL channel arrays configuration
    cdl.TransmitAntennaArray = txArray;
    cdl.ReceiveAntennaArray = rxArray;

    warnIfArraySizeChanged(cdl,NTxAnts,NRxAnts,linkDirection)

end

function array = bsArrayGeometry(array,nBsAnts)

    % Setup the base station antenna geometry
    % Table of antenna panel array configurations
    % M:  no. of rows in each antenna panel
    % N:  no. of columns in each antenna panel
    % P:  no. of polarizations (1 or 2)
    % Mg: no. of rows in the array of panels
    % Ng: no. of columns in the array of panels
    % Row format: [M  N   P   Mg  Ng]
    antArraySizes = ...
       [1   1   1   1   1;   % 1 ants
        1   1   2   1   1;   % 2 ants
        2   1   2   1   1;   % 4 ants
        2   2   2   1   1;   % 8 ants
        2   4   2   1   1;   % 16 ants
        4   4   2   1   1;   % 32 ants
        4   4   2   1   2;   % 64 ants
        4   8   2   1   2;   % 128 ants
        4   8   2   2   2;   % 256 ants
        8   8   2   2   2;   % 512 ants
        8  16   2   2   2];  % 1024 ants
    antselected = min(1+ceil(log2(nBsAnts)),size(antArraySizes,1));
    array.Size = antArraySizes(antselected,:);

    % Adjust element spacing to avoid panel overlaps
    array.ElementSpacing(3) = array.Size(1)*array.ElementSpacing(1);
    array.ElementSpacing(4) = array.Size(2)*array.ElementSpacing(2);

end

function array = ueArrayGeometry(array,nUeAnts)

    % Setup the UE antenna geometry
    if nUeAnts == 1
        % In the following settings, the number of rows in antenna array, 
        % columns in antenna array, polarizations, row array panels and the
        % columns array panels are all 1
        arraySize = ones(1,5);
    else
        % In the following settings, the no. of rows in antenna array is
        % nUeAnts/2, the no. of columns in antenna array is 1, the no.
        % of polarizations is 2, the no. of row array panels is 1 and the
        % no. of column array panels is 1. The values can be changed to
        % create alternative antenna setups
        arraySize = [ceil(nUeAnts/2),1,2,1,1];
    end
    array.Size = arraySize;
    
end

function warnIfArraySizeChanged(channel,NTxAnts,NRxAnts,linkDirection)

    NTxAntsChannel = prod(channel.TransmitAntennaArray.Size);
    NRxAntsChannel = prod(channel.ReceiveAntennaArray.Size);

    side = ["transmit" "receive"];
    if ~strcmpi(linkDirection,'Downlink')
        side = fliplr(side);
    end

    if NTxAntsChannel ~= NTxAnts
        str = 'The number of BS %s antenna elements configured (%d) is not one of the set (1,2,4,8,16,32,64,128,256,512,1024). Using %d instead.';
        warning('nr5g:hArrayGeometry:numAnts',str,side(1),NTxAnts,NTxAntsChannel);
    end
    
    if NRxAntsChannel ~= NRxAnts
        str = 'The number of UE %s antenna elements configured (%d) is not even. Using %d instead.';
        warning('nr5g:hArrayGeometry:numAnts',str,side(2),NRxAnts,NRxAntsChannel);
    end

end