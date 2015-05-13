% ImageClass function
function [MFout,labels] = calcMF(self,vec,thresh,n,varargin)
% Calculate Minkowski Functionals
% Inputs:   vec = 4D image index to perform analysis on
%           optional Name/Value pairs:
%               'Thresh'  = vector of thresholds to use
%               'Window'  = radius (voxels) of moving window
%                               *(use inf if you want whole-image)
%               'ApplyMask' = check for use of existing VOI
%               'ImgCheck'  = check to analyze image (true) or VOI (false)

MFout = [];
labels = {};

p = inputParser;
addRequired(p,'Vec',@(x)isscalar(x)&&(x>0));
addRequired(p,'Thresh',@isnumeric);
addRequired(p,'Window',@isvector);
addParameter(p,'ApplyMask',true,@islogical);
parse(p,vec,thresh,n,varargin{:});
pp = p.Results;

if self.check
    
    timg = self.mat(:,:,:,pp.Vec);
    gchk = any(isinf(pp.Window));
    
    if gchk
        
        nth = length(pp.Thresh);
        if nD == 2
            nmf = 3;
        else
            nmf = 4;
        end

        % Initialize output matrix:
        MFout = zeros([nth,nmf]);

        % Loop over desired image thresholds:
        for ith = 1:nth
            BW = timg > pp.Thresh(ith);
            if gchk
                BW = BW & self.mask.mat;
            end
            [MFout(ith,:),labels] = minkowskiFun(BW,pp.Window,varargin{:});
        end

        % Display global results:
        vals = [{'Thresh'},num2cell(pp.Thresh);...
                labels(:),num2cell(squeeze(MFout))];
        msgbox(sprintf(['%10s:',repmat(' %8f',nth)],vals{:}),'Minkowski Functionals');
        
    else
        
        % User decides where to save results:
        [fname,fpath] = uiputfile('*.mhd','Save MF Results',[self.name,'.mhd']);
        
        % Run in batch - will take too long to wait for
        ind = [];
        if pp.ApplyMask && self.mask.check
            ind = find(self.mask.mat);
        end
        batch_MinkowskiFun(fullfile(fpath,fname),...
                           self.voxsz.*self.dims(1:3),...
                           timg,pp.Window,pp.Thresh,ind);
        
    end
end

