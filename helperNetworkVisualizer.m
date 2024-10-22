classdef helperNetworkVisualizer < handle
    %helperNetworkVisualizer Show the network visualization
    %   VISOBJ = helperNetworkVisualizer creates a network visualization object.
    %
    %   VISOBJ = helperNetworkVisualizer(Name=Value) creates a network
    %   visualization object, VISOBJ, with the specified property Name set to
    %   the specified Value. You can specify additional name-value arguments in
    %   any order as (Name1=Value1, ...,NameN=ValueN)
    %
    %   helperNetworkVisualizer properties (configurable through N-V pair only):
    %
    %   Axis        - Axis of the figure object on which network should be visualized
    %   SampleRate  - Mobility refresh rate in terms of Hz
    %
    %   helperNetworkVisualizer methods:
    %
    %   showBoundaries               - Display the boundaries as circles
    %   showInfrastructureGridLayout - Display the infrastructure grid
    %   addNodes                     - Add nodes to network visualization

    %   Copyright 2023 The MathWorks, Inc.

    properties (SetAccess=private)
        %Axis Axis of the figure object on which network should be visualized
        Axis

        %SampleRate Mobility refresh rate in terms of Hz
        SampleRate 
    end

    properties (Hidden)
        %Nodes List of nodes in the network
        Nodes

        %Tags Tags of the nodes
        Tags

        %NetworkSimulator Custom network simulator
        NetworkSimulator

        %ShowDatatip Flag to control whether to show the data tips or not
        ShowDatatip = true;

        %MarkerColor Color codes for the markers
        MarkerColor = ["--mw-graphics-colorOrder-2-primary" "--mw-borderColor-primary" "--mw-color-teal600" "--mw-color-brown800"]

        %Markers Markers to represent the nodes
        Markers= ["^" "o" "square" "hexagram" "pentagram" "diamond" "|"];

        %NodeMarkerMap Map to track the marker type and its color for nodes
        NodeMarkerMap
    end

    properties(Access=private)
        %ColorIndex Tracks the currently used colors
        ColorIndex = 0;

        %MarkerIndex Tracks the currently used markers
        MarkerIndex = 0

        %Legend Holds the legend information for the visualization
        Legend = cell(0,2);

        %NumVisualizationUpdate Number of times visualization updates
        NumVisualizationUpdate = 10;
    end

    methods
        function obj = helperNetworkVisualizer(varargin)

            % Name-value pair check
            coder.internal.errorIf(mod(nargin, 2) == 1,'MATLAB:system:invalidPVPairs');

            % Assign the values to parameters
            for idx = 1:2:length(varargin)
                obj.(char(varargin{idx})) = varargin{idx+1};
            end
            obj.Nodes = [];
            obj.Tags = [];
            obj.NodeMarkerMap = containers.Map();
            if isempty(obj.Axis)
                % Using the screen width and height, calculate the figure width and height
                resolution = get(0, 'ScreenSize');
                screenWidth = resolution(3);
                screenHeight = resolution(4);
                figureWidth = screenWidth * 0.75;
                figureHeight = screenHeight * 0.75;
                fig = uifigure(Name="Network Layout Visualization", ...
                    Position=[screenWidth * 0.05 screenHeight * 0.05 figureWidth figureHeight]);
                % Use desktop theme to support dark theme mode
                matlab.graphics.internal.themes.figureUseDesktopTheme(fig);
                g = uigridlayout(fig, [1 1]);
                obj.Axis = uiaxes(Parent=g);
            end
            obj.Axis.XLimMode = 'auto';
            obj.Axis.YLimMode = 'auto';
            obj.Axis.XLabel.String = "X-axis (Meters)";
            obj.Axis.YLabel.String = "Y-axis (Meters)";

            if isempty(obj.NetworkSimulator)
                obj.NetworkSimulator = wirelessNetworkSimulator.getInstance();
            end
            drawnow;
            scheduleAction(obj.NetworkSimulator, @obj.init, [], 0);
        end

        function showInfrastructureGridLayout(obj, bsCoordinates, interSiteDistance)
            %showInfrastructureGridLayout Displays the infrastructure grid
            %
            %   showInfrastructureGridLayout (OBJ, BSCOORDINATES, INTERSITEDISTANCE)
            %   Displays an infrastructure grid layout
            %
            %   BSCOORDINATES     - 3D Cartesian coordinates of base station (BS)
            %   INTERSITEDISTANCE - Distance between two adjacent BSs (in meters)

            if ~isvalid(obj.Axis)
                return;
            end

            narginchk(3, 3);
            numBS = size(bsCoordinates,1);
            ax = obj.Axis;
            colors = ["--mw-graphics-colorOrder-2-primary", "--mw-color-selected-noFocus"];
            import matlab.graphics.internal.themes.specifyThemePropertyMappings
            ax.DataAspectRatio = [1 1 1];
            hold (ax,'on');

            cellSide = interSiteDistance/sqrt(3);
            % Vertices of the polygon that forms the boundary of a cell
            vx = cellSide*cosd(0:60:360); % x coordinates
            vy = cellSide*sind(0:60:360); % y coordinates

            % Plot the network layout
            for j = 1:numBS
                % Calculate vertices of hexagonal cell
                verticesXCoordinates = bsCoordinates(j,1)+vx;
                verticesYCoordinates = bsCoordinates(j,2)+vy;

                % Plot cell-site
                cellBoundary = plot(ax,verticesXCoordinates,verticesYCoordinates,Tag="Cell"+(j));
                specifyThemePropertyMappings(cellBoundary,Color=colors(2));
            end

            hold (ax,'off');
        end

        function showBoundaries(obj, bsCoordinates, cellRadius, varargin)
            %showBoundaries Show the boundaries as circles
            %
            %   showBoundaries(BSCOORDINATES, CELLRADIUS) Show the boundaries as
            %   circles.
            %
            %   showBoundaries(BSCOORDINATES, CELLRADIUS, CELLOFINTEREST) Show the
            %   boundaries as circles and highlights the cell which has the
            %   CELLOFINTEREST as cell ID.
            %
            %   BSCOORDINATES  - 3D Cartesian coordinates of base station (BS)
            %   CELLRADIUS     - Radius of each cell (in meters)
            %   CELLOFINTEREST - Cell of interest in the given scenario.

            if ~isvalid(obj.Axis)
                return;
            end
            narginchk(3,4);
            numBS = size(bsCoordinates,1);
            ax = obj.Axis;
            % Get the cell of interest index
            cellOfInterest = [];
            if ~isempty(varargin)
                if ~isscalar(varargin) || varargin{1} > numBS
                    return;
                else
                    cellOfInterest = varargin{1};
                end
            end

            import matlab.graphics.internal.themes.specifyThemePropertyMappings
            ax.DataAspectRatio = [1 1 1];
            hold (ax,'on');

            isLegendAdded = false;
            % Plot the network
            for i = 1:numBS
                bx = bsCoordinates(i,1); % BS X-coordinate
                by = bsCoordinates(i,2); % BS Y-coordinate
                % Plot the circle representing each cell
                th = 0:pi/60:2*pi;
                x = cellRadius*cos(th)+bx;
                y = cellRadius*sin(th)+by;
                cellBoundary = plot(ax,x,y,Tag="Cell"+(i));
                if i == cellOfInterest
                    specifyThemePropertyMappings(cellBoundary,Color="--mw-graphics-colorOrder-5-primary");
                    numItems = size(obj.Legend, 1)+1;
                    obj.Legend{numItems,1} = cellBoundary;
                    obj.Legend{numItems,2} = "Cell of interest";
                else
                    specifyThemePropertyMappings(cellBoundary,Color="--mw-color-selected-noFocus");
                    if ~isLegendAdded
                        isLegendAdded = true;
                        numItems = size(obj.Legend, 1)+1;
                        obj.Legend{numItems,1} = cellBoundary;
                        obj.Legend{numItems,2} = "Interfering cells";
                    end
                end
            end
            hold (ax,'off');
        end

        function addNodes(obj, nodes, varargin)
            %addNodes Add the nodes on the network visualization
            %
            %   addNodes(OBJ, NODES) adds the specified wireless nodes, NODES, to the
            %   helperNetworkVisualizer object, OBJ. You must add the nodes to the
            %   simulator before running the simulation. Specify NODES as one of these
            %   options.
            %       - A vector of objects of type bluetoothLENode object, bluetoothNode
            %       object, wlanNode object, nrGNB object, nrUE object, hTDMANode object 
            %       or any other wirelessnode object.
            %       - A cell array, where each cell can contain a bluetoothLENode
            %       object, bluetoothNode object, wlanNode object, nrGNB object, nrUE
            %       object, hTDMANode object or any other wirelessnode object.
            %
            %   addNodes(OBJ, ..., Name=Value) adds the specified wireless
            %   nodes to the network using parameters specified in name-value
            %   arguments.
            %   Tag - Tag values corresponding to the nodes.

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

            % Plot nodes(s)
            for idx = 1:numel(nodeTags)
                px = nodes{idx}.Position(1); % Node X-coordinate
                py = nodes{idx}.Position(2); % Node Y-coordinate
                objectType = string(class(nodes{idx}));
                newType = 0;
                % Find the marker and its color for the new node type
                if ~obj.NodeMarkerMap.isKey(objectType)
                    numMarkers = numel(obj.Markers);
                    numColors = numel(obj.MarkerColor);
                    obj.MarkerIndex = mod(obj.MarkerIndex, numMarkers)+1;
                    obj.ColorIndex = mod(obj.ColorIndex, numColors)+1;
                    obj.NodeMarkerMap(objectType) = [obj.MarkerIndex obj.ColorIndex];
                    newType = 1;
                    if obj.NodeMarkerMap.Count > numMarkers*numColors
                        error("Visualization supports a maximum of '%d' node types", numMarkers*numColors);
                    end
                end

                nodeMarkerInfo = obj.NodeMarkerMap(objectType);
                node = scatter(obj.Axis,px,py,Marker=obj.Markers{nodeMarkerInfo(1)},LineWidth=4,Tag=nodeTags(idx));
                if obj.ShowDatatip
                    cellIdRow = dataTipTextRow("", nodes{idx}.Name);
                    posRow = dataTipTextRow('Position[X, Y]: ',{sprintf('%.6f, %.6f',px,py)});
                    node.DataTipTemplate.DataTipRows = [cellIdRow posRow];
                end
                % Track the new node types
                if newType
                    numItems = size(obj.Legend, 1)+1;
                    obj.Legend{numItems,1} = node;
                    obj.Legend{numItems,2} = objectType;
                end
                % Specify the node color mapping for the current theme
                specifyThemePropertyMappings(node,MarkerFaceColor=obj.MarkerColor{nodeMarkerInfo(2)});
                specifyThemePropertyMappings(node,MarkerEdgeColor=obj.MarkerColor{nodeMarkerInfo(2)});
            end

            legend([obj.Legend{:,1}], [obj.Legend{:,2}], 'AutoUpdate','off');
            hold (obj.Axis,'off');
        end
    end

    methods(Hidden)
        function init(obj,varargin)
            %init Initialize the network visualization
            
            if isempty(obj.Nodes)
                addNodes(obj, obj.NetworkSimulator.Nodes);
            end

            if isempty(obj.SampleRate)
                obj.SampleRate = obj.NumVisualizationUpdate/obj.NetworkSimulator.EndTime;
            end
            scheduleAction(obj.NetworkSimulator, @obj.visualizer, [], 1/obj.SampleRate, 1/obj.SampleRate);
            drawnow;
        end

        function visualizer(obj, varargin)
            %visualizer Update the node positions in the network visualization

            numTags = numel(obj.Tags);
            for idx=1:numTags
                if ~isvalid(obj.Axis)
                    return;
                end
                nodeDetails = findobj(obj.Axis.Children,'Tag',obj.Tags{idx});
                position = obj.Nodes{idx}.Position;
                nodeDetails.XData = position(1);
                nodeDetails.YData = position(2);
                if obj.ShowDatatip
                    nodeDetails.DataTipTemplate.DataTipRows(2).Value = {sprintf('%.6f, %.6f',position(1),position(2))};
                end
            end
            drawnow;
        end
    end
end