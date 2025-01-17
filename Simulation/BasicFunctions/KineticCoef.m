function [block,MixedFlow,Flow2,Flow3] = KineticCoef(block,Inlet,first,count)
%% find the kinetic coefficient which results in the net reforming determined by equilibrium
H2consume = sum(block.Current.H2)/(2*96485.339*1000);
COconsume = sum(block.Current.CO)/(2*96485.339*1000);

switch block.Reformer
    case {'internal'}
        if sum(H2consume)+sum(COconsume)>0%fuel cell mode with reformer
            CH4max = min(Inlet.Mixed.CH4,Inlet.Mixed.H2O);
            CH4min = -min(Inlet.Mixed.CO,((Inlet.Mixed.H2 + Inlet.Mixed.CO)/4));
            X0guessRef = (sum(block.R_CH4ref)*block.Cells/block.RefSpacing/block.RefPerc - CH4min)/(CH4max -CH4min);
            X0guessRef = max(min(X0guessRef,(1-1e-5)),1e-5);
            X0guess = max(min(block.AnPercEquilib,(1-1e-5)),1e-5);
        else
            %electrolyzer mode with methanator
        end
    case {'direct','adiabatic','external'}
        CH4max = min(Inlet.Mixed.CH4,Inlet.Mixed.H2O);
        CH4min = -min(Inlet.Mixed.CO-COconsume,((Inlet.Mixed.H2 + Inlet.Mixed.CO - (H2consume+COconsume))/4));
        X0guess = (sum(block.R_CH4)*block.Cells/block.AnPercEquilib - CH4min)/(CH4max -CH4min);
        X0guess = max(min(X0guess,(1-1e-5)),1e-5);
end

%% Find equilibrium at outlet
Tout = mean(block.T.Flow2(block.Flow2Dir(:,end)));
MixedFlow = Inlet.Mixed;%revise this inlet as you calculate the anode recirculation 
if first && any(strcmp(block.Reformer,{'internal';'direct'}))  %only first time through when calculating anode recirculation
    if MixedFlow.H2O/(MixedFlow.CH4 +.5*MixedFlow.CO) <0.9*block.Steam2Carbon
        MixedFlow.H2O = block.Steam2Carbon*(MixedFlow.CH4+.5*MixedFlow.CO);
    end
    Flow2Out.T = Tout;
    count2 = 0;
    Tol = 1e-3;
    RCH4old =0;
    Rnet.CH4 = sum(block.R_CH4);
    while abs((Rnet.CH4-RCH4old)/Rnet.CH4)>Tol
        RCH4old = Rnet.CH4;
        if strcmp(block.Reformer,'internal')
            block.RefPlates = block.Cells/block.RefSpacing;
            RefInlet = MixedFlow;
            RefOutlet.T = mean(block.T.Flow3(block.Flow3Dir(:,end)));
            [RefOutlet,Rref_net] = equilib2D(RefInlet,RefOutlet.T,block.Flow2_Pinit,0,0,block.FCtype,block.RefPerc,X0guessRef);
            Flow2Inlet = RefOutlet;
        else
            Flow2Inlet = MixedFlow;
            Flow3 =[];
        end
        [Flow2Out,Rnet] = equilib2D(Flow2Inlet,Flow2Out.T,block.Flow2_Pinit,H2consume*block.Cells,COconsume*block.Cells,block.FCtype,block.AnPercEquilib,X0guess);
        errorR = 1;
        while abs(errorR)>1e-5 %% loop to find anode recirculation that meets steam2carbon design
            for i = 1:1:length(block.Spec2)
                MixedFlow.(block.Spec2{i}) = Inlet.Flow2.(block.Spec2{i}) + block.Recirc.Flow2*Flow2Out.(block.Spec2{i});
            end
            S2Ccheck = MixedFlow.H2O/(MixedFlow.CH4+.5*MixedFlow.CO);
            errorR = (block.Steam2Carbon-S2Ccheck)/block.Steam2Carbon;
            block.Recirc.Flow2 = block.Recirc.Flow2*(1+.9*errorR);
        end
        %%find resulting temperature of mixture
        errorT = 1;
        Hin = enthalpy(Inlet.Flow2);
        Hout = enthalpy(Flow2Out);
        Hnet = Hin + block.Recirc.Flow2*Hout;
        Cp = SpecHeat(Flow2Out);
        NetFlowMix = NetFlow(MixedFlow);
        while abs(errorT)>1e-3
            Hmix = enthalpy(MixedFlow);
            errorT = (Hnet-Hmix)/(Cp*NetFlowMix);
            MixedFlow.T = MixedFlow.T + errorT;
        end  
        count2 = count2+1;
    end
else
    if strcmp(block.Reformer,'internal')
        block.RefPlates = block.Cells/block.RefSpacing;
        RefInlet = MixedFlow;
        RefOutlet.T = mean(block.T.Flow3(block.Flow3Dir(:,end)));
        [RefOutlet,Rref_net] = equilib2D(RefInlet,RefOutlet.T,block.Flow2_Pinit,0,0,block.FCtype,block.RefPerc,X0guessRef);
        Flow2Inlet = RefOutlet;
    else
        Flow2Inlet = MixedFlow;
        Flow3 =[];
    end
    [~,Rnet] = equilib2D(Flow2Inlet,Tout,block.Flow2_Pinit,H2consume*block.Cells,COconsume*block.Cells,block.FCtype,block.AnPercEquilib,X0guess);
end

% %% From running equilibrium function I can calculate exponential fit to WGS equilibrium: K_WGS = exp(4189.8./T -3.8242) : slightly different than in Paradis paper

%% Indirect Reformer
switch block.Reformer
    case 'internal'
        if first && count
            X_CH4in = RefInlet.CH4/NetFlow(RefInlet);
            X_CH4out = (RefInlet.CH4-Rref_net.CH4)/(NetFlow(RefInlet)+2*Rref_net.CH4);
            lambda = log(X_CH4out/X_CH4in)/(-block.columns); %exponential decay in CH4
            R_cumulative = zeros(length(block.Flow3Dir(:,1)),1);
            XCH4 = zeros(block.nodes,1);
            for i= 1:1:block.columns
                k = block.Flow3Dir(:,i);
                XCH4(k) = X_CH4in*exp(-i*lambda);
                if i == 1 % R = (in flow - outflow) = (Xin*flowin + Xout*(flowin +2*R)) solved for R
                    R.CH4(k,1) = (RefInlet.CH4/length(k) - XCH4(k).*(NetFlow(RefInlet)/length(k) +2*R_cumulative))./(1+2*XCH4(k));
                    R_cumulative = R_cumulative+R.CH4(k);
                else
                    R.CH4(k,1) = (XCH4(kold) - XCH4(k)).*(NetFlow(RefInlet)/length(k)+2*R_cumulative)./(1+2*XCH4(k));
                    R_cumulative = R_cumulative+R.CH4(k);
                end
                kold = k;
            end
            R.WGS = Rref_net.WGS/Rref_net.CH4*R.CH4; %assume same initial distribution for WGS reaction
        else
            for r = 1:1:block.rows 
                k_r = block.Flow3Dir(r,:);
                R.CH4(k_r,1) = block.R_CH4ref(k_r)*(Rref_net.CH4/block.rows)/sum(block.R_CH4ref(k_r));%make sure the total reforming is correct.
                R.WGS(k_r,1) = block.R_WGSref(k_r)*(Rref_net.WGS/block.rows)/sum(block.R_WGSref(k_r)); %assume same initial distribution for WGS reaction
            end
        end
        R.CH4 = R.CH4/block.RefPlates;
        R.WGS = R.WGS/block.RefPlates;
        RefCurrent.H2 = zeros(length(R.CH4),1);
        RefCurrent.CO = zeros(length(R.CH4),1);
        [R, Flow3, K] = FindKineticCoef(RefInlet,block.T.Flow3,R,block.Flow3Dir,Rref_net.CH4/block.RefPlates,RefCurrent,block.Flow2_Pinit,block.FCtype,block.RefPlates,block.method,1e-5);
        block.KineticCoeff3 = K;
        block.R_CH4ref = R.CH4;
        block.R_WGSref = R.WGS;  
end
%% Anode Reforming
if first && count
    X_CH4in = Flow2Inlet.CH4/NetFlow(Flow2Inlet);
    X_CH4out = (Flow2Inlet.CH4-Rnet.CH4)/(NetFlow(Flow2Inlet)+2*Rnet.CH4);
    lambda = log(X_CH4out/X_CH4in)/(-block.columns); %exponential decay in CH4
    R_cumulative = zeros(length(block.Flow2Dir(:,1)),1);
    XCH4 = zeros(block.nodes,1);
    for i= 1:1:block.columns
        k = block.Flow2Dir(:,i);
        XCH4(k) = X_CH4in*exp(-i*lambda);
        if i == 1 % R = (in flow - outflow) = (Xin*flowin + Xout*(flowin +2*R)) solved for R
            R.CH4(k,1) = (Flow2Inlet.CH4/length(k) - XCH4(k).*(NetFlow(Flow2Inlet)/length(k) +2*R_cumulative))./(1+2*XCH4(k));
            R_cumulative = R_cumulative+R.CH4(k);
        else
            R.CH4(k,1) = (XCH4(kold) - XCH4(k)).*(NetFlow(Flow2Inlet)/length(k) + 2*R_cumulative)./(1+2*XCH4(k));
            R_cumulative = R_cumulative+R.CH4(k);
        end
        kold = k;
    end
    R.WGS = Rnet.WGS/Rnet.CH4*R.CH4; %assume same initial distribution for WGS reaction
else
    R.CH4 = block.R_CH4*Rnet.CH4/sum(block.R_CH4); %keep same disribution as last time, but make the sum equal to the global calculation
    R.WGS = block.R_WGS*Rnet.WGS/sum(block.R_WGS); %assume same initial distribution for WGS reaction
end
R.CH4 = R.CH4/block.Cells;
R.WGS = R.WGS/block.Cells;
[R, Flow2, K] = FindKineticCoef(Flow2Inlet,block.T.Flow2,R,block.Flow2Dir,Rnet.CH4/block.Cells,block.Current,block.Flow2_Pinit,block.FCtype,block.Cells,block.method,1e-5);
block.KineticCoeff1 = K;
block.R_CH4 = R.CH4;
block.R_WGS = R.WGS;
end%Ends function KineticCoef

function [R, Flow, KinCoef] = FindKineticCoef(Inlet,T_Out,R, Dir, referenceR_CH4,Current,Pressure,Type,Cells,method,Tol)
F=96485.339; % %Faraday's constant in Coulomb/mole
Ru = 8.314472; % Universal gas constant in kJ/K*kmol
specInterest = {'CH4','CO','CO2','H2','H2O'};
[m,~] = size(Dir);
for i = 1:1:m
    if sum(R.CH4(Dir(i,:)))>Inlet.CH4/(m*Cells)
        R.CH4(Dir(i,:)) = R.CH4(Dir(i,:))*(1-1e-7)*(Inlet.CH4/(m*Cells)/sum(R.CH4(Dir(i,:))));
    end
end
Flow = FCin2Out(T_Out,Inlet,Dir,Type,Cells,Current,R,'Flow2');
nout = NetFlow(Flow.Outlet);
X_CH4 = max(0,Flow.Outlet.CH4./nout*Pressure*1000); %partial pressures in Pa
X_H2O = Flow.Outlet.H2O./nout*Pressure*1000; %partial pressures in Pa

r = length(Dir(:,1));%rows
if strcmp(method,'Achenbach')
    KinCoef = R.CH4./(X_CH4.*exp(-8.2e4./(Ru*T_Out))); %best guess of KinCoef
elseif strcmp(method,'Leinfelder')
    KinCoef = R.CH4./(X_CH4.*30.8e10*X_H2O.*exp(-2.05e5./(Ru*T_Out)));
elseif strcmp(method,'Drescher')
    KinCoef = R.CH4./(X_CH4.*288.52*X_H2O.*exp(-1.1e4./(Ru*T_Out(Dir(:,1))))/(1+16*X_CH4+0.143*X_H2O.*exp(3.9e4./(Ru*T_Out))));
end
KinCoef(KinCoef==inf) = 0;
KinCoef = sum(KinCoef.*R.CH4/referenceR_CH4);

eK = 0.25*KinCoef;
spec = fieldnames(Inlet);
count = 0;
error = 1;   
while abs(error)>Tol %iterate to converge on a kinetic coefficients (if less CH4 in exhaust than equilibrium, smaller coefficient)
    count = count+1;
    [R_CH4a,valid1] = loopConverge(Flow,R,T_Out,Pressure,KinCoef,Dir,method);
    while ~valid1 %to large of a coefficient, reforming more than available CH4
        KinCoef = 0.9*KinCoef;
        [R_CH4a,valid1] = loopConverge(Flow,R,T_Out,Pressure,KinCoef,Dir,method);
    end
    error = (sum(R_CH4a)-referenceR_CH4)/referenceR_CH4;
    if error>0
        eK = -0.25*abs(eK);
    else eK = 0.25*abs(eK);
    end
    [R_CH4b,valid2] = loopConverge(Flow,R,T_Out,Pressure,KinCoef+eK,Dir,method);
    while ~valid2
        eK = 0.25*eK;
        [R_CH4b,valid2] = loopConverge(Flow,R,T_Out,Pressure,KinCoef+eK,Dir,method);
    end
    error2 = (sum(R_CH4b)-referenceR_CH4)/referenceR_CH4;
    eK = min(.5*KinCoef,max(-.5*KinCoef,error/(error-error2)*(eK)));
    KinCoef = KinCoef+eK;
    R.CH4 = loopConverge(Flow,R,T_Out,Pressure,KinCoef,Dir,method);

    R_CH4max = (1-1e-10)*min(Flow.Inlet.CH4,Flow.Inlet.H2O);
    R.CH4 = min(R.CH4,R_CH4max);
    
    %% update WGS to equilibrium assuming this rate of reforming
    for j= 1:1:length(Dir(1,:))
        k = Dir(:,j);
        if j == 1
            X.CH4 = Inlet.CH4/Cells/r - R.CH4(k);
            X.CO = Inlet.CO/Cells/r + R.CH4(k) - Current.CO(k)/(2*F*1000);
            X.CO2 = Inlet.CO2/Cells/r + Current.CO(k)/(2*F*1000);
            X.H2 = Inlet.H2/Cells/r + 3*R.CH4(k) - Current.H2(k)/(2*F*1000);%hydrogen consumed
            X.H2O = Inlet.H2O/Cells/r - R.CH4(k) + Current.H2(k)/(2*F*1000);% water produced
            if strcmp(Type,'MCFC')
                X.CO2 = X.CO2 + (Current.H2(k)+Current.CO(k))/(2*F*1000); % CO2 brought over
            end
            for i = 1:1:length(spec)
                if ~ismember(spec{i},specInterest)
                    X.(spec{i}) = Inlet.(spec{i})/Cells/r;
                end
            end
        else
            X.CH4 = X.CH4 - R.CH4(k);
            X.CO = X.CO + R.CH4(k) - Current.CO(k)/(2*F*1000);
            X.CO2 = X.CO2 + Current.CO(k)/(2*F*1000);
            X.H2 = X.H2 + 3*R.CH4(k) - Current.H2(k)/(2*F*1000);%hydrogen consumed
            X.H2O = X.H2O - R.CH4(k) + Current.H2(k)/(2*F*1000);% water produced
            if strcmp(Type,'MCFC')
                X.CO2 = X.CO2 + (Current.H2(k)+Current.CO(k))/(2*F*1000); % CO2 brought over
            end
        end

        R_COmin = -min(X.CO2,X.H2);
        R_COmax = min(X.H2O,X.CO);
        y0 = max(0+1e-5,min(1-1e-5,(R.WGS(k)-R_COmin)./(R_COmax-R_COmin)));
        
        y0 = Newton1D(y0,X,R_COmin,R_COmax,T_Out(k),Pressure,specInterest,1e-6,'GibbVal');

        R.WGS(k) = R_COmin+y0.*(R_COmax-R_COmin);
        X.CO = X.CO-R.WGS(k);
        X.CO2 = X.CO2+R.WGS(k);
        X.H2 = X.H2+R.WGS(k);
        X.H2O = X.H2O-R.WGS(k);
    end
    Flow = FCin2Out(T_Out,Inlet,Dir,Type,Cells,Current,R,'Flow2');
    if count > 6
        Tol = 5e-4;
    end
%     if count > 10
%         disp('Trouble converging FindKineticCoef function')
%     end
end
% disp(strcat('FindKineticCoef count is:',num2str(count)))
end%Ends function FindKineticCoef

function [R_CH4,valid] = loopConverge(Flow,R,T_Out,Pressure,KinCoef,Dir,method)
Ru = 8.314472; % Universal gas constant in kJ/K*kmol
valid = 1;
%% find new reforming reaction rates
k = Dir(:,1);
n_in = NetFlow(Flow.Inlet);
n_in = n_in(k);
H2O_in = Flow.Inlet.H2O(k);
X_CH4in = Flow.Inlet.CH4(k)./n_in;
nout = NetFlow(Flow.Outlet);
X_CH4 = Flow.Outlet.CH4./nout;%initial guess of X_CH4
for j= 1:1:length(Dir(1,:))
    k = Dir(:,j);
    if strcmp(method,'Achenbach')
        C = exp(-8.2e4./(Ru*T_Out(k)));
    elseif strcmp(method,'Leinfelder')
        X_H2O = (H2O_in - R.CH4(k) - R.WGS(k))./(n_in+2*R.CH4(k))*Pressure*1000; %partial pressures in Pa
        C = 30.8e10*X_H2O.*exp(-2.05e5./(Ru*T_Out(k)));
    elseif strcmp(method,'Drescher')
        X_H2O = (H2O_in - R.CH4(k) - R.WGS(k))./(n_in+2*R.CH4(k))*Pressure*1000; %partial pressures in Pa
        C = 288.52*X_H2O.*exp(-1.1e4./(Ru*T_Out))./(1+16*X_CH4(k)*Pressure*1000+0.143*X_H2O.*exp(3.9e4./(Ru*T_Out(k))));
    end

    % use newton method to find X_CH4_out that makes R.CH4 so that R = X_CH4 in *flow in - X_CH4out*flow out
    dX1 = (X_CH4in.*n_in - KinCoef.*X_CH4(k)*Pressure*1000.*C)./(n_in + 2*KinCoef*X_CH4(k)*Pressure*1000.*C) - X_CH4(k);
    eX = 1e-5*X_CH4in;
    dX2 = (X_CH4in.*n_in - KinCoef.*(X_CH4(k)+eX)*Pressure*1000.*C)./(n_in + 2*KinCoef*(X_CH4(k)+eX)*Pressure*1000.*C) - (X_CH4(k)+eX);
    m = (dX2-dX1)./eX;
    b = dX1 - m.*X_CH4(k);
    X_CH4(k) = - b./m; 
    
    R.CH4(k) = KinCoef*X_CH4(k)*Pressure*1000.*C;
    if any(R.CH4(k)>(X_CH4in.*n_in))
        R.CH4(k)=min(R.CH4(k),(1-1e-8)*(X_CH4in.*n_in));
        valid = 0;
    end
    %inlet to the next column
    X_CH4in = (X_CH4in.*n_in - R.CH4(k))./(n_in + 2*R.CH4(k));
    H2O_in = H2O_in - R.CH4(k) - R.WGS(k);
    n_in = n_in + 2*R.CH4(k);
%     errorJ = (X_CH4(k) - X_CH4in)./X_CH4in; %remaining error after 1 newton step
end
R_CH4 = R.CH4;
end%Ends function loopConverge