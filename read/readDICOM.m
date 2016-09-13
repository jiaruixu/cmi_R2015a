function [img,label,fov,dcmdata] = readDICOM(varargin)

fnames = varargin{1};
din = [];
if nargin==2
    din = varargin{2};
end
img = []; label = {}; fov = [];
[fpath,fname,ext] = fileparts(fnames);
if isempty(fpath)
    fpath = pwd;
end
if ~any(strcmp(ext,{'.dcm','.1'}))
    ext = [];
end
if strncmp(version('-release'),'2016',4)
    v = {'UseDictionaryVR',true};
else
    v = {};
end

% Find and load all DICOM files in selected directory
if strcmpi(fname,'dicomdir')
    % DICOM names are stored in "DICOMDIR" file
    hp = waitbar(0,'Reading DICOMDIR ...');
    tinfo = dicominfo(fnames,v{:});
    fnames = fieldnames(tinfo.DirectoryRecordSequence);
    nf = length(fnames);
    ind = false(1,nf);
    for i = 1:nf
        if isfield(tinfo.DirectoryRecordSequence.(fnames{i}),'ReferencedFileID')
            tdir = tinfo.DirectoryRecordSequence.(fnames{i}).ReferencedFileID;
            fnames{i} = strrep(tdir,'\',filesep);
        else
            ind(i) = true;
        end
        waitbar(i/nf,hp,'Finding file locations ...');
    end
    delete(hp);
    fnames(ind) = [];
    nf = nf - nnz(ind);
else
    % All DICOMs are in single directory
    fnames = dir([fpath,filesep,'*',ext]);
    fnames = {fnames(:).name};
    fnames(~cellfun(@(x)(exist(fullfile(fpath,x),'file')==2)&&isdicom(fullfile(fpath,x)),fnames)) = [];
%     fnames = fnames(isDICOM(fullfile(path,fnames))==1);
    nf = length(fnames);
end

dcmdata = struct('SeriesInstanceUID',{},... % for sorting multiple images
                 'img',{},...
                 'd',{},...
                 'AcquisitionNumber',{},...
                 'SeriesNumber',{},...
                 'TemporalPositionIdentifier',{},...
                 'DiffusionNumber',{},...
                 'SlicePos',{},...
                 'SlcThk',{},...
                 'PixelSpacing',{},...
                 'StudyDescription',{},...
                 'PatientID',{},...
                 'Label',{});
% * Images are sorted into 3D via SlcLoc,
%   and 4D via arrayed values:
%       MRI - TE, TR, ...
%       CT  - kV, ...
             
% Read in all DICOM slices:
hp = waitbar(0,'','WindowStyle','modal',...
    'CreateCancelBtn','setappdata(gcbf,''canceling'',1)'); % Option to cancel load midway
setappdata(hp,'canceling',0)
try
for ifn = 1:nf
    
    % Check for Cancel button press
    if getappdata(hp,'canceling')
        img = []; label = {}; fov = [];
        dcmdata = [];
        break
    end
    waitbar((ifn-1)/nf,hp,fnames{ifn});
    
    % Load DICOM file info:
    tinfo = dicominfo(fullfile(fpath,fnames{ifn}),v{:});
    if (ifn==1) % Check manufacturer to read private tags:
        ddir = fileparts(which('cmi'));
        if isfield(tinfo,'Manufacturer')
            str = tinfo.Manufacturer;
        else
            str = '';
        end
        if strncmpi(str,'philips',7)
            dicomdict('set',fullfile(ddir,'read','dicom-dict-Philips.txt'));
        elseif strncmpi(str,'ge',2)
            dicomdict('set',fullfile(ddir,'read','dicom-dict-GE.txt'));
        elseif strncmpi(str,'siemens',7)
            dicomdict('set',fullfile(ddir,'read','dicom-dict-Siemens.txt'));
        else
            dicomdict('factory');
        end
        tinfo = dicominfo(fullfile(fpath,fnames{ifn}),v{:});
    end
    
    if isfield(tinfo,'Modality')
        % Check if Series already exists in structure:
    %     disp(tinfo.SeriesInstanceUID);
    %     disp(num2str(tinfo.AcquisitionNumber));
    %     disp(num2str(tinfo.SeriesNumber));
    %     disp(num2str(tinfo.InstanceNumber));
    %     waitforbuttonpress
%         acqN = 0;
%         if isfield(tinfo,'AcquisitionNumber') && ~isempty(tinfo.AcquisitionNumber)
%             acqN = tinfo.AcquisitionNumber;
%         end
        serN = 0;
        if isfield(tinfo,'SeriesNumber') && ~isempty(tinfo.SeriesNumber)
            serN = tinfo.SeriesNumber;
        end
        tempN = 0;
        if isfield(tinfo,'TemporalPositionIdentifier') && ~isempty(tinfo.TemporalPositionIdentifier)
            tempN = tinfo.TemporalPositionIdentifier;
        end
        diffN = 0;
        if isfield(tinfo,'DiffusionBValue')
            nv = length(tinfo.DiffusionBValue);
            if nv==1
                diffN = tinfo.DiffusionBValue;
            elseif isa(tinfo.DiffusionBValue,'uint8')
                diffN = str2double(char(tinfo.DiffusionBValue'));
            end
        elseif isfield(tinfo,'Private_DiffusionBValue')
            nv = length(tinfo.DiffusionBValue);
            if nv==1
                diffN = tinfo.DiffusionBValue;
            elseif isa(tinfo.DiffusionBValue,'uint8')
                diffN = str2double(char(tinfo.DiffusionBValue'));
            end
        elseif isfield(tinfo,'B_value') && (length(tinfo.B_value)==1)
            diffN = tinfo.B_value;
        elseif isfield(tinfo,'SlopInt_6_9') && ~isempty(tinfo.SlopInt_6_9)
            if isa(tinfo.SlopInt_6_9,'uint8')
                % stored as char
                diffN = char(tinfo.SlopInt_6_9');
                diffN = str2double(strtok(diffN,'\'));
                if diffN>1e6
                    diffN = diffN - 1e9;
                end
            else % assumed double
                diffN = tinfo.SlopInt_6_9(1);
            end
        end
        diffD = zeros(3,1);
        if isfield(tinfo,'DiffusionGradientOrientation')
            nv = length(tinfo.DiffusionGradientOrientation);
            if nv==3
                diffD = tinfo.DiffusionGradientOrientation;
            elseif isa(tinfo.DiffusionGradientOrientation,'uint8') && (nv>=24)
                diffD = [ typecast(tinfo.DiffusionGradientOrientation(1:8),'double') ;...
                          typecast(tinfo.DiffusionGradientOrientation(9:16),'double') ;...
                          typecast(tinfo.DiffusionGradientOrientation(17:24),'double') ];
            end
        elseif isfield(tinfo,'DiffusionGradientDirection') && (length(tinfo.DiffusionGradientDirection)==3)
            diffD = tinfo.DiffusionGradientDirection;
        elseif all(isfield(tinfo,{'DiffusionDirectionX','DiffusionDirectionY','DiffusionDirectionZ'}))
            if ~isempty(tinfo.DiffusionDirectionX) && (numel(tinfo.DiffusionDirectionX)==1)
                diffD(1) = tinfo.DiffusionDirectionX;
            end
            if ~isempty(tinfo.DiffusionDirectionY) && (numel(tinfo.DiffusionDirectionY)==1)
                diffD(2) = tinfo.DiffusionDirectionY;
            end
            if ~isempty(tinfo.DiffusionDirectionZ) && (numel(tinfo.DiffusionDirectionZ)==1)
                diffD(3) = tinfo.DiffusionDirectionZ;
            end
        end
        TE = 0;
        if isfield(tinfo,'EchoTime') && ~isempty(tinfo.EchoTime)
            TE = tinfo.EchoTime;
        end
        TR = 0;
        if isfield(tinfo,'RepetitionTime') && ~isempty(tinfo.RepetitionTime)
            TR = tinfo.RepetitionTime;
        end
        j = [];
        if ~isempty(dcmdata)
            j = find( strcmp(tinfo.SeriesInstanceUID,{dcmdata(:).SeriesInstanceUID}) ...
                    & (serN==[dcmdata(:).SeriesNumber]) ...
                    & (tempN == [dcmdata(:).TemporalPositionIdentifier]) ...
                    & (diffN == [dcmdata(:).DiffusionNumber]) ...
                    & ismember([dcmdata(:).DiffusionDir]',diffD','rows')' ...
                    & (TE==[dcmdata(:).TE]) ...
                    & (TR==[dcmdata(:).TR]) ,1);
        end
        if isempty(j)
            % Initialize new series in structure:
            j = length(dcmdata)+1;
            val = '';
            if isfield(tinfo,'SeriesInstanceUID')
                val = tinfo.SeriesInstanceUID;
            end
            dcmdata(j).SeriesInstanceUID = val;
            dcmdata(j).SeriesNumber = serN;
            dcmdata(j).TemporalPositionIdentifier = tempN;
            dcmdata(j).DiffusionNumber = diffN;
            dcmdata(j).DiffusionDir = diffD;
            dcmdata(j).TE = TE;
            dcmdata(j).TR = TR;
            val = [1,1];
            if isfield(tinfo,'PixelSpacing')
                val = tinfo.PixelSpacing;
            end
            dcmdata(j).PixelSpacing = val;
            val = [];
            if isfield(tinfo,'SliceThickness')
                val = tinfo.SliceThickness;
            elseif isfield(tinfo,'SpacingBetweenSlices')
                val = tinfo.SpacingBetweenSlices;
            end
            dcmdata(j).SlcThk = val;
            val = '';
            if isfield(tinfo,'StudyDescription')
                val = tinfo.StudyDescription;
            end
            dcmdata(j).StudyDescription = val;
            if isfield(tinfo,'DiffusionBValue') && (length(tinfo.DiffusionBValue)==1)
                val = ['b',num2str(tinfo.DiffusionBValue)];
            elseif isfield(tinfo,'SeriesDescription') && ~isempty(tinfo.SeriesDescription)
                val = tinfo.SeriesDescription;
            elseif isfield(tinfo,'ProtocolName') && ~isempty(tinfo.ProtocolName)
                val = tinfo.ProtocolName;
            else val = tinfo.Modality;
            end
            dcmdata(j).Label = {val};
            val = '';
            if isfield(tinfo,'PatientID')
                val = tinfo.PatientID;
            end
            dcmdata(j).PatientID = val;
            dcmdata(j).img = [];
            if all(isfield(tinfo,{'Rows','Columns'}))
                dcmdata(j).d = [tinfo.Rows,tinfo.Columns];
            end
        end
        k = size(dcmdata(j).SlicePos,1)+1;
        if isempty(tinfo.AcquisitionNumber)
            val = 0;
        else
            val = tinfo.AcquisitionNumber;
        end
        dcmdata(j).AcquisitionNumber(k) = val;
        val = nan(1,3);
        if isfield(tinfo,'ImagePositionPatient')
            val = tinfo.ImagePositionPatient;
        elseif isfield(tinfo,'SliceLocation')
            val(3) = tinfo.SliceLocation;
        else
            val(3) = ifn;
        end
        dcmdata(j).SlicePos(k,:) = val;

        % Read slice data from file:
        ySlope = 1;
        if isfield(tinfo,'RescaleSlope') && ~isempty(tinfo.RescaleSlope)
            ySlope = tinfo.RescaleSlope;
        elseif isfield(tinfo,'MRScaleSlope')
            ySlope = 1/tinfo.MRScaleSlope;
        end
        yInt = 0;
        if isfield(tinfo,'RescaleIntercept') && ~isempty(tinfo.RescaleIntercept)
            yInt = tinfo.RescaleIntercept;
        elseif isfield(tinfo,'MRScaleIntercept')
            yInt = -tinfo.MRScaleIntercept/ySlope;
        end
        timg = ySlope * double(dicomread(tinfo)) + yInt;
        if (length(tinfo.ImageType)>5) && strcmp(tinfo.ImageType(end-5:end),'MOSAIC')
            ns = int32(tinfo.LocationsInAcquisition(1));
            nslab = ceil(sqrt(double(ns)));
            md = size(timg);
            d = md/nslab;
            mosi = timg;
            timg = zeros([d,ns]);
            ci = reshape((1:nslab)'*ones(1,nslab),1,[]);
            ri = reshape(ones(nslab,1)*(1:nslab),1,[]);
            for i = 1:ns
                timg(:,:,i) = mosi( (ri(i)-1)*d(1)+(1:d(1)) , (ci(i)-1)*d(2)+(1:d(2)) );
            end
            dcmdata(j).d = d;
            kk = k - 1 + (1:ns);
            dcmdata(j).AcquisitionNumber(kk) = dcmdata(j).AcquisitionNumber(k);
            % Correct slice locations:
            RS = reshape(tinfo.ImageOrientationPatient,[3,2]);
            t = dcmdata(j).SlicePos(k,:)' + RS*(double(md)-double(d))'/2;
            RS(:,3) = cross(RS(:,1),RS(:,2));
            th = double(0:ns-1)*dcmdata(j).SlcThk;
            dcmdata(j).SlicePos(kk,:) = repmat(t',[ns,1]) + (RS*[zeros(ns,2),th']')';
            k = kk;
        end
        if isempty(dcmdata(j).img)
            dcmdata(j).img = timg;
        else
            dcmdata(j).img(:,:,k) = timg;
        end
    end
end
delete(hp);
catch err
    assignin('base','err',err);
    delete(hp);
    dcmdata = [];
    error('Error in readDICOM.m - Check variable "err" for more info.');
end

if ~isempty(dcmdata)
    
%     % Some image sets not separable into 4D, so use multiples of slice
%     % locations to determine splits (e.g. MR Solutions):
%     if length(dcmdata)==1
%         u = unique(cellfun(@(x)sum(dcmdata.SlcLoc==x),num2cell(unique(dcmdata.SlcLoc))));
%         if (length(u)==1) && (u>1)
%             ns = length(dcmdata.SlcLoc)/u;
%             dcmdata.img = reshape(dcmdata.img,[dcmdata.d,ns,u]);
%             dcmdata.SlcLoc = dcmdata.SlcLoc(1:ns);
%             dcmdata.Label = repmat(dcmdata.Label,1,u);
%         end
%     end
    
    % Sort by slice location
    for i = 1:length(dcmdata)
        [~,ix] = sort(dcmdata(i).SlicePos(:,3));
        dcmdata(i).SlicePos = dcmdata(i).SlicePos(ix,:);
        dcmdata(i).img = dcmdata(i).img(:,:,ix);
        dcmdata(i).AcquisitionNumber = dcmdata(i).AcquisitionNumber(ix);
    end

    n = length(dcmdata);
    % If multiple images per position, try and separate based on AcquisitionNumber
    ct = 0;
    for i = 1:n
        ii = i+ct;
        ns = length(dcmdata(ii).AcquisitionNumber);
        uS = unique(dcmdata(ii).SlicePos,'rows');
        nuS = length(uS);
%         uA = unique([dcmdata(ii).SlicePos,dcmdata(ii).AcquisitionNumber'],'rows');
        uA = unique(dcmdata(ii).AcquisitionNumber);
        nuA = length(uA);
        if (nuS~=ns)
            if (nuA>1)
                disp('Separating images by AcquisitionNumber');
                A = dcmdata(ii).AcquisitionNumber;
                uA = unique(A);
                nuA = length(uA);
                dcmdata = [ dcmdata(1:(ii-1)),...
                            repmat(dcmdata(ii),1,nuA),...
                            dcmdata((ii+1):end) ];
                for j = 1:nuA
                    ind = ~(A==uA(j));
                    dcmdata(ii-1+j).img(:,:,ind) = [];
                    dcmdata(ii-1+j).SlicePos(ind,:) = [];
                    dcmdata(ii-1+j).AcquisitionNumber(ind) = [];
                end
                ct = ct + nuA - 1;
            else
                disp('Separating images based on file order.');
                [~,ind] = sortrows(dcmdata(ii).SlicePos);
                nsep = ns/nuS;
                dcmdata = [ dcmdata(1:(ii-1)),...
                            repmat(dcmdata(ii),1,nsep),...
                            dcmdata((ii+1):end) ];
                for j = 1:nsep
                    jj = ii-1+j;
                    indj = ind(j:nsep:end);
                    dcmdata(jj).img = dcmdata(jj).img(:,:,indj);
                    dcmdata(jj).SlicePos = dcmdata(jj).SlicePos(indj,:);
                    dcmdata(jj).AcquisitionNumber = dcmdata(jj).AcquisitionNumber(indj);
                end
            end
        end
    end
    
    n = length(dcmdata);
    gflag = 0; % Flag for number of slices per location group
    oimg = [];
    uN = unique(cellfun(@(x)size(x,1),{dcmdata(:).SlicePos}));
    uS = unique(round(diff(dcmdata(1).SlicePos(:,3)),3));
    % Looking for significant differences in slice spacing:
    if (n==1) && (length(uS)==2) && (mean(abs(uS-mean(uS))/mean(uS))>0.001)
%     if (n==1) && (length(unique(round(diff(dcmdata.SlicePos(:,3)),3)))==2)
    % Case for 2-slice gapped CT data
        gflag = 2;
        oimg = dcmdata.img;
        oloc = dcmdata.SlicePos;
    elseif (length(uN)==1) && ismember(uN,1:2)
    % 1: Case for single-slice gapped CT data
    % 2: Case for 2-slice gapped CT data
        gflag = size(dcmdata(1).SlicePos,1);
        oimg = cat(3,dcmdata(:).img);
        oloc = cat(1,dcmdata(:).SlicePos);
    end
    if gflag
        answer = questdlg('How would you like to compile these slices?',...
            'Gapped CT','Concatenate','Insert Gaps','Cancel','Concatenate');
        if ~strcmp(answer,'Cancel')
            tdata = dcmdata(1);
            if strcmp(answer,'Insert Gaps')
                fval = str2double(inputdlg('Blank Slice Value:','',1,{'-1024'}));
            % Determine gaps:
                [~,ix] = sort(oloc(:,3));
                dxyz = sqrt(sum(diff(oloc(ix,:),1).^2,2));
                d = size(oimg);
                if gflag == 2
                    dnew = floor((dxyz(1)+dxyz(2))/dxyz(1));
                    dz = abs(dxyz(1)+dxyz(2))/dnew;
                    d(3) = d(3)*dnew/2;
                    tmat = ones(d)*fval;
                    ind = round(dnew/2):dnew:d(3);
                    ind = [ind;ind+1];
                else % Single-slice
                    dnew = floor(dxyz(1)/tdata.SlcThk);
                    dz = abs(dxyz(1))/dnew;
                    d(3) = d(3)*dnew;
                    tmat = ones(d)*fval;
                    ind = round(dnew/2):dnew:d(3);
                end
                disp(['Image slices are now: ',num2str(ind(:)')])
                tmat(:,:,ind(:)) = oimg(:,:,ix);
                tdata.SlicePos = (0:d(3)-1)'*dz + oloc(1,:);
                tdata.SlcThk = dz;
                tdata.img = tmat;
            else
                tdata.img = oimg;
                tdata.SlicePos = oloc;
            end
            dcmdata = tdata;
        end
    end

    % User GUI to select single acquisition from set:
    if (length(dcmdata)>1)
        dd = cellfun(@size,{dcmdata(:).img},'UniformOutput',false);
        ld = cellfun(@length,dd);
        if all(ld==ld(1)) && all(cellfun(@(x)all(x==dd{1}),dd))
            dcmdata(1).img = cat(4,dcmdata(:).img);
            dcmdata(1).Label = [dcmdata(:).Label];
            dcmdata(1).AcquisitionNumber = ...
                reshape([dcmdata(:).AcquisitionNumber],size(dcmdata(1).img,3),[])';
            dcmdata(1).SeriesNumber = [dcmdata(:).SeriesNumber];
            dcmdata(1).TemporalPositionIdentifier = [dcmdata(:).TemporalPositionIdentifier];
            dcmdata(1).DiffusionNumber = [dcmdata(:).DiffusionNumber];
            dcmdata(1).DiffusionDir = [dcmdata(:).DiffusionDir];
            dcmdata(1).TE = [dcmdata(:).TE];
            dcmdata(1).TR = [dcmdata(:).TR];
            dcmdata(2:end) = [];
        else
            str = strcat('(',cellfun(@(x)num2str(size(x,1)),{dcmdata(:).SlicePos},...
                                     'UniformOutput',false),...
                         ' Slices)',[dcmdata(:).Label]);
            answer = listdlg('ListString',str,'SelectionMode','single',...
                             'ListSize',[300,300]);
            if isempty(answer)
                return % User cancelled the load
            else
                dcmdata = dcmdata(answer);
            end
        end
    end

    ind = isnan(dcmdata.SlicePos(:,3));
    dcmdata.img(:,:,ind) = [];
    dcmdata.SlicePos(ind,:) = [];

    % Sort slices by location:
%     uind = [];
    [d(1),d(2),d(3),d(4)] = size(dcmdata.img);
    n4d = d(4);
    uind = dcmdata.SlicePos(:,3);
    [~,ix,~] = unique(uind,'rows');
    ns = length(ix);
    if ns~=d(3)
        % MR Solutions DICOMs have no way to separate out b-values of DWI
        if mod(d(3),ns)==0
            n4d =  d(3)/ns;
            uind = repmat(0:n4d-1,ns,1);
            uind = uind(:);
            ix = repmat(ix,n4d,1) + uind;
        else
            error('Matrix cannot be separated into 4D.')
        end
    end
    if (n4d>1) && (d(3)==(n4d*nnz(uind==1)))
        ns = d(3)/n4d;
        dcmdata.img = reshape(dcmdata.img(:,:,ix),[d(1:2),ns,n4d]);
        dcmdata.SlicePos = dcmdata.SlicePos(ix(1:ns),:);
        % Determine labeling:
        dcmdata.Label = cell(1,n4d);
        ind = ix(1:ns:d(3));
        if isfield(dcmdata,'TR') && length(unique(dcmdata.TR))>1
            dcmdata.Label = strcat(dcmdata.Label,'TR=',...
                cellfun(@num2str,num2cell(dcmdata.TR(ind)),...
                        'UniformOutput',false),'; ');
        end
        if isfield(dcmdata,'TE') && length(unique(dcmdata.TE))>1
            dcmdata.Label = strcat(dcmdata.Label,'TE=',...
                cellfun(@num2str,num2cell(dcmdata.TE(ind)),...
                        'UniformOutput',false),'; ');
        end
        ind = cellfun(@isempty,dcmdata.Label);
        if any(ind)
            dcmdata.Label(ind) = cellfun(@num2str,num2cell(find(ind)),'UniformOutput',false);
        end
    end

    % Check for dimension match
    [d(1),d(2),d(3),d(4)] = size(dcmdata.img);
    if ~isempty(din) && ~all(d(1:3)==din)
        error(['Dimensions must match!',sprintf(' %f',d)])
    end

    % Prepare data to return:
    img = dcmdata.img;
    dcmdata = rmfield(dcmdata,'img');
    [d(1),d(2),d(3),d(4)] = size(img);
    fov = [dcmdata.PixelSpacing([2,1])',1] .* d([2,1,3]);
    if size(dcmdata.SlicePos,1)>1
        fov(3) = abs(sqrt(sum(diff(dcmdata.SlicePos([1,end],:),1).^2,2))) * d(3)/(d(3)-1);
    elseif ~isempty(dcmdata.SlcThk)
        fov(3) = d(3) * dcmdata.SlcThk;
    end
    label = dcmdata.Label;
end
