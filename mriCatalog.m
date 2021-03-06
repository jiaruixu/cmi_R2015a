function [C,hfig] = mriCatalog(studydir,displaycheck)
% Catalog Bruker MRI study data and convert to MHD

if nargin<2
    displaycheck = false;
end

hdr = {'Series','Protocol','Method','TR','TE','NE','Matrix','Thk','Nslc','MToff','MT'};
nlab = length(hdr);

% Find subject ID:
subjfname = fullfile(studydir,'subject');
if exist(subjfname,'file')
    fid = fopen(subjfname,'r');
    str = fread(fid,inf,'*char')';
    fclose(fid);
    tok = regexp(str,'##\$SUBJECT_id=[^<]*<([^>]*)','tokens');
    subjectID = tok{1}{1};
    subjectID(strfind(subjectID,'_')) = [];
else
    error('Not a Bruker MRI study folder: %s',studydir);
end
[~,studyname] = fileparts(studydir);
dateString = studyname(1:8);

% Find acquisitions:
dnames = dir(studydir);
dnames(1:2) = [];
nd = length(dnames);
C = cell(nd,nlab);
stat = false(nd,1);

% Find scan parameters
for i = 1:nd
    if dnames(i).isdir
        pnames = {fullfile(studydir,dnames(i).name,'method')};
        if exist(pnames{1},'file')
            if exist(fullfile(studydir,dnames(i).name,'acqp'),'file')
                pnames{2} = fullfile(studydir,dnames(i).name,'acqp');
            end
            p = readBrukerMRIpar(pnames);
            C(i,:) = [{dnames(i).name},parsePars(p,{'ACQ_scan_name','Method',...
                'PVM_RepetitionTime','PVM_EchoTime','PVM_NEchoImages','PVM_Matrix',...
                'PVM_SliceThick','PVM_SPackArrNSlices','PVM_MagTransOffset','PVM_MagTransOnOff'})];
            stat(i) = true;
        end
    end
end
C = C(stat,:);
[~,ord] = sort(str2double(C(:,1)));
C = C(ord,:);
mti = ~strcmp(C(:,11),'On');
C(mti,10) = {'off'};
C(:,11) = [];
hdr(end) = [];
saveCell2Txt([hdr;C],fullfile(studydir,sprintf('%s_%s_Catalog.tsv',dateString,subjectID)));

% Display catalog as table figure:
if displaycheck
    CC = C;
    ind = cellfun(@(x)~ischar(x)&&(numel(x)>1),C);
    CC(ind) = cellfun(@num2str,CC(ind),'UniformOutput',false);
    hfig = figure('Position',[900,500,800,700],'MenuBar','none','ToolBar','none',...
        'Name',sprintf('Study: %s',studyname),...
        'ToolBar','none');
    uitable(hfig,'Units','normalized','Position',[0,0,1,1],'ColumnName',hdr,...
        'ColumnWidth',{50,100,100,50,50,50,80,50,50,50,50},...
        'ColumnEditable',[true,false(1,nlab-1)],'Data',CC);
end


function v = parsePars(p,fieldnames)
nf = length(fieldnames);
v = cell(1,nf);
for i = 1:nf
    if isfield(p,fieldnames{i})
        v{i} = p.(fieldnames{i});
        if strcmp(fieldnames{i},'Method')
            tok = regexp(v{i},'<\w*:(\w*)>','tokens');
            v{i} = tok{1}{1};
        elseif strcmp(fieldnames{i},'ACQ_scan_name')
            tok = regexp(v{i},'<(\w*)','tokens');
            if isempty(tok)
                disp('');
            end
            v{i} = tok{1}{1};
        end
    end
end

function saveImg(studydir,dateString,subjectID,ser)
svdir = fullfile(studydir,'MHD');
if ~isdir(svdir)
    mkdir(svdir);
end
p = readBrukerMRIpar(fullfile(studydir,ser,{'method','acqp'}));
if isempty(strfind(p.ACQ_scan_name,'_Fat'))
    [img,label,fov] = readBrukerMRI(fullfile(studydir,ser,'pdata','1','2dseq'));
    for i = 1:size(img,4)
        saveMHD(fullfile(svdir,sprintf('%s_%s_%s.mhd',dateString,subjectID,label{i})),img(:,:,:,i),{''},fov);
    end
else
    [img,label,fov] = readBrukerMRI(fullfile(studydir,ser,'fid'));
    save(fullfile(svdir,sprintf('%s_%s_%s_%s.mat',dateString,subjectID,ser)),'img','label','fov');
    % Perform Fat/Water separation:
    p = readBrukerMRIpar(fullfile(studydir,ser,'method'));
    [FF,W,F,R2s,fmap] = fwi2(permute(coilCombine(img),[1,3,2,4,5]),p.EffectiveTE,p.PVM_FrqRef(1));
    saveMHD(fullfile(svdir,sprintf('%s_%s.mhd',dateString,subjectID)),...
        cat(4,FF*100,abs(W),abs(F),R2s,fmap),{'FatPct','Water','Fat','R2star','FieldMap'},fov([2,3,1]));
end
