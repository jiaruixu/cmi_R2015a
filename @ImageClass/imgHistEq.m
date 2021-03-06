% ImageClass function
function stat = imgHistEq(self,vec)

if nargin==1
    vec = 1:self.dims(4);
end

stat = false;
if self.check
    if self.mask.check
        mask = self.mask.mat;
    else
        mask = 1;
    end
    for i = 1:length(vec)
        if ismember(vec(i),1:self.dims(4))
            timg = self.mat(:,:,:,vec(i)) .* mask;
            mmin = min(timg(:));
            mmax = max(timg(:));
            timg = (timg-mmin)/(mmax-mmin);
            timg = adapthisteq(reshape(timg,self.dims(1),[]));
%             timg = timg * (mmax-mmin) + mmin;
            self.mat(:,:,:,vec(i)) = reshape(timg,self.dims(1:3))*1000;
            self.valExt(vec(i),:) = [0,1000];
            self.thresh(vec(i),:) = (self.thresh(vec(i),:)-mmin)/(mmax-mmin);
            stat = true;
        else
            warning('Invalid image index.');
        end
    end
end