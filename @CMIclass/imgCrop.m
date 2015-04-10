% CMIclass function
% Crop Image to current zoom
function imgCrop(self,~,~)
if self.img.check
    ind = 1:3; ind(self.orient) = [];
    % initially place rectangle in center of image w/ square dimensions
    tvoxsz = self.img.voxsz(ind);
    xl = get(self.haxes,'XLim');
    yl = get(self.haxes,'YLim');
    dx = diff(xl);
    dy = diff(yl);
    switch self.orient
        case 1
            dx = 0.9*dx;
            shft = [ 0.05*dx , 0 ];
        case 2
            dx = 0.9*dx;
            shft = [ 0.05*dx , 0 ];
        case 3
            dt = min(dx,dy);
            dx = dt*0.9; dy = dt*0.9;
            shft = 0.05*dt*[1,1];
    end
    pos = [ xl(1)+shft(1) , yl(1)+shft(2) , dx , dy ];
    hrect = imrect(self.haxes,pos);
    if self.orient==3
        setFixedAspectRatioMode(hrect,true);
    end
    setPositionConstraintFcn(hrect,...
        makeConstrainToRectFcn('imrect',get(self.haxes,'XLim'),...
                                        get(self.haxes,'YLim')));
    pos = wait(hrect);
    delete(hrect);
    if ~isempty(pos)
        % convert spatial positions to matrix positions
        pos = round(pos([2 1 4 3])./tvoxsz([1 2 1 2]));
        pos = pos + [1 1 0 0];
        
        coord = [ pos(1:2)           ;...
                  pos(1:2)+pos(3:4)-1 ]';
        disp('Crop extents:');
        for i = 1:length(ind)
            disp(['   Dim',num2str(ind(i)),' : ',...
                num2str(coord(i,1)'),'-',num2str(coord(i,2))]);
        end
        
        self.img.crop(ind(:),coord);
        
        % Update current slices
        tslc = self.slc(self.orient);
        self.slc = round(self.img.dims/2);
        self.slc(self.orient) = tslc;
        
        % Update displayed image
        self.dispUDview;
    end
end