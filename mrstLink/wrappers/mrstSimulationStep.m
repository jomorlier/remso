function [  shootingSol,Jacs,convergence ] = mrstSimulationStep( shootingVars,reservoirP,varargin)
%
%  MRST simulator function
%


opt = struct('shootingGuess',[],'force_step',false,'stop_if_not_converged',false);
opt = merge_options(opt, varargin{:});

[shootingSol.wellSols,shootingSol.ForwardStates,shootingSol.schedule,~,convergence,Jac] = runScheduleADI(shootingVars.state0,...
                                                                                reservoirP.G,...
                                                                                reservoirP.rock,...
                                                                                reservoirP.system,...
                                                                                shootingVars.schedule,...
                                                                                'stop_if_not_converged', opt.stop_if_not_converged, ...
                                                                                'initialGuess',opt.shootingGuess,'force_step',opt.force_step;


end

