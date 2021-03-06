function [covariance, precision] = get_gp_covariance(mu, cov_var_a, cov_var_p, iid_var)

if (~exist('iid_var', 'var') || isempty(iid_var))
    iid_var = 0;
end

num_SPs = size(mu, 1);
covariance = zeros(num_SPs);
    
for SP_index=1:num_SPs
    covariance(SP_index, :) = exp( -sum(bsxfun(@minus, mu(:,1:2), mu(SP_index, 1:2))' .^2 / (2*cov_var_p)) ) .* ...
                       exp( -sum(bsxfun(@minus, mu(:,3:5), mu(SP_index, 3:5))' .^2 / (2*cov_var_a)) );
end

precision = (covariance + eye(num_SPs)*iid_var)^-1;