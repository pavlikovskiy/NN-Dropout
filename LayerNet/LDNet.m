classdef LDNet < handle
    % An LDNet is a composition of LDLayers. This class is designed for testing
    % and experimenting with Dropout Ensemble Variance regularization.
    %
    
    properties
        % layers is a cell array of handles/pointers for the layers from which
        % this LDNet is composed.
        layers
        % layer_count gives the number of layers in this LDNet (not including
        % the input layer).
        layer_count
        % out_loss gives the loss function to apply at output layer
        out_loss
        % lam_l2 gives an L2 regularization penalty applied to all weights in
        % this LDNet.
        lam_l2
        % lam_l1 gives an L1 regularization penalty applied to all weights in
        % this LDNet.
        lam_l1
        % dev_lams gives the lam_dev for each layer
        dev_lams
        % dev_types gives the dev type for each layer
        dev_types
        % drop_input gives the drop rate for input layer
        drop_input
        % drop_hidden gives the drop rate for hidden layers
        drop_hidden
        % drop_undrop gives the fraction of training examples to not apply any
        % dropping to
        drop_undrop
        % do_dev tells whether to do DEV regularization or standard dropout
        do_dev
        % dev_pre
        dev_pre
    end % END PROPERTIES
    
    methods
        function [ self ] = LDNet( layer_sizes, act_func, loss_func )
            self.layer_count = numel(layer_sizes) - 1;
            self.layers = cell(1,self.layer_count);
            for i=1:self.layer_count,
                dim_in = layer_sizes(i) + 1;
                dim_out = layer_sizes(i+1);
                if (i < self.layer_count)
                    afun = act_func;
                else
                    afun = @LDLayer.line_trans;
                end
                self.layers{i} = LDLayer(dim_in, dim_out, afun);
            end
            if ~exist('loss_func','var')
                self.out_loss = @LDNet.loss_lsq;
            else
                self.out_loss = loss_func;
            end
            self.lam_l2 = 0;
            self.lam_l1 = 0;
            % Set dropout rate parameters
            self.drop_input = 0;
            self.drop_hidden = 0.5;
            self.drop_undrop = 0;
            self.do_dev = 0;
            self.dev_pre = 0;
            self.dev_types = ones(1,self.layer_count);
            self.dev_lams = zeros(1,self.layer_count);
            return
        end
        
        function [ acc ] = check_acc(self, X, Y)
            % Check classification performance on the given data
            if (size(Y,2) == 1)
                Y = LDNet.to_cats(Y);
            else
                Y = LDNet.class_cats(Y);
            end
            M = self.get_drop_masks(size(X,1));
            for i=1:length(M),
                M{i} = ones(size(M{i}));
            end
            F = self.feedforward(X,M,self.struct_weights());
            Yh = LDNet.class_cats(F{end});
            acc = sum(Yh == Y) / numel(Y);
            return
        end
        
        function [ N ] = weight_count(self)
            % Get the total number of weights in this layer.
            %
            N = 0;
            for i=1:self.layer_count,
                N = N + self.layers{i}.weight_count();
            end
            return
        end
        
        function [ Ws ] = init_weights(self, wt_scale, b_scale)
            % Initialize the weights for each layer in this LDNet. Return a
            % struct array containing the weight structs for each layer.
            if ~exist('b_scale','var')
                b_scale = wt_scale;
            end
            for i=1:self.layer_count,
                lay_i = self.layers{i};
                if (i == 1)
                    lay_i.init_weights(wt_scale,b_scale,0);
                else
                    lay_i.init_weights(wt_scale,b_scale,1);
                end
            end
            Ws = self.struct_weights();
            return
        end
        
        function [ Ws ] = set_weights(self, Ws)
            % Set weights for this LDNet, using the struct/vector W.
            %
            if ~isstruct(Ws)
                Ws = self.struct_weights(Ws);
            end
            for i=1:self.layer_count,
                self.layers{i}.set_weights(Ws(i).W);
            end
            return
        end
        
        function [ Ws ] = struct_weights(self, Wv)
            if ~exist('Wv','var')
                Wv = self.vector_weights();
            end
            assert((numel(Wv) == self.weight_count()),'Bad Wv.');
            Ws = struct();
            end_idx = 0;
            for i=1:self.layer_count,
                start_idx = end_idx + 1;
                end_idx = start_idx + (self.layers{i}.weight_count() - 1);
                Ws(i).W = self.layers{i}.matrix_weights(Wv(start_idx:end_idx));
            end
            return
        end
        
        function [ Wv ] = vector_weights(self, Ws)
            % Return a vectorized representation of the struct array of weight
            % matrices in Ws. Assume each weight matrix Ws(i).W can be used
            % by the LDLayer object at self.layers{i}.
            %
            % If no argument given, vectorize current weights for each layer.
            %
            Wv = [];
            for i=1:self.layer_count,
                lay_i = self.layers{i};
                if exist('Ws','var')
                    Wv = [Wv; lay_i.vector_weights(Ws(i).W)];
                else
                    Wv = [Wv; lay_i.vector_weights()];
                end
            end
            return
        end
        
        function [ M ] = get_drop_masks(self, mask_count, no_drop)
            % Get masks to apply to the activations of each layer (including at
            % the input layer), for dropout.
            %
            if ~exist('no_drop','var')
                no_drop = 0;
            end
            M = cell(1,self.layer_count);
            u_mask = (rand(mask_count,1) < self.drop_undrop);
            for i=1:self.layer_count,
                if (i == 1)
                    drop_rate = self.drop_input;
                else
                    drop_rate = self.drop_hidden;
                end
                mask_dim = self.layers{i}.dim_input;
                d_mask = (rand(mask_count,mask_dim) > drop_rate);
                M{i} = bsxfun(@or, d_mask, u_mask);
                M{i} = bsxfun(@times, M{i}, 1 ./ mean(M{i},2));
                if ((no_drop == 1) && (i > 1))
                    M{i} = ones(size(M{i}));
                end
            end
            return
        end

        function [ A_post A_pre ] = feedforward(self, X, M, Ws)
            % Compute feedforward activations for the inputs in X. Return the
            % cell arrays A_post and A_pre, in which A_post{i} gives
            % post-transform activations for layer i and A_pre{i} gives
            % pre-transform activations for layer i.
            %
            % If no Ws is given, then use current weights for each layer.
            %
            if ~exist('Ws','var')
                Ws = self.struct_weights();
            end
            A_post = cell(1,self.layer_count);
            if (nargout > 1)
                A_pre = cell(1,self.layer_count);
            end
            for i=1:self.layer_count,
                lay_i = self.layers{i};
                M_pre = M{i};
                if (i == 1)
                    A_in = LDNet.bias(X) .* M_pre;
                else
                    A_in = LDNet.bias(A_post{i-1}) .* M_pre;
                end
                [post pre] = lay_i.feedforward(A_in, Ws(i).W);
                A_post{i} = post;
                if (nargout > 1)
                    A_pre{i} = pre;
                end
            end
            return
        end
        
        function [ dLdWs dLdX ] = backprop(self, ...
                dLdA_post, dLdA_pre, A_post, X, M, Ws)
            % Backprop through the layers of this LDNet.
            %
            dLdWs = struct();
            for i=self.layer_count:-1:1,
                lay_i = self.layers{i};
                M_pre = M{i};
                if (i == 1)
                    A_in = LDNet.bias(X) .* M_pre;
                else
                    A_in = LDNet.bias(A_post{i-1}) .* M_pre;
                end
                [dLdWi dLdAi] = lay_i.backprop(dLdA_post{i}, dLdA_pre{i}, ...
                    A_post{i}, A_in, Ws(i).W);
                dLdAi = dLdAi .* M_pre;
                if (i == 1)
                    dLdX = dLdAi(:,1:(end-1));
                else
                    dLdA_post{i-1} = dLdA_post{i-1} + dLdAi(:,1:(end-1));
                end
                dLdWs(i).W = dLdWi;
            end
            return
        end
        
        function [ opts ] = train(self, X, Y, opts)
            % Train a multilayer feedforward network with an initial bilinear
            % layer followed by some number of linear/quadratic layers.
            %
            % Parameters:
            %   X: training observations
            %   Y: target outputs for observation in X
            %   opts: struct containing training options
            %
            % Outputs:
            %   opts: the options used in training (options not present in the
            %         initial opts structure will be set to default values).
            %
            if ~exist('opts','var')
                opts = struct();
            end
            % Check and set method specific options to valid values
            opts = LDNet.check_opts(opts);
            if isfield(opts,'lam_l2')
                self.lam_l2 = opts.lam_l2;
            end
            if isfield(opts,'lam_l1')
                self.lam_l1 = opts.lam_l1;
            end
            % Loop over SGD updates for randomly sampled minibatches
            batch_size = opts.batch_size;
            dev_reps = opts.dev_reps;
            rate = opts.start_rate;
            decay = opts.decay_rate;
            momentum = opts.momentum;
            rounds = opts.rounds;
            % Get initial weight vector
            Ws = self.struct_weights();
            dLdWs_mom = struct();
            for i=1:self.layer_count,
                dLdWs_mom(i).W = zeros(size(Ws(i).W));
            end
            for i=1:rounds,
                % Grab a batch of training samples
                if (batch_size < size(X,1))
                    idx = randsample(size(X,1),batch_size,false);
                    Xb = X(idx,:);
                    Yb = Y(idx,:);
                else
                    Xb = X;
                    Yb = Y;
                end
                if (self.do_dev == 1)
                    Xb = repmat(Xb,dev_reps,1);
                end
                % Get dropout masks for this batch
                Mb = self.get_drop_masks(size(Xb,1));
                if (self.do_dev == 1)
                    % For the undropped obs, set hidden-layer masks to ones
                    for l=2:self.layer_count,
                        Mb{l}(1:batch_size,:) = 1;
                    end
                end
                % Compute loss and weight gradients for this batch
                if (self.do_dev ~= 1)
                    [L dLdWs] = self.sde_loss_W(Ws, Xb, Yb, Mb);
                else
                    [L dLdWs] = ...
                        self.dev_loss_W(Ws, Xb, Yb, Mb, batch_size, dev_reps);
                end
                rater = min(rate, ((i / 1000) * rate));
                for l=1:self.layer_count,
                    dLdWs_mom(l).W = (momentum * dLdWs_mom(l).W) + ...
                        ((1-momentum) * dLdWs(l).W);
                    % Update weight vector
                    Ws(l).W = Ws(l).W - (rater * dLdWs_mom(l).W);
                end
                rate = rate * decay;
                % Bound weights
                for l=1:self.layer_count,
                    Ws(l).W = self.layers{l}.bound_weights(Ws(l).W, 4);
                end
                if ((i == 1) || (mod(i, 100) == 0)) 
                    % Record updated weights
                    self.set_weights(Ws);
                    draw_usps_filters(Ws(1).W,36,1,1,gcf());
                    drawnow();
                    % Check accuracy with updated weights
                    if (size(X,1) > 1000)
                        idx = randsample(size(X,1),1000);
                    else
                        idx = 1:size(X,1);
                    end
                    acc_tr = self.check_acc(X(idx,:),Y(idx,:));
%                     Mb = self.get_drop_masks(size(X(idx,:),1),0);
%                     Ab = self.feedforward(X(idx,:),Mb,Ws);
%                     mean_acts = [];
%                     for l=1:(self.layer_count - 1),
%                         mean_acts = [mean_acts mean(Ab{l},1)];
%                     end
%                     plot(mean_acts,'o');
%                     drawnow();
                    if (opts.do_validate == 1)
                        if(size(opts.Xv,1) > 1000)
                            idx = randsample(size(opts.Xv,1),1000);
                        else
                            idx = 1:size(opts.Xv,1);
                        end
                        acc_te = self.check_acc(opts.Xv(idx,:),opts.Yv(idx,:));
                        fprintf('Round %d, acc_tr: %.4f, acc_te: %.4f\n',...
                            i, acc_tr, acc_te);
                    else                        
                        fprintf('Round %d, acc_tr: %.4f\n',i,acc_tr);
                    end
                    fprintf('    Lo: %.4f, Ld: %.4f, Lr: %.4f\n',L(1),L(2),L(3));
                end
            end
            return
        end
        
        function [ accs ] = check_grad(self, X, Y, grad_checks, opts)
            % Check backprop computations for this LDNet.
            %
            if ~exist('opts','var')
                opts = struct();
            end
            % Check and set method specific options to valid values
            opts = LDNet.check_opts(opts);
            % Use minFunc's directional derivative gradient checking
            batch_size = opts.batch_size;
            dev_reps = opts.dev_reps;
            order = 1;
            type = 2;
            accs = zeros(1,grad_checks);
            for i=1:grad_checks,
                fprintf('=============================================\n');
                fprintf('GRAD CHECK %d\n',i);
                % Grab a batch of training samples
                if (batch_size < size(X,1))
                    idx = randsample(size(X,1),batch_size,false);
                    Xb = X(idx,:);
                    Yb = Y(idx,:);
                else
                    Xb = X;
                    Yb = Y;
                end
                if (self.do_dev == 1)
                    Xb = repmat(Xb,dev_reps,1);
                end
                % Get dropout masks for this batch
                Mb = self.get_drop_masks(size(Xb,1));
                if (self.do_dev == 1)
                    % For the non-dropped obs, set masks to ones
                    for l=1:self.layer_count,
                        Mb{l}(1:batch_size,:) = 1;
                    end
                end
                % Package a function handle for use by minFunc
                if (self.do_dev == 0)
                    mf_func = @( w ) self.sde_loss_W(w, Xb, Yb, Mb);
                else
                    mf_func = @( w ) self.dev_loss_W(...
                        w, Xb, Yb, Mb, batch_size, dev_reps);
                end
                % Do some learning using minFunc
                W = self.vector_weights(self.struct_weights());
                accs(i) = fastDerivativeCheck(mf_func,W,order,type);
            end
            return
        end
        
        function [ L dLdWs ] = sde_loss_W(self, Ws, X, Y, M)
            % Loss wrapper LDNet training wrt layer parameters.
            %
            return_struct = 1;
            if ~isstruct(Ws)
                Ws = self.struct_weights(Ws);
                return_struct = 0;
            end
            A_post = self.feedforward(X, M, Ws);
            % Compute loss and gradient at output layer
            Yh = A_post{end};
            [L_out dL_out] = self.out_loss(Yh, Y);
            dLdA_post = cell(1,length(A_post));
            dLdA_pre = cell(1,length(A_post));
            for i=1:length(A_post),
                dLdA_post{i} = zeros(size(A_post{i}));
                dLdA_pre{i} = zeros(size(A_post{i}));
            end
            dLdA_post{end} = dL_out;
            dLdWs = self.backprop(dLdA_post, dLdA_pre, A_post, X, M, Ws);
            % Add loss and gradient for L2/L1 parameter regularization
            L_reg = 0;
            for i=1:self.layer_count,
                L_reg = L_reg + (self.lam_l2 * sum(sum(Ws(i).W.^2)));
                dLdWs(i).Ws.w = dLdWs(i).W + (2 * (self.lam_l2 * Ws(i).W));
            end
            % Combine losses
            L = [L_out 0 L_reg];
            if (return_struct == 0)
                L = sum(L);
                dLdWs = self.vector_weights(dLdWs);
            end
            return
        end
        
        function [ L dLdWs ] = dev_loss_W(self, Ws, X, Y, M, b_size, d_reps)
            % Loss wrapper LDNet training wrt layer parameters.
            %
            return_struct = 1;
            if ~isstruct(Ws)
                Ws = self.struct_weights(Ws);
                return_struct = 0;
            end
            [A_post A_pre] = self.feedforward(X, M, Ws);
            % Compute loss and gradient at output layer
            Yh = A_post{end}(1:b_size,:);
            [L_out dL_out] = self.out_loss(Yh, Y);
            dLdA_post = cell(1,length(A_post));
            dLdA_pre = cell(1,length(A_post));
            for i=1:self.layer_count,
                dLdA_post{i} = zeros(size(A_post{i}));
                dLdA_pre{i} = zeros(size(A_pre{i}));
            end
            dLdA_post{end}(1:b_size,:) = dL_out;
            % Compute loss and gradient due to Dropout Ensemble Variance
            L_dev = 0;
            for i=1:self.layer_count,
                if (self.dev_pre == 1)
                    [Li dLdFi] = LDNet.drop_loss(A_pre{i}, b_size, d_reps, ...
                        self.dev_types(i), 0);
                    L_dev = L_dev + (self.dev_lams(i) * Li);
                    dLdA_pre{i} = dLdA_pre{i} + (self.dev_lams(i) * dLdFi);
                else
                    [Li dLdFi] = LDNet.drop_loss(A_post{i}, b_size, d_reps, ...
                        self.dev_types(i), 0);
                    L_dev = L_dev + (self.dev_lams(i) * Li);
                    dLdA_post{i} = dLdA_post{i} + (self.dev_lams(i) * dLdFi);
                end
            end
            % Backprop all gradients
            dLdWs = self.backprop(dLdA_post, dLdA_pre, A_post, X, M, Ws);
            % Add loss and gradient for L2/L1 parameter regularization
            L_reg = 0;
            for i=1:self.layer_count,
                L_reg = L_reg + (self.lam_l2 * sum(sum(Ws(i).W.^2)));
                dLdWs(i).W = dLdWs(i).W + ((2 * self.lam_l2) * Ws(i).W);
            end
            % Combine losses
            L = [L_out L_dev L_reg];
            if (return_struct == 0)
                L = sum(L);
                dLdWs = self.vector_weights(dLdWs);
            end            
            return
        end
        
    end % END INSTANCE METHODS
    
    methods (Static = true)
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % DROPOUT ENSEMBLE VARIANCE LOSS %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [L dLdF] = drop_loss(F, b_obs, b_reps, dev_type, use_shepherd)
            % Compute feature activations from droppy observations, and
            % grab a function handle for backpropping through activation
            %
            if ~exist('dev_type','var')
                dev_type = 1;
            end
            if ~exist('use_shepherd','var')
                use_shepherd = 0;
            end
            switch dev_type
                case 1
                    [F bp_F] = LDNet.norm_transform(F);
                case 2
                    [F bp_F] = LDNet.tanh_transform(F);
                case 3
                    [F bp_F] = LDNet.line_transform(F);
                otherwise
                    error('Improperly specified dev_type');
            end 
            N = size(F,2);
            Ft = zeros(b_obs, N, b_reps);
            for i=1:b_reps,
                b_start = ((i-1) * b_obs) + 1;
                b_end = b_start + (b_obs - 1);
                Ft(:,:,i) = F(b_start:b_end,:);
            end
            % Compute mean of each repeated observations activations
            n = b_reps;
            m = (b_obs * b_reps * N);
            if (use_shepherd ~= 1)
                Fm = sum(Ft,3) ./ n;
            else
                Fm = Ft(:,:,1);
            end
            % Compute differences between individual activations and means
            Fd = bsxfun(@minus, Ft, Fm);
            % Compute droppy variance loss
            L = sum(Fd(:).^2) / m;
            if (use_shepherd ~= 1)
                % Compute droppy variance gradient (magic numbers everywhere!)
                dLdFt = -(2/m) * ((((1/n) - 1) * Fd) + ...
                    ((1/n) * bsxfun(@minus, sum(Fd,3), Fd)));
            else
                dLdFt = (2*Fd) ./ m;
                dLdFt(:,:,1) = -sum(dLdFt(:,:,2:end),3);
            end
            dLdF = zeros(size(F));
            for i=1:b_reps,
                b_start = ((i-1) * b_obs) + 1;
                b_end = b_start + (b_obs - 1);
                dLdF(b_start:b_end,:) = squeeze(dLdFt(:,:,i));
            end
            % Backprop through the transform determined by dev_type
            dLdF = bp_F(dLdF);
            return
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % OUTPUT LAYER LOSS FUNCTIONS %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [ L dL ] = loss_mclr(Yh, Y)
            % Compute a multiclass logistic regression loss and its gradients,
            % w.r.t. the proposed outputs Yh, given the true values Y.
            %
            obs_count = size(Yh,1);
            cl_count = size(Y,2);
            [Y_max Y_idx] = max(Y,[],2);
            P = bsxfun(@rdivide, exp(Yh), sum(exp(Yh),2));
            % Compute classification loss (deviance)
            p_idx = sub2ind(size(P), (1:obs_count)', Y_idx);
            L = -sum(sum(log(P(p_idx)))) / obs_count;
            if (nargout > 1)
                % Make a binary class indicator matrix
                Yi = bsxfun(@eq, Y_idx, 1:cl_count);
                % Compute the gradient of classification loss
                dL = (P - Yi) ./ obs_count;
            end
            return
        end
        
        function [ L dL ] = loss_mcl2h(Yh, Y)
            % Compute a multiclass L2 hinge loss and its gradients, w.r.t. the
            % proposed outputs Yh, given the true values Y.
            %
            obs_count = size(Yh,1);
            cl_count = size(Y,2);
            [Y_max Y_idx] = max(Y,[],2);
            % Make a class indicator matrix using +1/-1
            Yc = bsxfun(@(y1,y2) (2*(y1==y2))-1, Y_idx, 1:cl_count);
            % Compute current L2 hinge loss given the predictions in Yh
            margin_lapse = max(0, 1 - (Yc .* Yh));
            L = (0.5 * margin_lapse.^2);
            L = sum(sum(L)) / obs_count;
            if (nargout > 1)
                % For L2 hinge loss, dL is equal to the margin intrusion
                dL = -(Yc .* margin_lapse) ./ obs_count;
            end
            return
        end       
        
        function [ L dL ] = loss_lsq(Yh, Y)
            % Compute a least-sqaures regression loss and its gradients, for
            % each of the predicted outputs in Yh with true values Y.
            %
            obs_count = size(Yh,1);
            R = Yh - Y;
            L = R.^2;
            L = sum(sum(L)) / obs_count;
            if (nargout > 1)
                % Compute the gradient of least-squares loss
                dL = (2 * R) ./ obs_count;
            end
            return
        end
        
        function [ L dL ] = loss_hsq(Yh, Y, delta)
            % Compute a "huberized" least-sqaures regression loss and its
            % gradients, for each of the predicted outputs in Yh with true
            % values Y. This loss simply transitions from L2 to L1 loss for
            % element residuals greater than 1. This helps avoid descent
            % breaking oversized gradients.
            %
            if ~exist('delta','var')
                delta = 0.5;
            end
            obs_count = size(Yh,1);
            R = Yh - Y;
            mask = (abs(R) < delta);
            L = zeros(size(R));
            L(mask) = R(mask).^2;
            L(~mask) = (2 * delta * abs(R(~mask))) - delta^2;
            L = sum(sum(L)) / obs_count;
            if (nargout > 1)
                % Compute the gradient of huberized least-squares loss
                dL = zeros(size(R));
                dL(mask) = 2 * R(mask);
                dL(~mask) = (2 * delta) .* sign(R(~mask));
                dL = dL ./ obs_count;
            end
            return
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % BACKPROPPABLE TRANSFORMS %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [ F BP ] = norm_transform(X)
            % L2 normalize X by rows, and return both the row-normalized matrix
            % and a function handle for backpropagating through normalization.
            N = sqrt(sum(X.^2,2) + 1e-6);
            F = bsxfun(@rdivide,X,N);
            % Backpropagate through normalization for unit norm
            BP = @( D ) ...
                (bsxfun(@rdivide,D,N) - bsxfun(@times,F,(sum(D.*X,2)./(N.^2))));
            return
        end
        
        function [ F BP ] = tanh_transform(X)
            % Transform the elements of X by hypertangent, and create a function
            % handle for backpropping through the transform.
            F = tanh(X);
            BP = @( D ) (D .* (1 - F.^2));
            return
        end
        
        function [ F BP ] = line_transform(X)
            % Leave the values in X unchanged.
            F = X;
            BP = @( D ) (D .* ones(size(D)));
            return
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % CLASS MATRIX MANIPULATIONS %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [ Yc ] = class_cats(Yi)
            % Convert +1/-1 indicator class matrix to a vector of categoricals
            [vals Yc] = max(Yi,[],2);
            return
        end
        
        function [ Yi ] = class_inds(Y, class_count)
            % Convert categorical class values into +1/-1 indicator matrix
            class_labels = sort(unique(Y),'ascend');
            if ~exist('class_count','var')
                class_count = numel(class_labels);
            end
            Yi = -ones(size(Y,1),class_count);
            for i=1:numel(class_labels),
                c_idx = (Y == class_labels(i));
                Yi(c_idx,i) = 1;
            end
            return
        end
        
        function [ Yi ] = to_inds( Yc )
            % This wraps class_cats and class_inds.
            Yi = LDNet.class_inds(Yc);
            Yc = LDNet.class_cats(Yi);
            Yi = LDNet.class_inds(Yc);
            return
        end
        
        function [ Yc ] = to_cats( Yc )
            % This wraps class_cats and class_inds.
            Yi = LDNet.class_inds(Yc);
            Yc = LDNet.class_cats(Yi);
            return
        end
        
        function [ Xb ] = bias(X, bias_val)
            % Add a column of constant bias to the observations in X
            if ~exist('bias_val','var')
                bias_val = 1.0;
            end
            Xb = [X (bias_val * ones(size(X,1),1))];
            return
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % PARAMETER CHECKING AND DEFAULT SETTING %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [ opts ] = check_opts( opts )
            % Process parameters to use in training of some sort.
            if ~isfield(opts, 'rounds')
                opts.rounds = 10000;
            end
            if ~isfield(opts, 'start_rate')
                opts.start_rate = 0.1;
            end
            if ~isfield(opts, 'decay_rate')
                opts.decay_rate = 0.1^(1/opts.rounds);
            end
            if ~isfield(opts, 'momentum')
                opts.momentum = 0.8;
            end
            if ~isfield(opts, 'batch_size')
                opts.batch_size = 100;
            end
            if ~isfield(opts, 'dev_reps')
                opts.dev_reps = 4;
            end
            if ~isfield(opts, 'do_validate')
                opts.do_validate = 0;
            end
            if (opts.do_validate == 1)
                if (~isfield(opts, 'Xv') || ~isfield(opts, 'Yv'))
                    error('Validation set required for doing validation.');
                end
            end
            % Clip momentum to be in range [0...1]
            opts.momentum = min(1, max(0, opts.momentum));
            return
        end
        
    end % END STATIC METHODS
    
        
end





%%%%%%%%%%%%%%
% EYE BUFFER %
%%%%%%%%%%%%%%
