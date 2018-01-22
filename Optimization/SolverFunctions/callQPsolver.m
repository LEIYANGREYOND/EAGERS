function [x,Feasible] = callQPsolver(QP)
if strcmp(QP.solver,'linprog') && any(any(QP.H - diag(diag(QP.H)))) %not a seperable QP problem
    QP.solver = 'quadprog';
end
if strcmp(QP.solver,'quadprog') && ~license('test','Optimization_Toolbox')
    QP.solver = 'CVX';
end
if strcmp(QP.solver,'Gurobi')%don't use gurobi for initial conditions
    QP.solver = 'quadprog';
end
if isempty(QP.f)
    x = [];
    Feasible = 1;
else
    switch QP.solver
        case 'quadprog'
        %use matlabs linprog or quadprog
        if nnz(QP.H)==0
            options = optimset('Algorithm','interior-point','MaxIter',100,'Display','none'); %,'Display','iter-detailed');% ,'TolFun',1e-10,'TolX',1e-10
            [x,~,Feasible] = linprog(QP.f,QP.A,QP.b,QP.Aeq,QP.beq,QP.lb,QP.ub,[],options); 
        else
            options = optimset('Algorithm','interior-point-convex','MaxIter',100,'Display','none');%,'TolFun',1e-10,'TolX',1e-10
            [x,~,Feasible] = quadprog(QP.H,QP.f,QP.A,QP.b,QP.Aeq,QP.beq,QP.lb,QP.ub,[],options);
            if Feasible ==0
                Feasible = 1;
%                 disp('Max iterations exceeded')
            elseif Feasible == -2 || Feasible == 3
                if ~isempty(x) && isfield(QP.Organize.Balance,'DistrictHeat')%change scale of heat vented upper bound
                    [m,n] = size(QP.organize);
                    nS = max(1,m-1);
                    req = nonzeros((1:1:length(QP.Aeq(:,1)))'.*(QP.Aeq(:,QP.Organize.HeatVented)~=0));
                    req = (req:QP.Organize.t1Balances:(req+(nS-1)*QP.Organize.t1Balances))';
                    error = QP.Aeq*x-QP.beq;
                    heatventStates = (QP.Organize.HeatVented:QP.Organize.t1States:(QP.Organize.HeatVented+(nS-1)*QP.Organize.t1States))';
                    QP.ub(heatventStates) = max(10,x(heatventStates) + 2*error(req));
                    [x,~,Feasible] = quadprog(QP.H,QP.f,QP.A,QP.b,QP.Aeq,QP.beq,QP.lb,QP.ub,[],options);
                    %error = QP.Aeq*x-QP.beq; %% can use this error to determine what energy balance is not met. can help in filter gen
                    if Feasible ==1
                        disp('Converged, but heat state needed rescaling')
                    end
                end
            end
        end
        case 'CVX'
            n = length(QP.f);
            if ~isfield(QP,'Organize') || n<24 %calculating generator cost fits
                if ~isempty (QP.lb)
                    QP.A = [QP.A;-eye(n);];
                    QP.b = [QP.b;QP.lb;];
                end
                if ~isempty (QP.ub)
                    QP.ub(isinf(QP.ub)) = 1e3*max(QP.ub(~isinf(QP.ub)));
                    QP.A = [QP.A;eye(n);];
                    QP.b = [QP.b;QP.ub;];
                end
                cvx_begin quiet
                    variable x(n) 
                    minimize (0.5*x'*QP.H*x+QP.f'*x)
                    subject to
                        QP.Aeq*x == QP.beq;
                        QP.A*x <= QP.b;
                cvx_end
            else
                %% normalize states by ub
                if ~isfield(QP.Organize,'IC')
                    ic = 0;
                else ic = max(QP.Organize.IC); %number of initial conditions. Don't need upper/lower bounds because there is an equality constraint
                end
                H = QP.H;
                f = QP.f;
                scale = QP.ub;
                scale(isinf(scale)) = 1e3*max(scale(~isinf(scale)));
                for i=1:1:n
                    if QP.ub(i)>0 %for ic = 0 do nothing
                        H(:,i) = QP.H(:,i)*scale(i)^2;
                        f(i) = QP.f(i)*scale(i);
                        if ~isempty(QP.Aeq)
                            QP.Aeq(:,i) = QP.Aeq(:,i)*scale(i);
                        end
                        if ~isempty(QP.A)
                            QP.A(:,i) = QP.A(:,i)*scale(i);
                        end
                        QP.ub(i) = 1;
                    end
                end
                %% convert quadprog form to norm
                H = (0.5*diag(H)).^0.5;
                minQcost = min(nonzeros(H));
                b = zeros(n,1);
                for i = 1:1:n
                    if QP.f(i)>0
                        if H(i)==0
                            H(i) = 1e-1*minQcost; %a very small quadratic cost so that the linear cost is not NAN
                        end
                        b(i) = f(i)/(-2*H(i));
                    end
                end
                H = diag(H);
                %add bound constraints to inequality constraint
                if ~isempty(QP.lb)
                    if isempty(QP.A)
                        QP.A = zeros(0,n);
                        QP.b = zeros(0,1);
                    end
                    I = eye(n);
                    I = I(ic+1:end,:); %remove rows that would associate with ic
                    QP.A = [QP.A; I;-I];
                    QP.b = [QP.b;QP.ub(ic+1:end);-QP.lb(ic+1:end);];
                end
    %             addpath(genpath('cvx'))
    %             if runSetup==true %if this is your first time through run the cvx setup
    %                 cvx_setup quiet
    %             end
                cvx_begin quiet
                    variable x(n) nonnegative
                    %variable y(n,n) nonnegative
                    variable onoff(n) binary
                    minimize ((norm((H*y)*x-b)))
                    subject to
                        QP.Aeq*x == QP.beq;
                        QP.A*x <= QP.b;
                        QP.lb <= x <= QP.ub;
                        y == zeros(n,n)+diag(onoff);
                cvx_end
                %% convert back to non-normalized
                x = x.*scale;
            end
            if strcmp(cvx_status,'Solved')
                Feasible = 1;
            else Feasible = -1;
            end
        case 'SPDT3'


        case 'PredictorCorrector'
            n = length(QP.f);
            %% normalize states by ub
            if ~isfield(QP.Organize,'IC')
                ic = 0;
            else ic = max(QP.Organize.IC); %number of initial conditions. Don't need upper/lower bounds because there is an equality constraint
            end
    %         scale = QP.ub;
    %         scale(isinf(scale)) = 1e3*max(scale(~isinf(scale)));
    %         for i=1:1:n
    %             if QP.ub(i)>0 %for ic = 0 do nothing
    %                 QP.H(:,i) = QP.H(:,i)*scale(i)^2;
    %                 QP.f(i) = QP.f(i)*scale(i);
    %                 if ~isempty(QP.Aeq)
    %                     QP.Aeq(:,i) = QP.Aeq(:,i)*scale(i);
    %                 end
    %                 if ~isempty(QP.A)
    %                     QP.A(:,i) = QP.A(:,i)*scale(i);
    %                 end
    %                 QP.ub(i) = 1;
    %             end
    %         end
            %add bound constraints to inequality constraint
            if ~isempty(QP.lb)
                if isempty(QP.A)
                    QP.A = zeros(0,n);
                    QP.b = zeros(0,1);
                end
                QP.ub(isinf(QP.ub)) = 1e3*max(QP.ub(~isinf(QP.ub)));%% avoid inf bounds!!
                I = [zeros(n-ic,ic),eye(n-ic)];
                QP.A = [QP.A; I;-I];
                QP.b = [QP.b;QP.ub(ic+1:end);-QP.lb(ic+1:end);];
            end
            [r,~] = size(QP.A);
            [req,~] = size(QP.Aeq);
            % initial values for states, langragian coef, and slack variables
            x = zeros(n,1);
            y = ones(req,1);
            z = ones(r,1);
            s = ones(r,1);
            [x,iterations,Feasible] = pcQPgen(QP.H,QP.f,QP.A',QP.b,QP.Aeq',QP.beq,x,y,z,s);
            %% convert back to non-normalized
    %         x = x.*scale;
    end
end
end%Ends callQPsolver