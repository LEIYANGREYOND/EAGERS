function Timers(options)
mpcTimer     = timer('TimerFcn'  ,@MPCloop, ...
                   'StartDelay'   , 0            , ...
                   'Period'       , options.Tmpc/options.scaleTime, ...
                   'Name'         ,'mpcTimer' , ...
                   'ExecutionMode','fixedrate'        );
optTimer     = timer('TimerFcn'  ,@OnlineLoop, ...
                   'StartDelay'   , options.Topt/options.scaleTime, ...
                   'Period'       , options.Topt/options.scaleTime, ...
                   'Name'         ,'optTimer' , ...
                   'ExecutionMode','fixedrate'        );
dispTimer     = timer('TimerFcn'  ,@DispatchLoop, ...
                   'StartDelay'   , options.Resolution*3600/options.scaleTime, ...
                   'Period'       , options.Resolution*3600/options.scaleTime, ...
                   'Name'         ,'dispTimer' , ...
                   'ExecutionMode','fixedrate'        );
%% start all timers
start(mpcTimer);
start(optTimer);
start(dispTimer);

%% for Genoa Only
% fanTimer     = timer('TimerFcn'  ,@writeThermalLoad, ...
%                    'StartDelay'   , 0            , ...
%                    'Period'       , options.Tmpc/options.scaleTime, ...
%                    'Name'         ,'fanTimer' , ...
%                    'ExecutionMode','fixedrate'        );
% start(fanTimer);