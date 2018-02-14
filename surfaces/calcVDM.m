function [vdm,h] = calcVDM(method,mask,voxsz,dt,elxdir)
% Method:
%   1 = linear |J|
%   2 = exponential |J|
%   3 = Surface tangent |J|
%   4 = d|J|/dt
%   5 = dA


% method = 5;
logchk = true;
if logchk
%     V = log(V);
%     clim = 0.8 * [-1,1];
    clim = [0.5,2.25];
else
    clim = 1 + 0.4*[-1,1];
end

% Check for existing results:
vdmname = fullfile(elxdir,'VDM.mat');
if exist(vdmname,'file')
    vdm = load(vdmname);
    d = size(mask);
    lims = (d-1).*voxsz/2;
    [x,y,z] = meshgrid(-lims(2):voxsz(2):lims(2),...
                       -lims(1):voxsz(1):lims(1),...
                       -lims(3):voxsz(3):lims(3));
else
    [fv,x,y,z] = mask2surf(mask,voxsz);
    
    % Save points:
    ptsname = fullfile(elxdir,'inputPoints.txt');
    fid = fopen(ptsname,'w');
    nv = size(fv.vertices,1);
    fprintf(fid,'point\n%u\n',nv);
    for i = 1:nv
        fprintf(fid,'%f %f %f\n',fv.vertices(i,:));
    end
    fclose(fid);

    vdm = struct('voxsz',voxsz,'vertices',fv.vertices,'faces',fv.faces,...
        'map_linJ',[],'map_expJ',[],'map_tanJ',[],'map_dJdt',[],'map_dA',[]);
    clear fv;
end


% Generate surface map based on method:
switch method
    case 1 % linear |J|
        
        label = 'map_linJ';
        str = 'Linear |J|';
        
        V = (surfVal(loadData(elxdir,'jdet'),x,y,z,vdm.vertices)-1)/dt +1;
        
    case 2 % exponential |J|
        
        label = 'map_expJ';
        str = 'Exponential |J|';
        
        V = surfVal(loadData(elxdir,'jdet'),x,y,z,vdm.vertices).^(1/dt);
        
    case 3 % surface tangent |J|
        
        label = 'map_tanJ';
        str = 'Surface Tangent |J|';
        
        M = permute(reshape(surfVal(loadData(elxdir,'jmat'),x,y,z,vdm.vertices)',3,3,[]),[2,1,3]);

        % Determine planar Jacobian from isonormals:
        n = isonormals(x,y,z,mask,fv.vertices);
        V = zeros(nv,1);
        for i = 1:size(n,1)
            R = vrrotvec2mat(vrrotvec([0,1,0],n(i,:)));
            tjac = R * M(:,:,i) * R';
            V(i) = det(tjac(1:2,1:2));
        end
        clear M;
        V = V.^(1/dt);

    case 4 % d|J|/dt
        
        label = 'map_dJdt';
        str = 'd|J|/dt';
        
        dX = loadData(elxdir,'def');
        fprintf('Calculating spatial Jacobian ...\n');
        F = surfVal(def2jac(dX,voxsz),x,y,z,vdm.vertices(:,:,1));
        fprintf('Calculating spatial rate Jacobian ...\n');
        FF = surfVal(def2jac(dX/dt,voxsz),x,y,z,vdm.vertices(:,:,1));

        np = size(F,1);
        V = zeros(np,1);
        f = zeros(3); % J
        ff = zeros(3);% dJ/dt
        gi = mod(1:np,round(np/20))==0;
        fprintf('Calculating Jacobian rate determinant ...\n');
        for i = 1:np
            f(:) = F(i,:);
            ff(:) = FF(i,:);
            V(i) = det(f) * trace( ff / f )/3;
            if gi(i)
                fprintf('%u%% Complete\n',sum(gi(1:i))*5);
            end
        end
        
    case 5 % dA
        
        label = 'map_dA';
        str = 'Relative Surface Area';
        
        p = loadData(elxdir,'pts');
        vdm.vertices = p;
        nf = size(vdm.faces,1);
        V = zeros(nf,1);
        fprintf('Calculating face areas ...\n');
        for i = 1:nf
            V(i) = area3D(p(vdm.faces(i,:),:,:));
        end
        V = V.^(1/dt);
end
clear x y z;
vdm.(label) = V;

% Save resulting maps:
save(vdmname,'-struct','vdm');

% Generate VDM figure:
h = savesurf(2,vdm.faces,vdm.vertices(:,:,end),V,clim,str,logchk,...
    fullfile(elxdir,sprintf('VDM_%s',label)));


function V = surfVal(M,x,y,z,p)
nv = size(M,4);
V = zeros(size(p,1),nv);
for i = 1:nv
    V(:,i) = interp3(x,y,z,M(:,:,:,i),p(:,1),p(:,2),p(:,3));
end

function A = loadData(elxdir,opt)
C = {'def'  ,'deformationField.mhd'     ,'-def all';...
     'jdet' ,'SpatialJacobian.mhd'      ,'-jac all';...
     'jmat' ,'FullSpatialJacobian.mhd'  ,'-jacmat all';...
     'pts'  ,'outputpoints.txt'         ,'-def "./inputPoints.txt"'};
i = find(strcmp(opt,C(:,1)),1);
if isempty(i)
    error('Invalid input.')
end
fname = fullfile(elxdir,C{i,2});
if ~exist(fname,'file')
    % Need to generate from transform:
    parname = dir(fullfile(elxdir,'TransformParameters.*.txt'));
    ind = max(cellfun(@(x)str2double(x(21)),{parname(:).name}));
    str = sprintf(['/opt/X11/bin/xterm -geometry 170x50 -T "(Transformix)" -e ''',...
             'cd %s ; /usr/local/bin/transformix -out "./" -tp ',...
             '"./TransformParameters.%u.txt" %s'''],elxdir,ind,C{i,3});
    system(str);
end
if i==4
    A = readPtsFile(fname);
else
    A = readMHD(fname);
end

function p = readPtsFile(fname)
% Vertex points: [nv x (x/y/z) x (in/out)]
disp('Reading points from file ...')
fid = fopen(fname,'r');
str = fread(fid,'*char')';
fclose(fid);
pat = ' = \[ (\S+) (\S+) (\S+) ]';
tok = cellfun(@(x)str2double(x)',regexp(str,['InputPoint',pat],'tokens'),'UniformOutput',false);
p = [tok{:}]';
tok = cellfun(@(x)str2double(x)',regexp(str,['OutputPoint',pat],'tokens'),'UniformOutput',false);
p(:,:,2) = [tok{:}]';

function A = area3D(p)
A = [0,0];
for i = 1:2
    a = norm(p(1,:,i)-p(2,:,i));
    b = norm(p(2,:,i)-p(3,:,i));
    c = norm(p(3,:,i)-p(1,:,i));
    s = (a+b+c)/2;
    A(i) = sqrt(s*(s-a)*(s-b)*(s-c));
end
A = A(2)/A(1);
    