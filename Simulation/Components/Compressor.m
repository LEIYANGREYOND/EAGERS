function Out = Compressor(varargin)
% Four (4) inlets: air flow,  outlet pressure, inlet pressure, shaft RPM
% Two (2) outlets: Flow, Work input required
% Two (2) states: Tgas out and Twall
global Tags
if length(varargin)==1 % first initialization
    block = varargin{1};
    block.Ru = 8.314472; % Universal gas constant in kJ/K*kmol
    block.Tamb = 305;%ambient air temp
    block.AmbConvC = 5;%ambient convection coefficient
    block.ConvCoef = 5;%convection coefficient
    block.Epsilon = .8;%radiation epsilon value
    block.Sigma = 5.67e-8;%Radiation sigma value
    block.SpecHeat = .5;%Specific Heat of Turbine kJ/(kg*K)
    
    block.Diameter = 0.5;
    block.Length = 2;
    
    block.Volume = pi/4*block.Diameter^2*block.Length;
    block.SurfA = pi*block.Diameter*block.Length;%surface area of compressor
    
    T2s = block.Tamb*(block.Pdesign)^((1.4 -1)/1.4);
    T2a = block.Tamb+(T2s-block.Tamb)/block.PeakEfficiency;
    
    block.Scale = [T2a; T2a];%Tflow, Twall
    block.IC = ones(length(block.Scale),1);
    block.UpperBound = [inf,inf];
    block.LowerBound = [0,0];
    
    Dir=strrep(which('InitializeCompressor.m'),fullfile('Components','Initialization','InitializeCompressor.m'),'CompressorMaps');
    load(fullfile(Dir,block.Map));
    f = fieldnames(map);
    for i = 1:1:length(f)
        block.(f{i}) = map.(f{i});
    end
    Eff = map.Efficiency;
    Eff(Eff<0)=nan;
    block.minEfficiency = min(min(Eff));
    block.Efficiency(block.Efficiency<0) = block.minEfficiency;
    
    %% set up dM/dP*Pout - C*Pin = mdot
    i = find(block.RPM>=1,1);
    j = ceil(length(block.NflowGMap(i,:))/2);
    P1 = block.PressRatio(i,j);
    P2 = block.PressRatio(i,j-1);
    M1 = block.NflowGMap(i,j);
    M2 = block.NflowGMap(i,j-1);
    block.mFlow = block.FlowDesign;
    dMdP = block.FlowDesign*(M2 - M1)/(101*(block.Pdesign-1)*(P2 - P1));
    C = (dMdP*101*block.Pdesign-block.mFlow)/101;
    block.dMdP = [dMdP, C]; 

    %%
    block.InletPorts = {'FlowIn','Pin','Pout','RPMin'};
    
    block.FlowIn.IC.N2 = .79;
    block.FlowIn.IC.O2 = .21;
    block.FlowIn.IC.T = 300;
    block.FlowIn.Saturation = [0,inf];
    
    block.Pin.IC = 101;%in kPa
    block.Pin.Saturation = [0,inf];
    block.Pin.Pstate = []; %identifies the state # of the pressure state if this block has one
    
    block.Pout.IC = block.Pin.IC*block.Pdesign;%in kPa
    block.Pout.Saturation = [0,inf];
    block.Pout.Pstate = []; %identifies the state # of the pressure state if this block has one
    
    block.RPMin.IC = block.RPMdesign;
    block.RPMin.Saturation = [0,inf];
    
    block.OutletPorts = {'Flow','Work'};
    
    Mmass = MassFlow(block.FlowIn.IC);%kg/kmol
    block.Flow.IC.T = T2a;
    specname = fieldnames(block.FlowIn.IC);
    for i = 1:1:length(specname)
        if ~strcmp(specname{i},'T')
            block.Flow.IC.(specname{i}) = block.FlowIn.IC.(specname{i})*block.FlowDesign/Mmass;
        end
    end
    
    FlowIn = block.Flow.IC;
    FlowIn.T = block.Tamb;
    [~,H1] = enthalpy(FlowIn);
    [~,H2] = enthalpy(block.Flow.IC);
    block.Work.IC = H2-H1;
    
    block.P_Difference = {'Pout','Pin'};
    Out = block;
elseif length(varargin)==2 %% Have inlets connected, re-initialize
    block = varargin{1};
    Inlet = varargin{2};
    Inlet = checkSaturation(Inlet,block);
    NetFlowIn = NetFlow(Inlet.FlowIn);
    specname = fieldnames(Inlet.FlowIn);
    for i = 1:1:length(specname) %normalize flow rate in to 1
        if ~strcmp(specname{i},'T')
            Xin.(specname{i}) = Inlet.FlowIn.(specname{i})/NetFlowIn;
        end
    end
    
    Mmass = MassFlow(Inlet.FlowIn)/NetFlowIn;
    nT =Inlet.FlowIn.T/block.Tdesign;%square root of the normalized T
    nRPM =Inlet.RPMin/(block.RPMdesign*nT^.5);%normalized RPM
    CompPR =(Inlet.Pout/Inlet.Pin -1)/(block.Pdesign - 1) + 1;%normalized compressor pressure ratio
    Mscale = block.FlowDesign*(Inlet.Pin/block.P0map)/(Mmass*nT^.5);%scalar maping for mass flow
%% Find table indecies (i,j) surrounding actual value
% s and r correspond to the fractional coordinate position 
    i2 = find(block.RPM >=nRPM,1,'first');
    if isempty(i2)
        i2 = length(block.RPM);
    elseif i2==1
        i2 =2;
    end
    i1 = i2-1;
    r = (nRPM-block.RPM(i1))/(block.RPM(i2)-block.RPM(i1));
    j12 = find(block.PressRatio(i1,:)>=CompPR,1,'first');
    if isempty(j12)
        j12 = length(block.PressRatio(i1,:));
    elseif j12==1
        j12 =2;
    end
    j11 = j12-1;
    j22 = find(block.PressRatio(i2,:)>=CompPR,1,'first');
    if isempty(j22)
        j22 = length(block.PressRatio(i2,:));
    elseif j22==1
        j22 = 2;
    end
    j21 = j22-1;
    P1 = block.PressRatio(i1,j11)*r+ block.PressRatio(i2,j21)*(1-r);
    P2 = block.PressRatio(i1,j12)*r+ block.PressRatio(i2,j22)*(1-r);
    P1 = Inlet.Pin*((P1 -1)*(block.Pdesign -1) + 1);
    P2 = Inlet.Pin*((P2 -1)*(block.Pdesign -1) + 1);
    M1 = block.NflowGMap(i1,j11)*r+ block.NflowGMap(i2,j21)*(1-r);
    M2 = block.NflowGMap(i1,j12)*r+ block.NflowGMap(i2,j22)*(1-r);

    s =(nRPM - block.RPM(i1))/(block.RPM(i2) - block.RPM(i1));
    PRVec = block.PressRatio(i1,:)*(1-s) + block.PressRatio(i2,:)*s;
    if CompPR>max(PRVec) && nRPM<1
        CompPR = (Inlet.Pout/Inlet.Pin -1)*nRPM/(block.Pdesign - 1) + 1;%renormalized compressor pressure ratio
    end
    Beta = interp1(PRVec,block.Beta,CompPR,'spline');
    Nflow = interp2(block.Beta,block.RPM,block.NflowGMap,Beta,nRPM,'spline');
    Eff = interp2(block.Beta,block.RPM,block.Efficiency,Beta,nRPM,'spline')*block.PeakEfficiency;
    NetFlowOut = Nflow*Mscale;
    
    specname = fieldnames(Inlet.FlowIn);
    for i = 1:1:length(specname)
        if ~strcmp(specname{i},'T')
            FlowOut.(specname{i}) = Inlet.FlowIn.(specname{i})*NetFlowOut/NetFlowIn;
        end
    end
    
    %update dMdP and mFlow
    block.mFlow = MassFlow(FlowOut);
    block.dMdP(1,1) = Mscale*(M2 - M1)/(P2 - P1);
    block.dMdP(1,2) =  (block.dMdP(1,1)*Inlet.Pout-block.mFlow)/Inlet.Pin;
    
    
    FlowComp = FlowOut;
    FlowComp.T = Inlet.FlowIn.T;
    [~, H1] = enthalpy(FlowComp);
    T2s = Inlet.FlowIn.T*(Inlet.Pout/Inlet.Pin)^((1.4 -1)/1.4);
    FlowS = FlowComp;
    FlowS.T = T2s;
    Cp = (SpecHeat(FlowComp)+SpecHeat(FlowS))/2;
    Gamma = Cp/(Cp - block.Ru);
    T2s = Inlet.FlowIn.T*(Inlet.Pout/Inlet.Pin)^((Gamma -1)/Gamma);
    FlowS.T = T2s;
    [~,H2s] = enthalpy(FlowS);    
    
    tC = (Cp*NetFlowOut);
    FlowOut.T = T2s;
    Wall.T = (FlowOut.T + block.Tamb)/2;
    errorT =1;
    while abs(errorT)>.01 %solve for the correct outlet temperature
        [~,Hout] = enthalpy(FlowOut);
        %heat transfer
        Q_WallAmbC =(Wall.T - block.Tamb)* block.AmbConvC*block.SurfA/1000;%Convection from wall to ambient
        Q_WallAmbR =((Wall.T)^4 - (block.Tamb)^4)*block.Epsilon*block.Sigma*block.SurfA/1000;%Radiation from wall to ambient
        Q_FlowWallC =(FlowOut.T - Wall.T) * block.ConvCoef * block.SurfA/1000;%Convection from flow to wall
        
        H2a = H1+(H2s-H1)/Eff - Q_FlowWallC;
        Win = (H2a-H1) + Q_FlowWallC;   
        errorT = (H2a - Hout)/tC;
        FlowOut.T = FlowOut.T + errorT;
        Wall.T = Wall.T + (Q_FlowWallC - Q_WallAmbC - Q_WallAmbR)/tC;
    end
    block.Scale =[FlowOut.T; Wall.T]; %Tflow, Twall
    block.FlowIn.IC =Inlet.FlowIn;
    block.Flow.IC = FlowOut;
    block.Work.IC = Win;
    Out = block;
else%running the model
    t = varargin{1};
    Y = varargin{2};
    Inlet = varargin{3};
    block = varargin{4};
    string1 = varargin{5};
    
    Inlet = checkSaturation(Inlet,block);
    NetFlowIn = NetFlow(Inlet.FlowIn);
    Mmass = MassFlow(Inlet.FlowIn)/NetFlowIn;
    %compressor map
    nT =Inlet.FlowIn.T/block.Tdesign;%square root of the normalized T
    nRPM =Inlet.RPMin/(block.RPMdesign*nT^.5);%normalized RPM
    CompPR =(Inlet.Pout/Inlet.Pin -1)/(block.Pdesign - 1) + 1;%normalized compressor pressure ratio

    i2 = find(block.RPM >=nRPM,1,'first');
    if isempty(i2)
        i2 = length(block.RPM);
    elseif i2==1
        i2 =2;
    end
    i1 = i2-1;
    s =(nRPM - block.RPM(i1))/(block.RPM(i2) - block.RPM(i1));
    PRVec = block.PressRatio(i1,:)*(1-s) + block.PressRatio(i2,:)*s;
    if CompPR>PRVec(end)
    %     disp('Stall Reached')
        Beta = CompPR/PRVec(end);
        Eff = block.minEfficiency;
        flow_RPM = block.NflowGMap(i1,end)*(1-s) + block.NflowGMap(i2,end)*s;
        Nflow = 1/Beta*flow_RPM;
    else
        Beta = interp1(PRVec,block.Beta,CompPR,'spline');
        Eff = interp2(block.Beta,block.RPM,block.Efficiency,Beta,nRPM,'spline')*block.PeakEfficiency;
        Nflow = interp2(block.Beta,block.RPM,block.NflowGMap,Beta,nRPM,'spline');
    end
    %outlet flow
    NetFlowOut = Nflow*Inlet.Pin/block.P0map*block.FlowDesign/Mmass/nT^.5;
    specname = fieldnames(Inlet.FlowIn);
    for i = 1:1:length(specname)
        if ~strcmp(specname{i},'T')
            FlowOut.(specname{i}) = Inlet.FlowIn.(specname{i})*NetFlowOut/NetFlowIn;
        end
    end
    FlowOut.T = Y(1);

    %heat transfer
    Q_WallAmbC =(Y(2) - block.Tamb)* block.AmbConvC*block.SurfA/1000;%Convection from wall to ambient
    Q_WallAmbR =((Y(2))^4 - (block.Tamb)^4)*block.Epsilon*block.Sigma*block.SurfA/1000;%Radiation from wall to ambient
    Q_FlowWallC =(Y(1) - Y(2)) * block.ConvCoef * block.SurfA/1000;%Convection from flow to wall

    %energy balance
    Cp = (SpecHeat(Inlet.FlowIn)+SpecHeat(FlowOut))/2;
    Gamma = Cp/(Cp - block.Ru);
    T2s = Inlet.FlowIn.T*(Inlet.Pout/Inlet.Pin)^((Gamma -1)/Gamma);

    FlowComp = FlowOut;
    FlowComp.T = Inlet.FlowIn.T;
    [~, H1] = enthalpy(FlowComp);
    FlowS = FlowComp;
    FlowS.T = T2s;
    [~,H2s] = enthalpy(FlowS);

    H2a = H1+(H2s-H1)/Eff - Q_FlowWallC;
    Win = (H2a-H1) + Q_FlowWallC;

    if strcmp(string1,'Outlet')
        Out.Flow = FlowOut;
        Out.Work = Win;
        Tags.(block.name).NRPM = nRPM;
        Tags.(block.name).Beta = Beta;
        Tags.(block.name).Flow = FlowOut;
        Tags.(block.name).Power = Win;
        Tags.(block.name).PR = Inlet.Pout/Inlet.Pin;
        Tags.(block.name).Nflow = Nflow;
        Tags.(block.name).MassFlow = MassFlow(FlowOut);
        Tags.(block.name).Temperature = Y(1);
        Tags.(block.name).Eff = Eff;
        Tags.(block.name).nMflow = MassFlow(FlowOut)/block.FlowDesign;
        Tags.(block.name).Pressure = Inlet.Pout;
    elseif strcmp(string1,'dY')
        dY = 0*Y;
        [~, Hout] = enthalpy(FlowOut);
        dY(1) = (H2a-Hout)*block.Ru*Y(1)/(Inlet.Pout*block.Volume*Cp); %dT = dQ / n Cp
        dY(2) = (Q_FlowWallC - Q_WallAmbC - Q_WallAmbR)/(block.Mass*block.SpecHeat);
        Out = dY;
    end
end
end%Ends function Compressor
