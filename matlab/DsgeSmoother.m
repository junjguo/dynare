function [alphahat,etahat,epsilonhat,ahat,SteadyState,trend_coeff,aK,T,R,P,PK,d,decomp] = DsgeSmoother(xparam1,gend,Y)
% Estimation of the smoothed variables and innovations. 
% 
% INPUTS 
%   o xparam1       [double]   (p*1) vector of (estimated) parameters. 
%   o gend          [integer]  scalar specifying the number of observations ==> varargin{1}.
%   o data          [double]   (T*n) matrix of data.
%  
% OUTPUTS 
%   o alphahat      [double]  (m*T) matrix, smoothed endogenous variables.
%   o etahat        [double]  (r*T) matrix, smoothed structural shocks (r>n is the umber of shocks).
%   o epsilonhat    [double]  (n*T) matrix, smoothed measurement errors.
%   o ahat          [double]  (m*T) matrix, one step ahead filtered (endogenous) variables.
%   o SteadyState   [double]  (m*1) vector specifying the steady state level of each endogenous variable.
%   o trend_coeff   [double]  (n*1) vector, parameters specifying the slope of the trend associated to each observed variable.
%   o aK            [double]  (K,n,T+K) array, k (k=1,...,K) steps ahead filtered (endogenous) variables.
%   o T and R       [double]  Matrices defining the state equation (T is the (m*m) transition matrix).
%    P:             3D array of one-step ahead forecast error variance
%                   matrices
%    PK:            4D array of k-step ahead forecast error variance
%                   matrices (meaningless for periods 1:d)
%    d:             number of periods where filter remains in diffuse part
%                  (should be equal to the order of integration of the model)
%    
% ALGORITHM 
%   Diffuse Kalman filter (Durbin and Koopman)       
%
% SPECIAL REQUIREMENTS
%   None

% Copyright (C) 2006-2008 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

  global bayestopt_ M_ oo_ estim_params_ options_

  alphahat 	= [];
  etahat	= [];
  epsilonhat	= [];
  ahat          = [];
  SteadyState   = [];
  trend_coeff   = [];
  aK            = [];
  T             = [];
  R             = [];
  P             = [];
  PK            = [];
  d             = [];
  decomp        = [];
  nobs 		= size(options_.varobs,1);
  smpl          = size(Y,2);

  set_all_parameters(xparam1);

  %------------------------------------------------------------------------------
  % 2. call model setup & reduction program
  %------------------------------------------------------------------------------
  [T,R,SteadyState] = dynare_resolve;
  bayestopt_.mf = bayestopt_.mf2;
  if options_.noconstant
      constant = zeros(nobs,1);
  else
      if options_.loglinear == 1
          constant = log(SteadyState(bayestopt_.mfys));
      else
          constant = SteadyState(bayestopt_.mfys);
      end
  end
  trend_coeff = zeros(nobs,1);
  if bayestopt_.with_trend == 1
    trend_coeff = zeros(nobs,1);
    t = options_.trend_coeffs;
    for i=1:length(t)
      if ~isempty(t{i})
	trend_coeff(i) = evalin('base',t{i});
      end
    end
    trend = constant*ones(1,gend)+trend_coeff*(1:gend);
  else
    trend = constant*ones(1,gend);
  end
  start = options_.presample+1;
  np    = size(T,1);
  mf    = bayestopt_.mf;
  % ------------------------------------------------------------------------------
  %  3. Initial condition of the Kalman filter
  % ------------------------------------------------------------------------------
  % 
  %  C'est ici qu'il faut d�terminer Pinf et Pstar. Si le mod�le est stationnaire,
  %  alors il suffit de poser Pstar comme la solution de l'�uation de Lyapounov et
  %  Pinf=[].
  %
  Q = M_.Sigma_e;
  H = M_.H;
  
  kalman_algo = options_.kalman_algo;
  if options_.lik_init == 1		% Kalman filter
      if kalman_algo ~= 2
          kalman_algo = 1;
      end
      Pstar = lyapunov_symm(T,R*Q*transpose(R),options_.qz_criterium);
      Pinf	= [];
  elseif options_.lik_init == 2 % Old Diffuse Kalman filter
      if kalman_algo ~= 2
          kalman_algo = 1;
      end
      Pstar = 10*eye(np);
      Pinf	= [];
  elseif options_.lik_init == 3 % Diffuse Kalman filter
      if kalman_algo ~= 4
          kalman_algo = 3;
      end
      [QT,ST] = schur(T);
      if exist('OCTAVE_VERSION') || matlab_ver_less_than('7.0.1')
          e1 = abs(my_ordeig(ST)) > 2-options_.qz_criterium;
      else
          e1 = abs(ordeig(ST)) > 2-options_.qz_criterium;
      end
      [QT,ST] = ordschur(QT,ST,e1);
      if exist('OCTAVE_VERSION') || matlab_ver_less_than('7.0.1')
          k = find(abs(my_ordeig(ST)) > 2-options_.qz_criterium);
      else
          k = find(abs(ordeig(ST)) > 2-options_.qz_criterium);
      end
      nk = length(k);
      nk1 = nk+1;
      Pinf = zeros(np,np);
      Pinf(1:nk,1:nk) = eye(nk);
      Pstar = zeros(np,np);
      B = QT'*R*Q*R'*QT;
      for i=np:-1:nk+2
          if ST(i,i-1) == 0
              if i == np
                  c = zeros(np-nk,1);
              else
                  c = ST(nk1:i,:)*(Pstar(:,i+1:end)*ST(i,i+1:end)')+...
                      ST(i,i)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i);
              end
              q = eye(i-nk)-ST(nk1:i,nk1:i)*ST(i,i);
              Pstar(nk1:i,i) = q\(B(nk1:i,i)+c);
              Pstar(i,nk1:i-1) = Pstar(nk1:i-1,i)';
          else
              if i == np
                  c = zeros(np-nk,1);
                  c1 = zeros(np-nk,1);
              else
                  c = ST(nk1:i,:)*(Pstar(:,i+1:end)*ST(i,i+1:end)')+...
                      ST(i,i)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i)+...
                      ST(i,i-1)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i-1);
                  c1 = ST(nk1:i,:)*(Pstar(:,i+1:end)*ST(i-1,i+1:end)')+...
                       ST(i-1,i-1)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i-1)+...
                       ST(i-1,i)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i);
              end
              q = [eye(i-nk)-ST(nk1:i,nk1:i)*ST(i,i) -ST(nk1:i,nk1:i)*ST(i,i-1);...
                   -ST(nk1:i,nk1:i)*ST(i-1,i) eye(i-nk)-ST(nk1:i,nk1:i)*ST(i-1,i-1)];
              z =  q\[B(nk1:i,i)+c;B(nk1:i,i-1)+c1];
              Pstar(nk1:i,i) = z(1:(i-nk));
              Pstar(nk1:i,i-1) = z(i-nk+1:end);
              Pstar(i,nk1:i-1) = Pstar(nk1:i-1,i)';
              Pstar(i-1,nk1:i-2) = Pstar(nk1:i-2,i-1)';
              i = i - 1;
          end
      end
      if i == nk+2
          c = ST(nk+1,:)*(Pstar(:,nk+2:end)*ST(nk1,nk+2:end)')+ST(nk1,nk1)*ST(nk1,nk+2:end)*Pstar(nk+2:end,nk1);
          Pstar(nk1,nk1)=(B(nk1,nk1)+c)/(1-ST(nk1,nk1)*ST(nk1,nk1));
      end
      
      Z = QT(mf,:);
      R1 = QT'*R;
% $$$       [u,s,v]=svd(Z*ST(:,1:nk),0);
% $$$       k = find(abs(diag(s)) < 1e-8);
% $$$       if length(k) > 0
% $$$ 	  [junk,k1] = max(abs(v(:,k)));
% $$$ 	  dd =ones(nk,1);
% $$$ 	  dd(k1) = zeros(length(k1),1);
% $$$ 	  Pinf(1:nk,1:nk) = diag(dd);
% $$$       end
      Pinf(1:nk,1:nk) = eye(nk);
  end
  % -----------------------------------------------------------------------------
  %  4. Kalman smoother
  % -----------------------------------------------------------------------------
  if any(any(H ~= 0))   % should be replaced by a flag
      if kalman_algo == 1
          [alphahat,epsilonhat,etahat,ahat,aK] = ...
              DiffuseKalmanSmootherH1(T,R,Q,H,Pinf,Pstar,Y,trend,nobs,np,smpl,mf);
          if all(alphahat(:)==0)
              kalman_algo = 2;
              if ~estim_params_.ncn
                  [alphahat,epsilonhat,etahat,ahat,aK] = ...
                      DiffuseKalmanSmootherH3(T,R,Q,H,Pinf,Pstar,Y,trend,nobs,np,smpl,mf);
              else
                  [alphahat,epsilonhat,etahat,ahat,aK] = ...
                      DiffuseKalmanSmootherH3corr(T,R,Q,H,Pinf,Pstar,Y,trend, ...
                                                  nobs,np,smpl,mf);
              end
          end
      elseif options_.kalman_algo == 2
          if ~estim_params_.ncn
              [alphahat,epsilonhat,etahat,ahat,aK] = ...
                  DiffuseKalmanSmootherH3(T,R,Q,H,Pinf,Pstar,Y,trend,nobs,np,smpl,mf);
          else
              [alphahat,epsilonhat,etahat,ahat,aK] = ...
                  DiffuseKalmanSmootherH3corr(T,R,Q,H,Pinf,Pstar,Y,trend, ...
                                              nobs,np,smpl,mf);
          end
      elseif kalman_algo == 3 | kalman_algo == 4
          data1 = Y - trend;
          if kalman_algo == 3
              [alphahat,epsilonhat,etahat,ahat,P,aK,PK,d,decomp] = ...
                  DiffuseKalmanSmootherH1_Z(ST,Z,R1,Q,H,Pinf,Pstar,data1,nobs,np,smpl);
              if all(alphahat(:)==0)
                  kalman_algo = 4;
                  if ~estim_params_.ncn
                      [alphahat,epsilonhat,etahat,ahat,P,aK,PK,d,decomp] = ...
                          DiffuseKalmanSmootherH3_Z(ST,Z,R1,Q,H,Pinf,Pstar,data1,nobs,np,smpl);
                  else
                      [alphahat,epsilonhat,etahat,ahat,P,aK,PK,d,decomp] = ...
                          DiffuseKalmanSmootherH3corr_Z(ST,Z,R1,Q,H,Pinf,Pstar,data1, ...
                                                        nobs,np,smpl);
                  end
              end
          else
              if ~estim_params_.ncn
                  [alphahat,epsilonhat,etahat,ahat,P,aK,PK,d,decomp] = ...
                      DiffuseKalmanSmootherH3_Z(ST,Z,R1,Q,H,Pinf,Pstar,data1, ...
                                                nobs,np,smpl);
              else
                  [alphahat,epsilonhat,etahat,ahat,P,aK,PK,d,decomp] = ...
                      DiffuseKalmanSmootherH3corr_Z(ST,Z,R1,Q,H,Pinf,Pstar,data1, ...
                                                    nobs,np,smpl);
              end
          end
          alphahat = QT*alphahat;
          ahat = QT*ahat;
          nk = options_.nk;
          for jnk=1:nk
              aK(jnk,:,:) = QT*squeeze(aK(jnk,:,:));
              for i=1:size(PK,4)
                  PK(jnk,:,:,i) = QT*squeeze(PK(jnk,:,:,i))*QT';
              end
              for i=1:size(decomp,4)
                  decomp(jnk,:,:,i) = QT*squeeze(decomp(jnk,:,:,i));
              end
          end
          for i=1:size(P,4)
              P(:,:,i) = QT*squeeze(P(:,:,i))*QT';
          end
      end
  else
      if kalman_algo == 1
          [alphahat,etahat,ahat,aK] = DiffuseKalmanSmoother1(T,R,Q,Pinf,Pstar,Y,trend,nobs,np,smpl,mf);
          if all(alphahat(:)==0)
              kalman_algo = 2;
              [alphahat,etahat,ahat,aK] = DiffuseKalmanSmoother3(T,R,Q,Pinf,Pstar,Y,trend,nobs,np,smpl,mf);
          end
      elseif kalman_algo == 2
          [alphahat,etahat,ahat,aK] = DiffuseKalmanSmoother3(T,R,Q,Pinf,Pstar,Y,trend,nobs,np,smpl,mf);
      elseif kalman_algo == 3 | kalman_algo == 4
          data1 = Y - trend;
          if options_.kalman_algo == 3
              [alphahat,etahat,ahat,P,aK,PK,d,decomp] = DiffuseKalmanSmoother1_Z(ST, ...
						  Z,R1,Q,Pinf,Pstar,data1,nobs,np,smpl);
              if all(alphahat(:)==0)
                  options_.kalman_algo = 4;
                  [alphahat,etahat,ahat,P,aK,PK,d,decomp] = DiffuseKalmanSmoother3_Z(ST, ...
						  Z,R1,Q,Pinf,Pstar, ...
                                                  data1,nobs,np,smpl);
              end
%              oo_.NewFilteredVariables = QT*filtered_values(data1,ahat,P,T,Z);
          else
              [alphahat,etahat,ahat,P,aK,PK,d,decomp] = DiffuseKalmanSmoother3_Z(ST, ...
						  Z,R1,Q,Pinf,Pstar,data1,nobs,np,smpl);
          end
          alphahat = QT*alphahat;
          ahat = QT*ahat;
          nk = options_.nk;
          for jnk=1:nk
              aK(jnk,:,:) = QT*squeeze(aK(jnk,:,:));
              for i=1:size(PK,4)
                  PK(jnk,:,:,i) = QT*squeeze(PK(jnk,:,:,i))*QT';
              end
              for i=1:size(decomp,4)
                  decomp(jnk,:,:,i) = QT*squeeze(decomp(jnk,:,:,i));
              end
          end
          for i=1:size(P,4)
              P(:,:,i) = QT*squeeze(P(:,:,i))*QT';
          end
      end
  end
