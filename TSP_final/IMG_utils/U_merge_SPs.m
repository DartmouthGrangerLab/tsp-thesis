% --------------------------------------------------------------------------
% -- merge_with
% --   Merges this SP with another one and empties the other one. Assumes
% -- the labels have already been updated correctly. Fixes borders.
% --
% --   parameters:
% --     - other : A pointer to the other SP to merge with
% --     - label : A pointer to the label image
% --     - border_ptr : the linked list borders to fix
% --     - (xdim, ydim) : image dimensions
% --------------------------------------------------------------------------
function IMG = U_merge_SPs(IMG, index, index_other)
    % update the MIW stuff
    IMG.SP(index).N = IMG.SP(index).N + IMG.SP(index_other).N;
    IMG.SP(index).pixels = IMG.SP(index).pixels + IMG.SP(index_other).pixels;
    IMG.SP(index).app = NormalD_merge(IMG.SP(index).app, IMG.SP(index_other).app);
    IMG.SP(index).pos = NormalD_merge(IMG.SP(index).pos, IMG.SP(index_other).pos);
    
    % update the border pixels
    IMG.SP(index) = SP_fix_borders(IMG.SP(index), IMG.label);
    
    %update neighbors' neighbors lists
    for n=find(IMG.SP(index_other).neighbors)'
        if IMG.SP(n).neighbors(index)>0
            IMG = U_fix_neighbors_self(IMG, n);
        else
            IMG.SP(n).neighbors(index) = IMG.SP(n).neighbors(index_other);
            IMG.SP(n).neighbors(index_other) = 0;
        end
    end
    
    %update index and index_other's neighbor lists
    IMG.SP(index).neighbors = IMG.SP(index).neighbors + IMG.SP(index_other).neighbors;
    IMG.SP(index).neighbors(index) = 0;
    IMG.SP(index).neighbors(index_other) = 0;
    
    IMG.SP(index) = SP_calculate_log_probs(IMG.SP(index));
    IMG.SP(index_other) = SP_empty(IMG.SP(index_other));
end