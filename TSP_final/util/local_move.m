% =============================================================================
% == local_move.m
% == --------------------------------------------------------------------------
% == An interface to perform local TSP moves with flow estimation.
% == See m files for calling convention.
% ==
% == All work using this code should cite:
% == J. Chang, D. Wei, and J. W. Fisher III. A Video Representation Using
% ==    Temporal Superpixels. CVPR 2013.
% == --------------------------------------------------------------------------
% == Written in C++ by Jason Chang and Donglai Wei 06-20-2013
% == Converted to MATLAB by Andrew Pillsbury 12-4-2014
% =============================================================================
function [IMG_K, IMG_label, IMG_SP, IMG_SP_changed, IMG_max_UID, IMG_alive_dead_changed, IMG_SP_old, IMG_Sxy, IMG_Syy] = local_move(IMG_label, IMG_K, IMG_N, IMG_SP_changed, IMG_SP, IMG_T4Table, IMG_boundary_mask, IMG_dummy_log_prob, IMG_new_SP, IMG_SP_old, IMG_data, model_order_params, IMG_new_pos, IMG_new_app, IMG_max_UID, IMG_alive_dead_changed, IMG_prev_pos_mean, IMG_prev_K, IMG_prev_precision, IMG_prev_covariance, IMG_Sxy, IMG_Syy, IMG_max_SPs, its)
    disp('local_move');
    for iter=1:its
        if mod(iter,10)==0
            fprintf('local iter=%d\n',iter);
        end
        
        %COMPUTE THE FLOW
        
        %given label z, globally update flow variable of SP using GP approximation of Optical Flow like L2 penalty

        % get the alive stuff
        num_alive = 0;
        num_dead = 0;
        alive2all = zeros(IMG_prev_K, 1);
        dead2all = zeros(IMG_prev_K, 1);
        for k=1:IMG_prev_K
            if ~(k > numel(IMG_SP) || isempty(IMG_SP(k).N) || IMG_SP(k).N == 0)
                num_alive = num_alive + 1;
                alive2all(num_alive) = k;
            else
                num_dead = num_dead + 1;
                dead2all(num_dead) = k;
            end
        end

        % for computational efficiency
        % 1. Covariance matrix
        if IMG_alive_dead_changed || isempty(IMG_Syy)
            IMG_Syy = zeros(num_alive, num_alive);
            IMG_Sxy = zeros(IMG_prev_K, num_alive);
            %obs_uv(:,1) is obs_u, obs_uv(:,2) is obs_v
            obs_uv = zeros(num_alive,2);

            % FIND IMG_Sxy and IMG_Syy
            % assume memory allocated correctly for SxySyy
            temp_still_alive = true(IMG_prev_K, 1);
            temp_Syy = IMG_prev_precision;
            temp_d = zeros(IMG_prev_K, 1);
            if num_dead>0
                for dead_kindex=1:num_dead
                    dead_k = dead2all(dead_kindex);
                    c = temp_Syy(dead_k, dead_k);
                    temp_still_alive(dead_k) = false;

                    %only populate half of the matrix
                    found_still_alive = find(temp_still_alive(1:dead_k));
                    for ind=1:length(found_still_alive);
                        i = found_still_alive(ind);
                        temp_d(i, 1) = temp_Syy(dead_k, i);
                    end

                    found_still_alive = find(temp_still_alive(dead_k+1:IMG_prev_K));
                    for ind=1:length(found_still_alive);
                        i = found_still_alive(ind);
                        temp_d(i, 1) = temp_Syy(i, dead_k);
                    end

                    found_still_alive = find(temp_still_alive);
                    for ind=1:length(found_still_alive);
                        i = found_still_alive(ind);
                        temp_di = temp_d(i, 1);
                        temp_Syy(i, i) = temp_Syy(i, i) - (temp_di^2)/c;
                        temp_di = temp_di/c;
                        temp_found_still_alive = find(temp_still_alive(i+1:IMG_prev_K));
                        for jind=1:length(temp_found_still_alive)
                            j = temp_found_still_alive(jind);
                            temp_Syy(j, i) = temp_Syy(j, i) - temp_di*temp_d(j);
                        end
                    end
                end
            end

            for k=1:IMG_prev_K
                for alive_k=1:num_alive
                    IMG_Sxy(k, alive_k) = IMG_prev_covariance(k, alive2all(alive_k));
                end
            end

            for k1=1:num_alive
                alive_k1 = alive2all(k1);
                IMG_Syy(k1, k1) = temp_Syy(alive_k1, alive_k1);
                for k2=k1+1:num_alive
                    alive_k2 = alive2all(k2);
                    IMG_Syy(k1, k2) = temp_Syy(alive_k1, alive_k2);
                    IMG_Syy(k2, k1) = temp_Syy(alive_k2, alive_k1);
                end
            end
            IMG_alive_dead_changed = false;
        end

        % populate the observation
        for k1=1:num_alive
            all_k1 = alive2all(k1);
            obs_uv(k1,:) = NormalD_calc_mean(IMG_SP(all_k1).pos) - IMG_prev_pos_mean(all_k1, :) - IMG_SP(all_k1).prev_v;
        end

        % uv_gsl(1) = ugsl, uv_gsl(2) = vgsl
        uv_gsl = IMG_Sxy * IMG_Syy * obs_uv;

        % copy over the new parameters
        for i=1:IMG_prev_K
            if ~(i > numel(IMG_SP) || isempty(IMG_SP(i).N) || IMG_SP(i).N == 0)
                % ith element of ugsl
                IMG_SP(i).pos.offset = uv_gsl(i,:) + IMG_SP(i).prev_v;
            end
        end
        IMG_SP_changed(1:IMG_prev_K) = true;

        % make the move
        [IMG_K, IMG_label, IMG_SP, IMG_SP_changed, IMG_max_UID, IMG_alive_dead_changed, IMG_SP_old, changed] = local_move_internal(IMG_label, IMG_K, IMG_N, IMG_SP_changed, IMG_SP, IMG_T4Table, IMG_boundary_mask, IMG_dummy_log_prob, IMG_new_SP, IMG_SP_old, IMG_data, model_order_params, IMG_new_pos, IMG_new_app, IMG_max_UID, IMG_alive_dead_changed, IMG_max_SPs);
        if ~changed
            break;
        end
    end
end