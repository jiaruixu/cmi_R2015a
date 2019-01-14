% ImageClass function
function xyz = getImageCoords(self,ind,iflag)
% Inputs:
%   ind = [n x 3] matrix of indices (x,y,z)
%   iflag = 1/0 flagging for conversion of spatial to matrix coordinates

d = self.dims(1:3);

n = cross(self.dircos(1:3),self.dircos(4:6));
M = [reshape(self.dircos,3,2),n',self.slcpos';zeros(1,3),1];

if nargin==1
    % Return all spatial coordinates of image:
    
    [X,Y,Z] = meshgrid(flip((0:d(2)-1)*self.voxsz(2)),...
                       (0:d(1)-1)*self.voxsz(1),...
                       (0:d(3)-1)*self.voxsz(3));
    xyz = M * [reshape(cat(4,X,Y,Z),prod(d),3)';ones(1,prod(d))];
    xyz = reshape(xyz(1:3,:),[d,3]);
%     X = reshape(I(1,:),d);
%     Y = reshape(I(2,:),d);
%     Z = reshape(I(3,:),d);
elseif (nargin==2) || ~iflag
    % Return only specified coordinates:
    
    if (size(ind,2)==3) && all(ind>0) && all(ind(:,1)<=d(1)) ...
            && all(ind(:,2)<=d(2)) && all(ind(:,3)<=d(3))
        xyz = (M * [ ((ind-0.5) * diag(self.voxsz))' ; ones(1,size(ind,1)) ])';
        xyz(4) = [];
%         X = I(1);
%         Y = I(2);
%         Z = I(2);
    else
        error('Invalid index input.');
    end
else
    % Convert spatial coordinates to matrix coords
    
    if (size(ind,2)==3)
        xyz = (M \ [ ind' ; ones(1,size(ind,1)) ])';
        xyz = xyz(:,1:3) / diag(self.voxsz) + 0.5;
    else
        error('Invalid index input.');
    end
end

% d = self.dims(1:3);
% v = self.voxsz;
% vd = (d-1)/2 .* v;
% [X,Y,Z] = meshgrid(-vd(2):v(2):vd(2),-vd(1):v(1):vd(1),-vd(3):v(3):vd(3));
