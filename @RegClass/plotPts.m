% RegClass function
function plotPts(self,varargin)
% Plot user-selected points on CMIcalss figure

h = [];
if nargin==2
    % Manual callback
    % varargin = { image#(1/2,Ref/Hom) }
    i = varargin{1};
    h = self.cmiObj(i).haxes;
elseif (nargin==3)
    % GUI listener callback
    h = varargin{2}.AffectedObject.haxes;
    i = find(cellfun(@(x)~(isempty(x)||isempty(h))&&(x==h),{self.cmiObj(:).haxes}),1);
end

if ~isempty(h)
    % POINTS ARE IN XYZ
    p = self.points{i};
    if ~isempty(p)
        
        % Retrieve image properties:
        ornt = self.cmiObj(i).orient;
        
        % Convert spatial to matrix coordinates, find points on this slice
        p = self.cmiObj(i).img.getImageCoords(p,1);
        p = p(round(p(:,ornt))==self.cmiObj(i).getProp('slc'),:);
        p(:,ornt) = [];
        
    end
    if isempty(p)
        if ~isnan(self.hpts(i)) && ishghandle(self.hpts(i))
            delete(self.hpts(i));
            self.hpts(i) = nan;
        end
    else
        if isnan(self.hpts(i)) || ~ishghandle(self.hpts(i))
            hold(h,'on');
            self.hpts(i) = plot(h,p(:,2),p(:,1),'*g');
            hold(h,'off');
        else
            set(self.hpts(i),'XData',p(:,2),'YData',p(:,1));
        end
    end
end