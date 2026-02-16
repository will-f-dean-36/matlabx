function cmap = ColormapSelector(cmap_name)
    arguments
        cmap_name (1,:) char = 'gray'
    end

    if ~guitools.colormaps.Registry.has(cmap_name)
        error('ColormapSelector:InvalidColormapName',...
            'Colormap "%s" does not exist or is not unique. Try specifying a category.',...
            cmap_name);
    end

    fig = uifigure("WindowStyle","alwaysontop",...
        "Name","Select colormap",...
        "Position",[0 0 300 600],...
        "CloseRequestFcn",@(~,~) closeAndReturn(),...
        "Visible","off",...
        "Color",[0.18 0.18 0.18]);

    movegui(fig,"center");

    grid = uigridlayout(fig,[3,1],...
        "RowHeight",{30,'1x',20},...
        "ColumnWidth",{'1x'},...
        "BackgroundColor",[0.18 0.18 0.18],...
        "RowSpacing",5);

    % panel to hold example colormap axes
    cmap_panel = uipanel(grid);
    cmap_panel.Layout.Row = 1;
    cmap_panel.Layout.Column = 1;

    % axes to hold example colorbar
    cmap_axes = uiaxes(cmap_panel,...
        'Visible','Off',...
        'XTick',[],...
        'YTick',[],...
        'Units','Normalized',...
        'InnerPosition',[0 0 1 1]);
    cmap_axes.Toolbar.Visible = 'Off';
    disableDefaultInteractivity(cmap_axes);

    % create image to show example colorbar for colormap switching
    cmap_image = image(cmap_axes,...
        'CData',repmat(1:256,50,1),...
        'CDataMapping','direct');
    % set axes limits so that colorbar image fills axes area
    set(cmap_axes,"YLim",[0.5 50.5],"XLim",[0.5 256.5]);

    % uitree for colormap selection
    cmap_tree = uitree(...
        "Parent",grid,...
        "SelectionChangedFcn",@(~,e) colormapSelectionChanged(e));
    cmap_tree.Layout.Row = 2;
    cmap_tree.Layout.Column = 1;

    % populate tree with colormap categories
    categories = guitools.colormaps.Registry.categories;

    for i = 1:numel(categories)
        thisCategory = categories(i);
        catNode = uitreenode("Parent",cmap_tree,"Text",thisCategory);

        names = guitools.colormaps.Registry.names(thisCategory);

        for j = 1:numel(names)
            uitreenode("Parent",catNode,"Text",names(j),"NodeData",names(j));
        end
    end

    % select input cmap in the tree
    cmap_tree.SelectedNodes = cmap_tree.findobj("NodeData",cmap_name);
    % get the map data
    cmap = guitools.colormaps.Registry.map(cmap_name);
    % and set it in the example colormap axes
    cmap_axes.Colormap = cmap;

    % button to select and exit
    OK_button = uibutton(grid,...
        "Text","OK",...
        "ButtonPushedFcn",@(~,~) selectAndReturn());
    OK_button.Layout.Row = 3;
    OK_button.Layout.Column = 1;

    % show figure
    fig.Visible = 'on';

    % do not return until figure is closed
    waitfor(fig);

    function closeAndReturn()
        % delete the figure
        delete(fig)
    end

    function selectAndReturn()
        cmap = guitools.colormaps.Registry.map(cmap_tree.SelectedNodes.NodeData);
        delete(fig);
    end

    function colormapSelectionChanged(evt)
        % get the newly selected node
        node = evt.SelectedNodes;
        % get colormap name from NodeData property
        name = node.NodeData;
        % if empty -> user selected a category node, return
        if isempty(name), return; end
        % get category from Text property of Parent node
        catName = node.Parent.Text;
        % update cmap and set it on example colormap axes
        cmap = guitools.colormaps.Registry.map(name,catName);
        cmap_axes.Colormap = cmap;
    end

end