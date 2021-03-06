% --------------------------------------------------------------------------
% -- update_neighbors_label_add_check
% --   Checks to see if the neighbor count at index should be incremented
% -- by adding one neighbor of label neighbor_label. If so, it increments.
% -- The neighboring label should be changed before calling this function.
% -- The neighbor count should be incremented if there is exactly one
% -- neighbor with neighbor label.
% --
% --   parameters:
% --     - label : the label image
% --     - index : the index bordering the added pixel
% --     - (xdim,ydim) : dimensions of image
% --     - neighbor_label : the label of the neighbor to increment
% --------------------------------------------------------------------------
function SP = SP_update_neighbors_label_add_check(SP, label, x, y, neighbor_label)
    [xdim, ydim] = size(label);
    check = 0;
    if x>1 && label(x-1, y)==neighbor_label
        check = check+1;
    end
    if y>1 && label(x, y-1)==neighbor_label
        check = check+1;
    end
    if x<xdim && label(x+1, y)==neighbor_label
        check = check+1;
    end
    if y<ydim && label(x, y+1)==neighbor_label
        check = check+1;
    end
    if check==1
        SP.neighbors(neighbor_label) = SP.neighbors(neighbor_label) + 1;
    end
end