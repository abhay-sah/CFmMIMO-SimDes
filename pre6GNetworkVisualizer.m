classdef pre6GNetworkVisualizer < helperNetworkVisualizer

    properties(Constant, Access=private)
        AllowedNodes = ["pre6GCPU", "pre6GAP", "pre6GUE"];
    end

    methods
        function obj = pre6GNetworkVisualizer(varargin)
            obj = obj@helperNetworkVisualizer(varargin{:});

            obj.NodeMarkerMap = struct.empty(3, 0);
            scale = 40 / numel(obj.NetworkSimulator.Nodes);
            scale = min([scale, 1]);
            scale = max([scale, 0.1]);

            imCPU = imread("pre6GCPU.png");
            for i=1:size(imCPU,1)
                for j=1:size(imCPU,2)
                    if all(imCPU(i,j,:) == 255)
                        imCPU(i,j,:) = obj.Axis.Color * 255;
                    end
                end
            end
            obj.NodeMarkerMap(1).Image = imCPU;
            obj.NodeMarkerMap(1).Size = scale * 125 * [1, size(imCPU,1) / size(imCPU, 2)];

            imAP = imread("pre6GAP.png");
            for i=1:size(imAP,1)
                for j=1:size(imAP,2)
                    if all(imAP(i,j,:) == 255)
                        imAP(i,j,:) = obj.Axis.Color * 255;
                    end
                end
            end
            obj.NodeMarkerMap(2).Image = imAP;
            obj.NodeMarkerMap(2).Size = scale * 40 * [1, size(imAP,1) / size(imAP,2)];

            imUE = imread("pre6GUE.png");
            for i=1:size(imUE,1)
                for j=1:size(imUE,2)
                    if all(imUE(i,j,:) == 255)
                        imUE(i,j,:) = obj.Axis.Color * 255;
                    end
                end
            end
            obj.NodeMarkerMap(3).Image = imUE;
            obj.NodeMarkerMap(3).Size = scale * 20 * [1, size(imUE,1) / size(imUE, 2)];
            % Turn off data tips
            obj.Axis.InteractionOptions.DatatipsSupported = "off";

            addNodes(obj, obj.NetworkSimulator.Nodes);
        end

        function addNodes(obj, nodes, varargin)
            import matlab.graphics.internal.themes.specifyThemePropertyMappings
            hold (obj.Axis,'on');

            if ~iscell(nodes)
                nodes = num2cell(nodes);
            end

            names = varargin(1:2:end);
            % Search the presence of 'Tag' N-V argument to
            % calculate the number of nodes user intends to plot
            tagIdx = find(strcmp([names{:}], 'Tag'), 1, 'last');
            if isempty(tagIdx)
                nodeTags = string(cellfun( @(x) x.ID, nodes, 'uni', 1));
            else
                nodeTags = varargin{2*tagIdx};
            end

            nodeCoordinates = cell(numel(nodeTags),1);
            for idx=1:numel(nodeTags)
                nodeCoordinates{idx} = nodes{idx}.Position;
                obj.Nodes{end+1} = nodes{idx};
                obj.Tags{end+1} = nodeTags(idx);
            end

            % Validate the tags
            if ~isempty(obj.Tags) && numel(unique(nodeTags)) ~= numel(nodeTags) ...
                    && ~isempty(intersect([obj.Tags{:}], nodeTags))
                error('Nodes IDs/tags must be unique')
            end

            % Scatter points to get axis ratio
            for idx = 1:numel(nodeTags)
                px = nodes{idx}.Position(1); % Node X-coordinate
                py = nodes{idx}.Position(2); % Node Y-coordinate
                scatter(obj.Axis, px, py, "red", "filled",".");
            end

            % Calculate the scaling values and axis ratio
            scalex = (obj.Axis.XLim(2) - obj.Axis.XLim(1)) / 1000;
            scaley = (obj.Axis.YLim(2) - obj.Axis.YLim(1)) / 1000;
            ar = scaley / scalex;

            % Plot nodes(s)
            for idx = 1:numel(nodeTags)
                px = nodes{idx}.Position(1); % Node X-coordinate
                py = nodes{idx}.Position(2); % Node Y-coordinate
                objectType = string(class(nodes{idx}));
                % Validate Node
                validatestring(objectType, obj.AllowedNodes, mfilename, "Object Type");

                markerIdx = find(objectType == obj.AllowedNodes);
                nodeMarkerInfo = obj.NodeMarkerMap(markerIdx);

                % UE - AP Connection Lines
                if strcmp(objectType, 'pre6GUE')
                    connectedAPIDs = nodes{idx}.ConnectedAPs;
                    nodeColor = [];
                    for i=1:numel(connectedAPIDs)
                        apx = nodes{connectedAPIDs(i)}.Position(1);
                        apy = nodes{connectedAPIDs(i)}.Position(2);
                        p = plot(obj.Axis, [px apx], [py apy], ':', LineWidth=1);
                        if isempty(nodeColor)
                            nodeColor = p.Color;
                        end
                        p.Color = [nodeColor, 0.7];
                    end
                    nodeColor = [];
                end

                marker = nodeMarkerInfo.Image;
                markersize = [nodeMarkerInfo.Size(1) * scalex, nodeMarkerInfo.Size(2) * scaley * ar];
                xlow = px - markersize(1)/2;
                xhigh = px + markersize(1)/2;
                ylow = py - markersize(2)/2;
                yhigh = py + markersize(2)/2;
                imagesc(obj.Axis, [xlow xhigh], [yhigh ylow], marker);

                % AP - CPU Connection Lines
                if strcmp(objectType, 'pre6GAP')
                    cpuNodeID = nodes{idx}.CPUNodeID;
                    cpux = nodes{cpuNodeID}.Position(1);
                    cpuy = nodes{cpuNodeID}.Position(2);
                    midx = (px - cpux) * 0.5;
                    midy = (py - cpuy) * 0.65;
                    x = [px, midx + cpux, cpux];
                    y = [py, midy + cpuy, cpuy];
                    xint = linspace(px, cpux, 50);
                    yint = interp1(x, y, xint, 'spline');
                    p = line(obj.Axis, xint, yint,LineWidth = 1);
                    specifyThemePropertyMappings(p,Color="--mw-borderColor-primary");
                    p.Color(4) = 0.2;
                end
            end

            hold (obj.Axis,'off');
        end
    end

    methods(Hidden)
        function init(obj,varargin)
            %init Initialize the network visualization
        end
    end
end