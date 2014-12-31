% =============================================================================
% == split_move.cpp
% == --------------------------------------------------------------------------
% == A MEX interface to perform split moves on TSPs.
% == See m files for calling convention.
% ==
% == All work using this code should cite:
% == J. Chang, D. Wei, and J. W. Fisher III. A Video Representation Using
% ==    Temporal Superpixels. CVPR 2013.
% == --------------------------------------------------------------------------
% == Written in C++ by Jason Chang and Donglai Wei 06-20-2013
% == Converted to MATLAB by Andrew Pillsbury 12-05-2014
% =============================================================================


function IMG = split_move(IMG, its)
    for i=1:its
        % choose a random order of super pixels
        Nsp = numel(IMG.SP);
        perm = randperm(Nsp);

        pre_K = Nsp;
        %split_thres = floor(IMG.N/IMG.K);

        energies = zeros(Nsp, 1);
        mean_area = 0;

        for k=1:pre_K
            temp_energy = (IMG.SP(k).log_likelihood + U_calc_model_order(IMG, IMG.SP(k).N, IMG.SP_old(k))) / IMG.SP(k).N;
            energies(k) = temp_energy;
            mean_area = mean_area + IMG.SP(k).N;
        end
        mean_area = mean_area / pre_K;
        threshold = min(energies) + (max(energies)-min(energies))*0.2;

        for k=perm
            if (any(IMG.SP(k).neighbors) && (IMG.SP(k).N>mean_area || energies(k) < threshold) && IMG.SP_changed(k))
                IMG = move_split_SP(IMG, k);
                
                %REMOVE EXCESS SPs
                SP = numel(IMG.SP); 
                while SP_is_empty(IMG, SP) && SP>Nsp
                    IMG.SP(SP) = [];
                    SP = SP - 1;
                end
            end
        end
    end
end


function IMG = move_split_SP(IMG, index)
    num_SP = 2;
    if ~SP_is_empty(IMG, index) && IMG.SP(index).N > num_SP
        new_ks = ones(num_SP, 1) * -1;
        ksplit = -1;
        max_E = -inf;

        %only work for num_SP == 2, so far
        IMG = move_split_SP_propose(IMG, index, num_SP, max_E, ksplit, new_ks);
        max_E = IMG.max_E;
        ksplit = IMG.ksplit;
        new_ks = IMG.new_ks;

        % update
        if max_E>0
            %mexPrintf("split: %f,%d,%d\n",max_E,index,new_ks[0]);
            % update the labels first
            IMG = U_set_label_from_SP_pixels(IMG, IMG.SP(new_ks(1)), index);

            % merge the super pixels
            IMG = U_merge_SPs(IMG, index, new_ks(1)); %need to delete
            IMG.SP_changed(index) = true;
            
            if (ksplit<0)
                % splitting into a new super pixel
                IMG.SP_changed(new_ks(2)) = true;
                % move it to the right spot
                if (new_ks(2)~=IMG.K+1)
                    IMG = U_set_label_from_SP_pixels(IMG, IMG.SP(new_ks(2)), IMG.K+1);
                    IMG = U_merge_SPs(IMG, IMG.K+1, new_ks(2));
                    IMG.SP_old(IMG.K+1) = IMG.SP_old(new_ks(2));
                end
                IMG.K = IMG.K + 1;
                IMG.max_UID = IMG.max_UID + 1;
            else
                % splitting into an old super pixel
                IMG.SP_changed(ksplit) = true;
                IMG = U_set_label_from_SP_pixels(IMG, IMG.SP(new_ks(2)), ksplit);
                IMG = U_merge_SPs(IMG, ksplit, new_ks(2));
                IMG.alive_dead_changed = true;
            end
        elseif (ksplit~=-2)
            %Recover previous IMG.label
            IMG = U_set_label_from_SP_pixels(IMG, IMG.SP(IMG.K+1), index);
            IMG = U_set_label_from_SP_pixels(IMG, IMG.SP(IMG.K+2), index);
            IMG.SP_changed(index) = false;

            for i=1:num_SP
                IMG = U_merge_SPs(IMG, index, IMG.K+i);
            end
        else
            IMG.SP_changed(index) = false;
        end
    end
end


function IMG = move_split_SP_propose(IMG, index, num_SP, max_E, ksplit, new_ks)
    num_iter = 5;
    SP_bbox = [IMG.xdim, 1, IMG.ydim, 1];

    % 1. Kmeans++
    IMG = U_Kmeans_plusplus(IMG, index, SP_bbox, num_SP, num_iter);
    SP_bbox = IMG.bbox;
    
    if (IMG.broken)
        IMG.max_E = -inf;
        IMG.ksplit = -2;
        IMG.new_ks = new_ks;
        return;
    end

    % 2. create two new SP from the old one
    % label matrix is equivalent to SP.pixels
    % we will mess around label matrix for new proposal
    % and recover it from SP.pixels if it doesn't work out
    % merge small connected component in the label matrix
    IMG = U_connect_newSP(IMG, index, SP_bbox, num_SP);

    % new super pixels in K+1 and K+2... old super pixel in index
    IMG.SP(index) = SP_empty(IMG.SP(index));

%    if (option==-1)
    % (index, new);
    E = move_split_calc_delta(IMG, IMG.SP(index), create_SP_new(IMG), IMG.SP(IMG.K+1), IMG.SP(IMG.K+2), IMG.SP_old(index), false);
    if (E>max_E)
        max_E = E;
        new_ks(1) = IMG.K+1;
        new_ks(2) = IMG.K+2;
        ksplit = -1;
    end
    % (new, index)
    E = move_split_calc_delta(IMG, IMG.SP(index), create_SP_new(IMG), IMG.SP(IMG.K+2), IMG.SP(IMG.K+1), false, IMG.SP_old(index));
    if (E>max_E)
        max_E = E;
        new_ks(1) = IMG.K+2;
        new_ks(2) = IMG.K+1;
        ksplit = -1;
    end
    % (index, old_empty) && (old_empty, index)
    for ktest=1:IMG.K
        if (ktest~=index && ktest<=numel(IMG.SP) && IMG.SP(ktest).N==0)
            E = move_split_calc_delta(IMG, IMG.SP(index), IMG.SP(ktest), IMG.SP(IMG.K+1), IMG.SP(IMG.K+2), IMG.SP_old(index), false);
            if (E>max_E)
                max_E = E;
                new_ks(1) = IMG.K+1;
                new_ks(2) = IMG.K+2;
                ksplit = ktest;
            end
            E = move_split_calc_delta(IMG, IMG.SP(index), IMG.SP(ktest), IMG.SP(IMG.K+2), IMG.SP(IMG.K+1), false, IMG.SP_old(index));
            if (E>max_E)
                max_E = E;
                new_ks(1) = K+2;
                new_ks(2) = K+1;
                ksplit = ktest;
            end
        end
    end
    IMG.max_E = max_E;
    IMG.ksplit = ksplit;
    IMG.new_ks = new_ks;
%     else
%         % for refine_move
%         % split into IMG.SP(index] and IMG.SP(option]
%         if (~IMG.SP_old(index) && ~IMG.SP_old(option))
%             SP1_total_pos = IMG.SP(IMG.K-1).pos.total;
%             N1 = IMG.SP(IMG.K-1).N;
%             SP2_total_pos = IMG.SP(IMG.K).pos.total;
%             N2 = IMG.SP(IMG.K).N;
%             SPK1_total_pos = IMG.SP(IMG.K+1).pos.total;
%             NK1 = IMG.SP(IMG.K+1).N;
%             SPK2_total_pos = IMG.SP(IMG.K+2).pos.total;
%             NK2 = IMG.SP(IMG.K+2).N;
% 
%             E_1_K1 = 0;
%             E_1_K2 = 0;
%             for d=1:2
%                 temp = SPK1_total_pos(d)/NK1 - SP1_total_pos(d)/N1;
%                 E_1_K1 = E_1_K1 + temp*temp;
%                 temp = SPK2_total_pos(d)/NK2 - SP2_total_pos(d)/N2;
%                 E_1_K1 = E_1_K1 + temp*temp;
% 
%                 temp = SPK1_total_pos(d)/NK1 - SP2_total_pos(d)/N2;
%                 E_1_K2 = + E_1_K2 + temp*temp;
%                 temp = SPK2_total_pos(d)/NK2 - SP1_total_pos(d)/N1;
%                 E_1_K2 = + E_1_K2 + temp*temp;
%             end
% 
%             if (E_1_K1 < E_1_K2)
%                 new_ks(1) = IMG.K+1;
%                 new_ks(2) = IMG.K+2;
%                 max_E = move_split_calc_delta(IMG, IMG.SP(index), IMG.SP(option), IMG.SP(IMG.K+1), IMG.SP(IMG.K+2), IMG.SP_old(index), IMG.SP_old(option));
%             else
%                 new_ks(1) = IMG.K+2;
%                 new_ks(2) = IMG.K+1;
%                 max_E = move_split_calc_delta(IMG, IMG.SP(index), IMG.SP(option), IMG.SP(IMG.K+2), IMG.SP(IMG.K+1), IMG.SP_old(index), IMG.SP_old(option));
%             end
%         else
%             E_1_K1 = move_split_calc_delta(IMG, IMG.SP(index), IMG.SP(option), IMG.SP(IMG.K+1), IMG.SP(IMG.K+2), IMG.SP_old(index), IMG.SP_old(option));
%             E_1_K2 = move_split_calc_delta(IMG, IMG.SP(index), IMG.SP(option), IMG.SP(IMG.K+2), IMG.SP(IMG.K+1), IMG.SP_old(index), IMG.SP_old(option));
% 
%             if (E_1_K1 > E_1_K2)
%                 new_ks(1) = IMG.K+1;
%                 new_ks(2) = IMG.K+2;
%                 max_E = E_1_K1;
%             else
%                 new_ks(1) = IMG.K+2;
%                 new_ks(2) = IMG.K+1;
%                 max_E = E_1_K2;
%             end
%        end
end


function dist = U_dist(vec1, vec2)
   dist = sum((vec1 - vec2).^2);
   dist = dist/10000;
end


function IMG = U_Kmeans_plusplus(IMG, index, bbox, num_SP, numiter)
    IMG.broken = false;
    true_pix = find(IMG.SP(index).pixels)';

    if (num_SP~=2)
        disp('Trying to split into more than 2');
    end

    num_pix = IMG.SP(index).N;
    distvec = zeros(length(IMG.SP(index).pixels),1);
    klabels = zeros(num_pix,1);
    center = zeros(num_SP, 5);

    %1. kmeans ++ initialization
    %first cener pt

    for tmp_pos=true_pix
        % get the Bounding Box of IMG.SP(index)
        [x, y] = get_x_and_y_from_index(tmp_pos, IMG.xdim);
        bbox(1) = min(x, bbox(1));
        bbox(2) = max(x, bbox(2));
        bbox(3) = min(y, bbox(3));
        bbox(4) = max(y, bbox(4));
    end
    IMG.bbox = bbox;

    old_split1 = IMG.SP_old(index);
    if ~old_split1 % new
        % first is new
        seed = randi(length(IMG.SP(index).pixels));
        while ~IMG.SP(index).pixels(seed)
            seed = randi(length(IMG.SP(index).pixels));
        end

        [x, y] = get_x_and_y_from_index(seed, IMG.xdim);
        if (IMG.label(x, y)~=index)
            disp('inconsistency about cluster label');
        end

        center(1,:) = IMG.data(seed,:);
        
        for pix=true_pix
            distvec(pix) = U_dist(IMG.data(pix,:), center(1,:));
        end

        % second is new
        %seed2 = randi(length(IMG.SP(index).pixels));
        %while ~IMG.SP(index).pixels(seed) || seed2 == seed
        %    seed2 = randi(length(IMG.SP(index).pixels));
        %end

        [~, seed2] = max(distvec);
        [x, y] = get_x_and_y_from_index(seed2, IMG.xdim);
        if (IMG.label(x, y)~=index)
            disp('inconsistency about cluster label');
        end
        center(2,:) = IMG.data(seed2,:);

    else %old
        center(1,1:2) = NormalD_calc_mean(IMG.SP(index).pos);
        center(1,3:5) = NormalD_calc_mean(IMG.SP(index).app);

        for pix=true_pix
            distvec(pix) = U_dist(IMG.data(pix,:), center(1,:));
        end

        % second is new
        [~, seed2] = max(distvec);
        [x, y] = get_x_and_y_from_index(seed2, IMG.xdim);
        if (IMG.label(x, y)~=index)
            disp('inconsistency about cluster label');
        end
        center(2,:) = IMG.data(seed2,:);

%     elseif (~old_split1 && old_split2) % new old
%         center(2,1:2) = IMG.SP(index2).pos.mean;
%         center(2,3:5) = IMG.SP(index2).app.mean;
% 
%         for pix=true_pix
%             distvec(pix) = U_dist(IMG.data(pix,:), center(2,:));
%         end
% 
%         % first is new
%         [~, seed] = max(distvec);
%         [x, y] = get_x_and_y_from_index(seed, IMG.xdim);
%         if (IMG.label(x, y)~=index)
%             disp('inconsistency about cluster label');
%         end
%         center(1,:) = IMG.data(seed,:);
% 
%     else % old old
%         center(1,1:2) = IMG.SP(index).pos.mean;
%         center(1,3:5) = IMG.SP(index).app.mean;
% 
%         center(2,1:2) = IMG.SP(index2).pos.mean;
%         center(2,3:5) = IMG.SP(index2).app.mean;
     end

    %2. kmeans ++ iterations
    change = false;
    for itr=1:numiter
        distvec = inf(length(IMG.SP(index).pixels),1);
        for pix=true_pix
            for i=1:num_SP
                tmp_dist = U_dist(IMG.data(pix,:), center(i,:));
                if(tmp_dist < distvec(pix) )
                    distvec(pix) = tmp_dist;
                    klabels(pix) = i;
                    change = true;
                end
            end
        end

        if ~change
            %no change happened... Kmeans totally stuck
            break;
        end

        center = zeros(num_SP, 5);
        SP_sz = zeros(num_SP, 1);


        for pix=true_pix
            %printf("dist %d,%d,%d,%d\n",r,c,counter,klabels[counter]);
            % klabels[n]==0 && old_split1 then don't update
            % klabels[n]==1 && old_split2 then don't update
            % if (klabels[n]!=old_split1-1 && klabels[n]!=old_split2-1)
            if (klabels(pix)~=1 || ~old_split1)
                center(klabels(pix), :) = center(klabels(pix), :) + IMG.data(pix, :);
            end
            SP_sz(klabels(pix)) = SP_sz(klabels(pix))+1;
        end

        for k=1:num_SP
            if SP_sz(k)>0
                if (k==1 && ~old_split1) || k==2
                    center(k, :) = center(k, :) / SP_sz(k);
                end
            else
                if old_split1
                    IMG.broken = true;
                else
                    disp('one cluster removed... shouldnt happen');
                end
            end
        end
    end

    if ~IMG.broken
        % change label accordingly
        for pix=true_pix
            [x, y] = get_x_and_y_from_index(pix, IMG.xdim);
            IMG.label(x, y) = IMG.K+klabels(pix);
        end
    end
end


% KMerge Version 2: grow region

function IMG = U_connect_newSP(IMG, old_k, bbox, num_SP)
    min_x = bbox(1);
    min_y = bbox(3);
    max_x = bbox(2);
    max_y = bbox(4);
    dx4 = [-1,  0,  1,  0];
    dy4 = [ 0, -1,  0,  1];

    new_label = false(IMG.xdim, IMG.ydim);
    label_count = 0;

    check_labels = (1:num_SP) + IMG.K;

    for x=min_x:max_x
        for y=min_y:max_y
            tmp_ind = get_index_from_x_and_y(x, y, IMG.xdim);
            curLabel = IMG.label(x, y);
            if any(curLabel==check_labels) && ~new_label(x, y)
                label_count = label_count + 1;

                new_label(x, y) = true;
                
                if ~SP_is_empty(IMG, IMG.K+label_count)
                    disp('SP should be null..');
                end
                IMG.SP(IMG.K+label_count) = new_SP(IMG.new_pos, IMG.new_app, IMG.max_UID, [0, 0], IMG.N, IMG.max_SPs);
                
                %can't decide whether it will be border yet
                pixel_bfs=zeros(size(IMG.SP(IMG.K+label_count).pixels));
                pixel_bfs_write=1;
                pixel_bfs_read=1;
                
                IMG.SP(IMG.K+label_count) = SP_add_pixel(IMG.SP(IMG.K+label_count), IMG.data, tmp_ind, false, IMG.boundary_mask(x, y));
                pixel_bfs(pixel_bfs_write) = tmp_ind;
                pixel_bfs_write = pixel_bfs_write+1;
                
                while(pixel_bfs_read < pixel_bfs_write)
                    pix = pixel_bfs(pixel_bfs_read);
                    [pix_x, pix_y] = get_x_and_y_from_index(pix, IMG.xdim);
                    for n=1:4
                        new_x = pix_x+dx4(n);
                        new_y = pix_y+dy4(n);
                        if (new_x >= min_x && new_x <= max_x) && (new_y >= min_y && new_y <= max_y)
                            new_ind = get_index_from_x_and_y(new_x, new_y, IMG.xdim);
                            if ~new_label(new_x, new_y) && IMG.label(new_x, new_y) == curLabel
                                % should always update labels before adding pixel, otherwise
                                % U_check_border_pix will be wrong!
                                new_label(new_x, new_y) = true;
                                IMG.label(new_x, new_y) = IMG.K+label_count;
                                IMG.SP(IMG.K + label_count) = SP_add_pixel(IMG.SP(IMG.K + label_count), IMG.data, new_ind, false, IMG.boundary_mask(new_x, new_y));
                                pixel_bfs(pixel_bfs_write) = new_ind;
                                pixel_bfs_write = pixel_bfs_write+1;
                            end
                        end
                    end
                    pixel_bfs_read = pixel_bfs_read+1;
                end
                IMG.label(x, y) = IMG.K+label_count;
            end
        end
    end

    % Now is the time to clean up the border pixels and neighbor ids
    
    % remove all neighbors of the original index
    for k=1:IMG.K
        IMG.SP(k).neighbors(old_k) = 0;
    end
    
    
    % loop through every pixel in the bounding box plus one pixel all around
    % set border and neighbor values
    for x=max(1, min_x-1):min(IMG.xdim, max_x+1)
        for y=max(1, min_y-1):min(IMG.ydim, max_y+1)
            k = IMG.label(x, y);
            if k>0
                index = get_index_from_x_and_y(x, y, IMG.xdim);
                is_border = U_check_border_pix(IMG, index, k);
                IMG.SP(k).borders(index) = is_border;
                if is_border
                    % 1:IMG.K are already set up for neighbor 1:IMG.K, so
                    % only update them for the new SPs
                    if k<=IMG.K
                        old_neighbors = IMG.SP(k).neighbors(1:IMG.K);
                    end
                    IMG.SP(k) = SP_update_neighbors_add_self(IMG.SP(k), IMG.label, index);
                    if k<=IMG.K
                        IMG.SP(k).neighbors(1:IMG.K) = old_neighbors;
                    end
                end
            end
        end
    end
    
    if (label_count>num_SP)
        %printf("oops... kmeans gives %d connected components\n",label_count);
        pix_counts = zeros(label_count, 1);
        for i=1:label_count
            pix_counts(i) = IMG.SP(IMG.K+i).N;
        end
        check_labels = (IMG.K+1):(IMG.K+label_count);
        
        [~, ind_counts] = sort(pix_counts, 1, 'ascend');
        
        neighbors = false(IMG.K+label_count, 1);
        for i=1:label_count-num_SP
            max_k = -1;
            max_E = -inf;
            
            [max_E, max_k] = move_merge_SP_propose_region(IMG, IMG.K+ind_counts(i), neighbors, check_labels, max_E, max_k);
            
            if(max_k==-1 || max_E==-1)
                disp('the redundant SP doesnt merge within the range');
                save('connect_newSP.mat');
            end
            
            IMG = U_set_label_from_SP_pixels(IMG, IMG.SP(IMG.K+ind_counts(i)), max_k);
            IMG = U_merge_SPs(IMG, max_k, IMG.K+ind_counts(i));
        end

        % relabel SPs
        %printf("relabel\n");
        max_k = IMG.K+1;
        for i=1:num_SP
            while SP_is_empty(IMG, max_k)
                max_k = max_k+1;
                if(max_k>IMG.max_SPs)
                    disp('there should be more nonempty SPs..\n');
                end
            end
            if max_k~=IMG.K+i
                %fetch stuff far behind to here
                IMG = U_set_label_from_SP_pixels(IMG, IMG.SP(max_k), IMG.K+i);
                IMG = U_merge_SPs(IMG, IMG.K+i, max_k);
                %printf("pair up %d,%d\n",(K+i),max_k);
                %relabel to the first two ...
            end
            max_k = max_k+1;
        end
    end
end


function [max_E, max_k] = move_merge_SP_propose_region(IMG, k, neighbors, check_labels, max_E, max_k)

    neighbors = U_find_border_SP(IMG, k, neighbors);

    % loop through all neighbors
    true_neighbors = find(neighbors)';
    for merge_k=intersect(true_neighbors, check_labels)
        % calculate the energy
        tmp_E = U_move_merge_calc_delta(IMG, k, merge_k);
        if(tmp_E>max_E)
            max_E = tmp_E;
            max_k = merge_k;
        end
    end
            
    if (max_k==-1)
        disp('move_merge_SP_propose_region: No neighbour found');
        save('propose.mat');
    end
end


% --------------------------------------------------------------------------
% -- move_split_calc_delta
% --   calculates the change in energy for
% -- (k1 U new_k1) && (k2 U new_k2) - (k1 U new_k1 U new_k) && (k2)
% --
% --   parameters:
% --     - SP1 : the SP that originates the splitting
% --     - SP2 : the SP to split to
% --     - new_SP1 : temporary SP that contains pixels that will go in k1
% --     - new_SP2 : temporary SP that contains pixels that will go in k2
% --     - SP1_old : indicates if SP1 is an old SP
% --     - SP2_old : indicates if SP2 is an old SP
% --------------------------------------------------------------------------
function prob = move_split_calc_delta(IMG, SP1, SP2, new_SP1, new_SP2, SP1_old, SP2_old)
    prob = SP_log_likelihood_test_merge1(SP1, new_SP1);
    prob = prob + SP_log_likelihood_test_merge1(SP2, new_SP2);
    prob = prob - SP_log_likelihood_test_merge2(SP1, new_SP1, new_SP2);
    prob = prob - SP2.log_likelihood;

    % split
    prob = prob + U_calc_model_order(IMG, SP1.N + new_SP1.N, SP1_old);
    prob = prob + U_calc_model_order(IMG, SP2.N + new_SP2.N, SP2_old);

    % not split
    prob = prob - U_calc_model_order(IMG, SP1.N + new_SP1.N + new_SP2.N, SP1_old);
    prob = prob - U_calc_model_order(IMG, SP2.N, SP2_old);
end