% --------------------------------------------------------------------------
% -- log_likelihood_switch_prior
% --   Calculates the likelihood for this SP if the prior is switched to
% -- the prior of the supplied SP
% --
% --   parameters:
% --     - new_prior: a pointer to the SP to switch priors with
% --------------------------------------------------------------------------
function logprob = SP_log_likelihood_switch_prior(SP, SP_new_prior, SP_new_prior_is_old)   

    %calculate pos switch prior
    total = SP.pos.total;
    total2 = SP.pos.total2;
    logprob = -3*(SP.N+0.5)*0.5*1.837877066409 - SP_new_prior.pos.sumlogDelta_div2;
    if ~SP_new_prior_is_old
        logprob = logprob + sum(total.*total./SP.N - total2)/2;
    else
        Delta = SP_new_prior.pos.Delta;
        theta = SP_new_prior.pos.theta;
        logprob = logprob + sum((Delta.*total.*total + 2*total.*theta - SP.N*theta.*theta) ./ (2*SP.N*Delta + 2) - total2/2);
    end

    %calculate app switch prior
    total = SP.app.total;
    total2 = SP.app.total2;
    logprob = logprob - 3*(SP.N+0.5)*0.5*1.837877066409 - SP_new_prior.app.sumlogDelta_div2;
    if ~SP_new_prior_is_old
        logprob = logprob + sum(total.*total./SP.N - total2)/2;
    else
        Delta = SP_new_prior.app.Delta;
        theta = SP_new_prior.app.theta;
        logprob = logprob + sum((Delta.*total.*total + 2*total.*theta - SP.N*theta.*theta) ./ (2*SP.N*Delta + 2) - total2/2);
    end
end