%% SOFC stack fed with a pure O2 cathode. Indirect internal reforming manages the internal temperature
function Plant = OxyFC
global SimSettings
SimSettings.NominalPower= 300;
Reformer = 'internal'; % options are 'internal' for indirect internal reforming, 'direct' for direct internal reforming, 'adiabatic' for external reforming using the heat from the anode (over-rides S2C ratio),'external' for an external reformer with heat captured from oxidixed anode exhaust, 'pox' partial oxidation reformer

Steam2Carbon = 2.0;
Oxidant.O2 = 1;

Fuel.CH4 = 0.9;
Fuel.CO = 0.04;
Fuel.CO2 = 0.04;
Fuel.H2 = 0;
Fuel.H2O = 0;
Fuel.N2 = 0.02;

%% Components
Plant.Components.O2Source.type = 'Source'; 
Plant.Components.O2Source.name = 'O2Source';
Plant.Components.O2Source.InitialComposition = Oxidant;
Plant.Components.O2Source.connections = {930;'';'Controller.OxidantFlow';};

Plant.Components.FuelSource.type = 'Source';
Plant.Components.FuelSource.name = 'FuelSource';
Plant.Components.FuelSource.InitialComposition = Fuel;
Plant.Components.FuelSource.connections = {300;'';'Controller.FuelFlow';};

S2C = Fuel.H2O/(Fuel.CH4+.5*Fuel.CO);
if S2C<Steam2Carbon %add anode recirculation
    FCexit.CH4 = .0001;
    FCexit.CO = .0999;
    FCexit.CO2 = .25;
    FCexit.H2 = .1;
    FCexit.H2O = .54;
    FCexit.N2 = .01;

    PartiallyRef.CH4 = .07;
    PartiallyRef.CO = .07;
    PartiallyRef.CO2 = .07;
    PartiallyRef.H2 = .5;
    PartiallyRef.H2O = .28;
    PartiallyRef.N2 = .01;
    
    %recircValve
    Plant.Components.recircValve.type = 'Valve3Way';
    Plant.Components.recircValve.name = 'recircValve';
    Plant.Components.recircValve.InitialFlowIn = FCexit;
    Plant.Components.recircValve.InitialFlowIn.T = 1050;
    Plant.Components.recircValve.connections = {'FC1.Flow2Out','Controller.AnodeRecirc'};
    Plant.Components.recircValve.PercOpen = 0.5; %INITIAL valve position

    %Mixing
    Plant.Components.Mix1.type = 'MixingVolume';
    Plant.Components.Mix1.name = 'Mix1';
    Plant.Components.Mix1.Vol = 0.1;
    Plant.Components.Mix1.inlets = 2;
    Plant.Components.Mix1.SpeciesInit = PartiallyRef;
    Plant.Components.Mix1.Tinit = 800;
    Plant.Components.Mix1.connections = {'FuelSource.Outlet';'recircValve.Out1';'FC1.Flow2Pin'};
    Plant.Components.Mix1.TagInf = {'MassFlow';'Temperature';};
end

%Fuel Cell
Plant.Components.FC1.type = 'FuelCell';
Plant.Components.FC1.name = 'FC1';
Plant.Components.FC1.FCtype = 'SOFC'; %SOFC, or MCFC 
Plant.Components.FC1.Reformer = Reformer;
Plant.Components.FC1.direction = 'coflow'; % 'coflow', or 'counterflow' or 'crossflow'
Plant.Components.FC1.ClosedCathode = 1; %0 means air or some excess flow of O2 in the cathode used as primary means of temerature control (initializations hold to design fuel utilization), 1 means closed end cathode, or simply a fixed oxygen utilization, cooling is done with excess fuel, and the design voltage is met during initialization
Plant.Components.FC1.CoolingStream = 'anode'; % choices are 'anode' or 'cathode'. Determines which flow is increased to reach desired temperature gradient.
Plant.Components.FC1.Mode = 'fuelcell'; % options are 'fuelcell' or 'electrolyzer'
Plant.Components.FC1.PressureRatio = 1.2;
Plant.Components.FC1.columns = 5;
Plant.Components.FC1.rows = 1;
Plant.Components.FC1.RatedStack_kW = 300; %Nominal Stack Power in kW
Plant.Components.FC1.Flow1Spec = Oxidant;
Plant.Components.FC1.Flow2Spec = Fuel; %initial fuel composition at inlet
Plant.Components.FC1.Steam2Carbon = Steam2Carbon; %steam to carbon ratio that fuel or recirculaton is controlled to
Plant.Components.FC1.method = 'Achenbach'; %Determines reforming reaction kinetics options: 'Achenbach' , 'Leinfelder' , 'Drescher'   
Plant.Components.FC1.L_Cell= .09;  %Cell length in meters
Plant.Components.FC1.W_Cell = .09;  %Cell Width in meters  
Plant.Components.FC1.Specification = 'voltage'; %options are 'cells', 'power density', 'voltage', or 'current density'. Note: careful when specifying cells that it arrives at a feasible power density
Plant.Components.FC1.SpecificationValue = 0.86; % power density specified in mW/cm^2, voltage specified in V/cell, current density specified in A/cm^2
Plant.Components.FC1.deltaTStack = 50; %temperature difference from cathode inlet to cathode outlet
Plant.Components.FC1.TpenAvg = 1023;% 750 C, average electrolyte operating temperature
Plant.Components.FC1.Utilization_Flow2 = Plant.Components.FC1.SpecificationValue*1.6 - .728;% ; %fuel utilization (net hydrogen consumed/ maximum hydrogen produced with 100% Co and CH4 conversion (initial guess, will be iterated)
Plant.Components.FC1.Flow1Pdrop = 10; %design pressure drop
Plant.Components.FC1.Flow2Pdrop = 2; %Design  pressure drop
Plant.Components.FC1.Map = 'SOFC_map'; %Radiative heat transfer view factors, imported from CAD
switch Reformer
    case {'direct';'internal'}
        Plant.Components.FC1.AnPercEquilib = 1; %CH4 reforming reaches equilibrium at anode exit.
        if S2C<Steam2Carbon %add anode recirculation
            Plant.Components.FC1.connections = {'Controller.Current';'O2Source.Outlet';'Mix1.Outlet';'';'';};
        else
            Plant.Components.FC1.connections = {'Controller.Current';'O2Source.Outlet';'FuelSource.Outlet';'';'';};
        end
        if strcmp(Reformer,'internal')
            Plant.Components.FC1.RefPerc = 0.75;% necessary for internal reformer, proportion of CH4 reforming in the reforming channels
            Plant.Components.FC1.RefSpacing = 1;% necessary for internal reformer. This is the # of active cells between reformer plates
        end
end

Plant.Components.FC1.TagInf = {'Power';'Current';'Voltage';'PENavgT';'StackdeltaT';'H2utilization';'O2utilization';'LocalNernst';};
Plant.Components.FC1.TagFinal = {'Power';'Current';'Voltage';'PENavgT';'StackdeltaT';'H2utilization';'O2utilization';};

%Controller
Plant.Controls.Controller.type = 'ControlFCstack';
Plant.Controls.Controller.name = 'Controller';
Plant.Controls.Controller.Target = {'FC1.TpenAvg';'FC1.deltaTStack';'FC1.Steam2Carbon';SimSettings.NominalPower;};
Plant.Controls.Controller.OxyFC = true;
Plant.Controls.Controller.Oxidant_IC = 'FC1.Flow1.IC';
Plant.Controls.Controller.OxidantUtilization = 'FC1.Utilization_Flow1';
Plant.Controls.Controller.Fuel = Fuel;
Plant.Controls.Controller.FuelFlow = 'FC1.Flow2.IC';
Plant.Controls.Controller.AnodeRecirc = 'FC1.Recirc.Flow2';
Plant.Controls.Controller.Cells = 'FC1.Cells';
Plant.Controls.Controller.Gain = [0;2e-3;1e-2];
Plant.Controls.Controller.PropGain = [0;.5;1];
Plant.Controls.Controller.TagInf = {'OxidantFlow';'OxidantTemp';'FuelFlow';'Current';'Recirculation';'Power';'AverageTemperature';};
Plant.Controls.Controller.connections = {'';'';'';'PowerDemandLookup';'FC1.MeasureTflow2';'FC1.MeasureVoltage';};

Plant.Scope = {'Controller.FuelFlow';'Controller.Current';'Controller.Recirculation';'Controller.Power';'FC1.Voltage';'Controller.AverageTemperature';'FC1.H2utilization';'FC1.LocalNernst';}; %must be in TagInf of the corresponding block to work here
Plant.Plot = [Plant.Scope;{'FC1.StackdeltaT';'FC1.PENavgT';'FC1.Voltage';'FC1.LocalNernst';}];