function varargout= simulateSystem_R(x,u,v,sss,varargin)

opt = struct('gradients',false,'xLeftSeed',[],'vLeftSeed',[],'sLeftSeed',[],'guessX',[],'guessV',[],'xRightSeed',[],'uRightSeed',[],'vRightSeed',[],'simVars',[]);
opt = merge_options(opt, varargin{:});


ss = sss.ss;
jobSchedule = sss.jobSchedule;
fidW = jobSchedule.fidW;


gradients = opt.gradients;
xLeftSeed = opt.xLeftSeed;
if isempty(xLeftSeed)
    xLeftSeed = createEmptyDistributedVar(jobSchedule);
end
vLeftSeed = opt.vLeftSeed;
if isempty(vLeftSeed)
    vLeftSeed = createEmptyDistributedVar(jobSchedule);
end
sLeftSeed = opt.sLeftSeed;
guessX = opt.guessX;
if isempty(guessX)
    guessX = createEmptyDistributedVar(jobSchedule);
end
guessV = opt.guessV;
if isempty(guessV)
    guessV = createEmptyDistributedVar(jobSchedule);
end
xRightSeed = opt.xRightSeed;
if isempty(xRightSeed)
    xRightSeed = createEmptyDistributedVar(jobSchedule);
end
uRightSeed = opt.uRightSeed;
vRightSeed = opt.vRightSeed;
if isempty(vRightSeed)
    vRightSeed = createEmptyDistributedVar(jobSchedule);
end
simVars = opt.simVars;
if isempty(simVars)
    simVars = createEmptyDistributedVar(jobSchedule);
end

%spmd
[xs,vs,J,converged,simVars,usliced] = runMS(x,u,ss,gradients,xLeftSeed,vLeftSeed,guessX,guessV,xRightSeed,uRightSeed,simVars,fidW);
%end

Jac = [];
if gradients
    if size(uRightSeed,1)==0 && size(sLeftSeed,2)==0  % no seeds given
        [s2,JacS] = realization2s(x,u,v,sss,'partials',true);
        
        %spmd
            xJx = extracField(J,'xJx');
            xJu = extracField(J,'xJu');
            vJx = extracField(J,'vJx');
            vJu = extracField(J,'vJu');
        %end
        Jac.xJx = xJx;
        Jac.xJu = xJu;
        Jac.vJx = vJx;
        Jac.vJu = vJu;
        Jac.sJv = JacS.Jv;
        Jac.sJx = JacS.Jx;
        Jac.sJu = JacS.Ju;


    
    elseif size(xRightSeed{1},1) ~=0 && size(sLeftSeed,2)==0  % right seeds given

        [s2,JacS] = realization2s(x,u,v,sss,'partials',true,'vRightSeed',vRightSeed,'xRightSeed',xRightSeed,'uRightSeed',uRightSeed);
        

        %spmd
        JacxJ = extractJacobian(J,'xJ');
        JacvJ = extractJacobian(J,'vJ');
        %end
        Jac.xJ = JacxJ;
        Jac.vJ = JacvJ;
        
        Jac.sJ = JacS.J;

    elseif size(xRightSeed{1},1) ==0 && size(sLeftSeed,2)~=0
        
        [s2,JacS] = realization2s(x,u,v,sss,'partials',true,'leftSeed',sLeftSeed);
        
        Jac.Jx = cellfun(@(Jr,Jvr)cellfun(@plus,Jr.Jx,Jvr,'UniformOutput',false),J,JacS.Jx,'UniformOutput',false);
        Jac.Ju = cellfun(@(Ji)Ji.Ju ,J,'UniformOutput',false);
        Jac.Ju = catAndSum(Jac.Ju)+JacS.Ju;
		uDims = cellfun(@numel,u);
        Jac.Ju = mat2cell(Jac.Ju,size(Jac.Ju,1),uDims);
        
        
        Jac.Jv = JacS.Jv;
    else
        error('Not allowed to provide rightSeeds and leftSeeds')
    end
else
    [s2] = realization2s(x,u,v,sss,'partials',false);
end



%spmd
convergedAll = all(cell2mat(converged));
convergedAll = gopMPI('*', convergedAll+0,jobSchedule);
%end
convergedAll = NMPI_Bcast(convergedAll,1,jobSchedule.Master_rank,jobSchedule.my_rank)~=0;


varargout{1} = xs;
varargout{2} = vs;
varargout{3} = s2;
varargout{4} = Jac;
varargout{5} = convergedAll;
varargout{6} = simVars;
varargout{7} = usliced;





end


function out = catAndSum(M)

if ~isempty(M)
    if iscell(M{1})
M = cellfun(@cell2mat,M,'UniformOutput',false);

    end
if any(cellfun(@issparse,M))
    if isrow(M)
        M = M';
    end
    rows= size(M{1},1);
    blocks = numel(M);
    out = sparse( repmat(1:rows,1,blocks),1:rows*blocks,1)*cell2mat(M);
else
    out = sum(cat(3,M{:}),3);    
end

else
    out = 0;
end

end


function [xs,vs,J,converged,simVars,usliced] = runMS(x,u,ss,gradients,xLeftSeed,vLeftSeed,guessX,guessV,xRightSeed,uRightSeed,simVars,fidW)
nr = numel(ss);

if isempty(fidW)
    printCounter= false;
    printRef = '\b';
    fid = 1;
else
    printCounter= true;
    fid = fidW;
end

xs = cell(nr,1);
vs = cell(nr,1);
J = cell(nr,1);
converged = cell(nr,1);
usliced = cell(nr,1);

for r = 1:nr
    if printCounter
        printRef = sprintf('%d/%d',r,nr);
    end
    [xs{r},vs{r},J{r},converged{r},simVars{r},usliced{r}] = ...
        simulateSystem(x{r},u,ss{r},...
        'gradients',gradients,...
        'xLeftSeed',xLeftSeed{r},...
        'vLeftSeed',vLeftSeed{r},...
        'guessX',guessX{r},...
        'guessV',guessV{r},...
        'xRightSeed',xRightSeed{r},...
        'uRightSeed',uRightSeed,...
        'simVars',simVars{r},...
        'withAlgs',true,...
        'printCounter',printCounter,...
        'fid',fid,...
        'printRef',printRef);
end
end


function cellStructDOTfield = extracField(cellstruct,field)
	cellStructDOTfield = cellfun(@(z)z.(field),cellstruct,'UniformOutput',false);
end

function Jvar = extractJacobian(J,var)
Jvar = cellfun(@(Ji)Ji.(var) ,J,'UniformOutput',false);
end