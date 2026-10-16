function [summary, figures, consumption] = simulate_ps_figures(mode, Ngrid, reps, mFixed, seed, workers, outputDirectory, traceM)
% SIMULATE_PS_FIGURES  Reproduce all PS/RP figures in one MATLAB file.
%
% Companion code for:
%   "The Remarkable Efficiency of the Probabilistic Serial Mechanism"
%
% Paper Figure 1:
%   PS versus RP as (i) object copies and (ii) object types increase.
%   The two panels are exported as fig1.pdf and fig2.pdf (also PNG/FIG).
%
% Paper Figure 2:
%   PS eating dynamics, surviving object types and cumulative average rank.
%   Exported as ps_eating_proof_fast.pdf (also PNG/FIG and CSV data).
%
% Exactly the original deferred-revelation simulations are retained.
% No full agent-by-object rankings are constructed; 2000 independent
% replications per economy and 2000 eating-process simulations by default.
% Both simulations reuse their own saved checkpoints when rerun.
%
% All graphics use: Helvetica 18 pt, 5.5 x 4.1 inches, identical
% blue/red palette, vector PDF and 300 dpi PNG; no plot titles.
%
% Usage:
%   simulate_ps_figures                   % both figures, 2000 replications
%   simulate_ps_figures('growth')         % only PS/RP comparison panels
%   simulate_ps_figures('consumption')    % only PS eating-process figure
%   simulate_ps_figures('check')          % sampler integrity tests
%   simulate_ps_figures('both', [], 2000, 100, 20260908, 8);
%   simulate_ps_figures('both', [], 2000, 100, 20260908, 0); % serial
%
% Parameters (all optional):
%   mode            'both', 'growth', 'consumption', or 'check'
%   Ngrid           total agents per growth economy (default:
%                   [100 200 500 1000 2000 5000 10000])
%   reps            profiles per mechanism and eating-process replications
%                   (default 2000)
%   mFixed          types in growing-copies panel (default 100)
%   seed            reproducibility seed (default 20260908)
%   workers         local process workers, 0 means serial (default 8)
%   outputDirectory result folder (default fresh_simulation_fast, alongside
%                   this file, preserving existing growth checkpoints)
%   traceM          object types = agents in eating simulation (default 2000)
%
% The output figures are saved to outputDirectory; the source code does not
% upload results automatically.

if nargin < 1 || isempty(mode), mode = 'both'; end
if nargin < 2 || isempty(Ngrid)
    Ngrid = [100 200 500 1000 2000 5000 10000];
end
if nargin < 3 || isempty(reps), reps = 2000; end
if nargin < 4 || isempty(mFixed), mFixed = 100; end
if nargin < 5 || isempty(seed), seed = 20260908; end
if nargin < 6 || isempty(workers), workers = 8; end
if nargin < 7 || isempty(outputDirectory)
    outputDirectory = fullfile(fileparts(mfilename('fullpath')), ...
        'fresh_simulation_fast');
end
if nargin < 8 || isempty(traceM), traceM = 2000; end

if isstring(mode), mode = char(mode); end
assert(ischar(mode), 'mode must be a string.');
mode = lower(strtrim(mode));
assert(ismember(mode,{'both','growth','consumption','check'}), ...
    'Choose both, growth, consumption, or check.');

summary = [];
figures = gobjects(0);
consumption = [];

if strcmp(mode,'check')
    self_check();
    return
end

if any(strcmp(mode,{'both','growth'}))
    legacyDirectory = fullfile(fileparts(mfilename('fullpath')), ...
        'fresh_simulation');
    [summary,figures] = simulate_ps_growth_core( ...
        Ngrid,reps,mFixed,seed,workers,outputDirectory,legacyDirectory);
end

if any(strcmp(mode,{'both','consumption'}))
    consumption = simulate_ps_eating_core( ...
        traceM,reps,seed,workers,outputDirectory);
end
end


function [summary, fig] = simulate_ps_growth_core(Ngrid, reps, mFixed, seed, workers, outputDirectory, legacyDirectory)
% Local function: growing-markets PS and RP simulation.
% Inputs:
%   Ngrid   total numbers of students
%           default: [100 200 500 1000 2000 5000 10000]
%   reps    TOTAL profiles PER mechanism PER economy; default: 2000
%   mFixed  school types in copies sequence; default: 100
%   seed    default: 20260908
%   workers default: 8; [] = automatic up to 4; 0 = serial
%   outputDirectory default: fresh_simulation_fast beside this file
%   legacyDirectory default: fresh_simulation beside this file
%                   pass '' explicitly to disable old-checkpoint import
%
% Examples:
%   simulate_ps_growth_fast
%   simulate_ps_growth_fast([100 500 1000],2000)
%   simulate_ps_growth_fast('check')
%
% SPEED:
% Preferences are revealed only when needed.
% No full N-by-m preference matrix is constructed.
% The samplers reproduce the finite-market distributions.
%
% CHECKPOINTS:
% Saved PS and RP observations are reused.
% Increasing reps extends the same sample.
% Keep the same output directory and seed to resume.
% Checkpoints are saved after every batch.
%


if nargin >= 1 && (ischar(Ngrid) || (isstring(Ngrid) && isscalar(Ngrid)))
    assert(strcmp(char(Ngrid),'check'), ...
        'The only text command is ''check''.');
    self_check;
    summary = [];
    fig = [];
    return
end

if nargin < 1 || isempty(Ngrid)
    Ngrid = [100 200 500 1000 2000 5000 10000];
end
if nargin < 2 || isempty(reps)
    reps = 2000;
end
if nargin < 3 || isempty(mFixed)
    mFixed = 100;
end
if nargin < 4 || isempty(seed)
    seed = 20260908;
end
if nargin < 5
    workers = 8;
end

baseDirectory = fileparts(mfilename('fullpath'));

if nargin < 6 || isempty(outputDirectory)
    outputDirectory = fullfile(baseDirectory,'fresh_simulation_fast');
end
if nargin < 7
    legacyDirectory = fullfile(baseDirectory,'fresh_simulation');
end

validateattributes(Ngrid,{'numeric'}, ...
    {'vector','real','finite','integer','positive','nonempty'});
validateattributes(reps,{'numeric'}, ...
    {'scalar','real','finite','integer','>=',2,'<',1e6});
validateattributes(mFixed,{'numeric'}, ...
    {'scalar','real','finite','integer','positive'});
validateattributes(seed,{'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative','<=',2^32-1});

Ngrid = sort(double(Ngrid(:)));
reps = double(reps);
mFixed = double(mFixed);
seed = double(seed);

assert(numel(unique(Ngrid)) == numel(Ngrid), ...
    'Ngrid must not contain duplicates.');
assert(all(mod(Ngrid,mFixed) == 0), ...
    'Every N must be a multiple of mFixed.');

if ~isempty(workers)
    validateattributes(workers,{'numeric'}, ...
        {'scalar','real','finite','integer','nonnegative'});
    workers = double(workers);
end

if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

K = numel(Ngrid);

panelCells = [repmat(mFixed,K,1),Ngrid/mFixed; ...
              Ngrid,ones(K,1)];

[cells,~,rowMap] = unique(panelCells,'rows','stable');

offsets = zeros(size(cells,1),1);
for c = 1:size(cells,1)
    offsets(c) = substream_offset(cells(c,1),cells(c,2));
end

% Reserve disjoint substream ranges for PS and RP.
assert(all(offsets + reps < 2^50), ...
    'Grid is too large for the reserved substream ranges.');

check_gap_sampler;

workerLimit = choose_workers(workers);
batchSize = max(20,4*max(1,workerLimit));

fprintf('\n%d profiles per economy; %d distinct economies.\n', ...
    reps,size(cells,1));
fprintf('Copies panel: m=%d; types panel: q=1. All students iid.\n', ...
    mFixed);
fprintf('BOTH PS and RP are simulated: %d profiles EACH per economy.\n', ...
    reps);
fprintf('Independent iid samples for the two mechanisms; saved PS profiles are reused.\n');
fprintf('RP formula is an additional check; the plotted RP curve is simulated.\n');
fprintf('Saving after each batch of at most %d profiles.\n',batchSize);
fprintf('Output: %s\n',outputDirectory);
fprintf('Working checkpoints: %s\n', ...
    checkpoint_directory(fullfile(outputDirectory,'checkpoint.mat')));

records = nan(size(cells,1),9);
fig = gobjects(2,1);
panelSaved = false(2,1);

for c = 1:size(cells,1)

    m = cells(c,1);
    q = cells(c,2);
    N = m*q;

    checkpoint = fullfile(outputDirectory, ...
        sprintf('fast_m%d_q%d_seed%d.mat',m,q,seed));

    state = load_checkpoint( ...
        checkpoint,m,q,seed,legacyDirectory,reps);

    state.psValues = state.psValues(:);

    if numel(state.psValues) < reps
        state.psValues(end+1:reps,1) = NaN;
    end

    if ~isfield(state,'rpCompleted')
        state.rpCompleted = 0;
        state.rpValues = nan(reps,1);
        state.rpSampler = 'iid_poisson_integer_ranks_v1';
    else
        state.rpValues = state.rpValues(:);
        if numel(state.rpValues) < reps
            state.rpValues(end+1:reps,1) = NaN;
        end
    end

    state.rpValues = state.rpValues(:);

    % Preserve recovered data immediately in a new snapshot.
    save_checkpoint(checkpoint,state);

    completed = min(state.completed,reps);
    rpCompleted = min(state.rpCompleted,reps);

    exactRP = rp_formula(m,q);

    fprintf('\nm=%d, q=%d, N=%d: PS %d/%d saved; RP %d/%d saved.\n', ...
        m,q,N,completed,reps,rpCompleted,reps);
    fprintf('  RP expected-rank formula: %.6f (validation only).\n', ...
        exactRP);

    if ~isempty(state.legacyFile)
        fprintf('  Includes %d imported profiles from the old simulator.\n', ...
            min(state.legacyCount,reps));
    end

    logFactorial = gammaln((0:m)' + 1);
    cellOffset = offsets(c);

    batchesDone = 0;
    cellTimer = tic;

    while completed < reps || rpCompleted < reps

        psIds = (completed+1):min(completed+batchSize,reps);
        rpIds = (rpCompleted+1):min(rpCompleted+batchSize,reps);

        nJobs = max(numel(psIds),numel(rpIds));

        psBatch = nan(nJobs,1);
        rpBatch = nan(nJobs,1);

        if workerLimit > 0

            parfor (j = 1:nJobs, workerLimit)

                stream = RandStream('mrg32k3a','Seed',seed);

                if j <= numel(psIds)
                    stream.Substream = cellOffset + psIds(j);
                    psBatch(j) = ps_iid_rank( ...
                        m,q,stream,logFactorial);
                end

                if j <= numel(rpIds)
                    stream.Substream = 2^50 + cellOffset + rpIds(j);
                    rpBatch(j) = rp_iid_rank( ...
                        m,q,stream,logFactorial);
                end

            end

        else

            for j = 1:nJobs

                stream = RandStream('mrg32k3a','Seed',seed);

                if j <= numel(psIds)
                    stream.Substream = cellOffset + psIds(j);
                    psBatch(j) = ps_iid_rank( ...
                        m,q,stream,logFactorial);
                end

                if j <= numel(rpIds)
                    stream.Substream = 2^50 + cellOffset + rpIds(j);
                    rpBatch(j) = rp_iid_rank( ...
                        m,q,stream,logFactorial);
                end

            end

        end

        if ~isempty(psIds)
            state.psValues(psIds) = psBatch(1:numel(psIds));
            completed = psIds(end);
            state.completed = completed;
        end

        if ~isempty(rpIds)
            state.rpValues(rpIds) = rpBatch(1:numel(rpIds));
            rpCompleted = rpIds(end);
            state.rpCompleted = rpCompleted;
        end

        save_checkpoint(checkpoint,state);
        batchesDone = batchesDone+1;

        ps = state.psValues(1:completed);
        rp = state.rpValues(1:rpCompleted);

        remainingBatches = ceil( ...
            max(reps-completed,reps-rpCompleted)/batchSize);

        eta = remainingBatches*toc(cellTimer)/batchesDone/60;

        fprintf(['  SAVED PS %d/%d: %.5f (SE %.5f) | ' ...
            'RP %d/%d: %.5f (SE %.5f) | ~%.1f min left\n'], ...
            completed,reps,mean(ps),std(ps,0)/sqrt(numel(ps)), ...
            rpCompleted,reps,mean(rp),std(rp,0)/sqrt(numel(rp)),eta);

    end

    ps = state.psValues(1:reps);
    rp = state.rpValues(1:reps);

    records(c,:) = [N,m,q,reps, ...
        mean(ps),std(ps,0)/sqrt(reps), ...
        mean(rp),std(rp,0)/sqrt(reps),exactRP];

    imported = (1:reps)' <= state.legacyCount;

    raw = table((1:reps)',ps,rp,imported, ...
        'VariableNames', ...
        {'replication_index','ps_rank','rp_rank', ...
         'ps_imported_from_old_run'});

    % Row numbers index independent PS and RP samples, not paired profiles.
    writetable(raw,fullfile(outputDirectory, ...
        sprintf('both_profiles_m%d_q%d_seed%d_B%d.csv', ...
        m,q,seed,reps)));

    fprintf(['  FINISHED: PS %.6f (SE %.6f); ' ...
        'RP SIMULATED %.6f (SE %.6f); RP formula %.6f.\n'], ...
        records(c,5:9));

    if records(c,8) > 0
        fprintf('  RP simulation minus formula: %.6f (%.2f Monte Carlo SEs).\n', ...
            records(c,7)-exactRP, ...
            (records(c,7)-exactRP)/records(c,8));
    end

    summary = make_summary(records,rowMap,K);

    writetable(summary,fullfile(outputDirectory, ...
        sprintf('growth_both_seed%d_B%d.csv',seed,reps)));

    % Save each figure immediately when its own sequence is complete.
    for panel = 1:2

        panelRows = rowMap((panel-1)*K+(1:K));

        if ~panelSaved(panel) ...
                && all(isfinite(records(panelRows,5))) ...
                && all(isfinite(records(panelRows,7)))

            fig(panel) = save_separate_figure( ...
                records(panelRows,:),panel,mFixed,Ngrid, ...
                outputDirectory,seed,reps);

            panelSaved(panel) = true;

        end

    end

end

summary = make_summary(records,rowMap,K);

csvFile = fullfile(outputDirectory, ...
    sprintf('growth_both_seed%d_B%d.csv',seed,reps));

writetable(summary,csvFile);

fprintf('\nDONE. %d PS profiles and %d RP profiles per economy.\n', ...
    reps,reps);

disp(summary);

fprintf('fig1 = more copies; fig2 = more types. Both curves are simulated.\n');
fprintf('Fresh results: %s\n',csvFile);

end


function summary = make_summary(records,rowMap,K)

summary = array2table(records(rowMap,:), ...
    'VariableNames', ...
    {'N','m','q','profiles','ps_mean','ps_se', ...
     'rp_sim_mean','rp_sim_se','rp_exact'});

summary.path = [repmat({'seats'},K,1); ...
                repmat({'schools'},K,1)];

summary.gap = summary.rp_sim_mean-summary.ps_mean;

% Independent samples for the two mechanisms.
summary.gap_se = sqrt(summary.ps_se.^2+summary.rp_sim_se.^2);

summary = summary(:, ...
    {'path','N','m','q','profiles','ps_mean','ps_se', ...
     'rp_sim_mean','rp_sim_se','rp_exact','gap','gap_se'});

end


function value = rp_iid_rank(m,q,stream,lf)
% Exact finite-market simulation with deferred iid preferences.
%
% At each RP turn, the preferred available type is uniform over
% available types, independently of its rank in the student's ranking.
%
% Stopped rate-one Poisson clocks generate the type-choice sequence.
% Each type has q clock rings; its last ring exhausts that type.
%
% We then draw an actual INTEGER preference rank at every turn.

N = m*q;

if m == 1
    value = 1;
    return
end

if q == 1

    activeCounts = (m:-1:1)';

else

    times = cumsum(-log(max(rand(stream,q,m),realmin)),1);

    [~,order] = sort(times(:));

    isLastRing = mod(order,q) == 0;

    activeCounts = m-[0;cumsum(isLastRing(1:end-1))];

    assert(sum(isLastRing) == m, ...
        'RP clock simulation failed.');

end

ranks = rp_integer_ranks( ...
    m,activeCounts,rand(stream,N,1),lf);

value = mean(ranks);

assert(value >= 1 && value <= m, ...
    'RP rank is out of range.');

end


function ranks = rp_integer_ranks(m,a,u,lf)
% Minimum position of a uniform a-subset of the m preference positions.
%
% P(rank > d | a) = choose(m-d,a) / choose(m,a).
%
% a may differ across turns.
% Binary search avoids constructing full preference permutations.

a = a(:);
u = u(:);

lo = zeros(size(a));
hi = m-a+1;

base = lf(m+1)-lf(m-a+1);
logU = log(u);

pending = find(hi-lo > 1);

while ~isempty(pending)

    mid = floor((lo(pending)+hi(pending))/2);
    z = m-mid;

    logSurvival = lf(z+1)-lf(z-a(pending)+1)-base(pending);

    left = logSurvival <= logU(pending);

    hi(pending(left)) = mid(left);
    lo(pending(~left)) = mid(~left);

    pending = pending(hi(pending)-lo(pending) > 1);

end

ranks = hi;

end


function value = ps_iid_rank(m,q,stream,logFactorial,firstChoice)
% Deferred decisions for independent uniform preference permutations.
%
% After revealed rank r, L=m-r preference positions remain.
% The a available schools occupy a uniform a-subset of those positions.
% Therefore the next rank increment D satisfies
%
% P(D>d) = choose(L-d,a) / choose(L,a).
%
% The next school's identity is uniform among available schools,
% independently of the rank increment.
%
% These conditional draws reveal one fixed latent iid profile.
% They do not redraw preferences at each exhaustion event.

N = m*q;

if nargin < 5
    choice = randi(stream,m,N,1);
else
    choice = firstChoice(:);
end

rank = ones(N,1);
counts = accumarray(choice,1,[m,1]);
remaining = q*ones(m,1);
available = true(m,1);

rankSum = N;
rankMass = 0;
elapsed = 0;

tolerance = 1e-11*max(1,q);

while any(available)

    eating = find(counts > 0);

    dt = min(remaining(eating)./counts(eating));

    assert(isfinite(dt) && dt >= 0, ...
        'Invalid PS event time.');

    rankMass = rankMass + dt*rankSum;
    elapsed = elapsed + dt;

    remaining(eating) = remaining(eating)-dt*counts(eating);

    exhausted = available & remaining <= tolerance;

    assert(any(exhausted), ...
        'No school exhausted at a PS event.');

    remaining(exhausted) = 0;
    available(exhausted) = false;
    counts(exhausted) = 0;

    active = find(available);
    a = numel(active);

    if a == 0
        break
    end

    moving = find(exhausted(choice));

    L = m-rank(moving);

    assert(all(L >= a), ...
        'Inconsistent revealed preference prefix.');

    increment = minimum_position( ...
        L,a,rand(stream,numel(moving),1),logFactorial);

    rank(moving) = rank(moving)+increment;
    rankSum = rankSum+sum(increment);

    choice(moving) = active(randi(stream,a,numel(moving),1));

    counts = counts + accumarray(choice(moving),1,[m,1]);

end

value = rankMass/N;

assert(abs(elapsed-1) < 1e-7, ...
    'PS did not allocate one unit per student.');

assert(value >= 1-1e-8 && value <= m+1e-8, ...
    'PS rank is out of range.');

end


function D = minimum_position(L,a,u,lf)
% Inverse survival function of the minimum of a uniform a-subset of 1:L.

if a == 1
    D = min(L,1+floor((1-u).*L));
    return
end

lo = zeros(size(L));
hi = L-a+1;

logU = log(u);
base = lf(L+1)-lf(L-a+1);

pending = find(hi-lo > 1);

while ~isempty(pending)

    mid = floor((lo(pending)+hi(pending))/2);
    z = L(pending)-mid;

    logSurvival = lf(z+1)-lf(z-a+1)-base(pending);

    left = logSurvival <= logU(pending);

    hi(pending(left)) = mid(left);
    lo(pending(~left)) = mid(~left);

    pending = pending(hi(pending)-lo(pending) > 1);

end

D = hi;

end


function offset = substream_offset(m,q)
% Cantor pairing of (m-1,q-1), reserving 10^6 substreams per economy.

s = m+q-2;
offset = (s*(s+1)/2 + q-1)*1e6;

end


function n = choose_workers(requested)
% Never create a remote pool or close/resize an existing pool.

hasToolbox = license('test','Distrib_Computing_Toolbox') ...
    && ~isempty(ver('parallel'));

if isequal(requested,0) || (~hasToolbox && isempty(requested))
    n = 0;
    fprintf('Using the serial fast algorithm (no parallel pool).\n');
    return
end

assert(hasToolbox, ...
    ['Parallel Computing Toolbox is unavailable. ' ...
     'Pass 0 as the fifth input to use the fast serial algorithm.']);

pool = gcp('nocreate');

if isempty(requested)
    requested = 4;
end

if isempty(pool)

    cluster = parcluster('local');
    requested = min(requested,cluster.NumWorkers);

    fprintf('Starting a local pool with %d workers...\n',requested);

    pool = parpool(cluster,requested);

elseif isa(pool,'parallel.ThreadPool')

    error('Use a local process pool, or pass 0 as the fifth input.');

end

if isprop(pool,'Cluster')

    assert(isa(pool.Cluster,'parallel.cluster.Local'), ...
        ['An external pool is open. Pass 0 for serial ' ...
         'or select a local pool yourself.']);

else

    error('Unrecognized pool type. Pass 0 as the fifth input for serial execution.');

end

n = min(requested,pool.NumWorkers);

fprintf('Using at most %d local parallel workers.\n',n);

end


function state = load_checkpoint(file,m,q,seed,legacyDirectory,reps)

[directory,sourceDirectory,stem] = checkpoint_directory(file);

snapshots = dir(fullfile(directory,[stem '_completed*.mat']));

% Sort numerically by both completion counts.
% Old PS-only filenames represent zero RP simulations.
if ~isempty(snapshots)

    progress = zeros(numel(snapshots),2);

    for j = 1:numel(snapshots)

        psToken = regexp(snapshots(j).name, ...
            '_completed(\d+)_','tokens','once');

        rpToken = regexp(snapshots(j).name, ...
            '_rp(\d+)_','tokens','once');

        if ~isempty(psToken)
            progress(j,1) = str2double(psToken{1});
        end

        if ~isempty(rpToken)
            progress(j,2) = str2double(rpToken{1});
        end

    end

    [~,order] = sortrows(progress,[-1 -2]);
    snapshots = snapshots(order);

end

for j = 1:numel(snapshots)

    candidate = fullfile(snapshots(j).folder,snapshots(j).name);

    try

        saved = load(candidate,'state','checkpointComplete');

        if ~isfield(saved,'checkpointComplete') ...
                || ~isequal(saved.checkpointComplete,true) ...
                || ~isfield(saved,'state') ...
                || ~valid_checkpoint(saved.state,m,q,seed)

            error('Checkpoint:Incomplete','Incomplete checkpoint.');

        end

    catch problem

        warning('PS:SkippedCheckpoint', ...
            'Skipping unreadable snapshot %s: %s', ...
            candidate,problem.message);

        continue

    end

    state = saved.state;

    assert(isfield(state,'checkpointSource') ...
        && strcmp(state.checkpointSource,sourceDirectory), ...
        'Checkpoint directory identity mismatch; no data have been overwritten.');

    return

end

% Migration from old fast checkpoints, backups and temporary files.
% Keep one longest valid sample; never concatenate overlapping prefixes.
oldFiles = [dir(fullfile(sourceDirectory,'*.mat')); ...
            dir(fullfile(sourceDirectory,'*.mat.previous'))];

best = [];
bestCount = -1;
bestRP = -1;

for j = 1:numel(oldFiles)

    candidate = fullfile(oldFiles(j).folder,oldFiles(j).name);

    try

        variables = whos('-file',candidate);

        if ~any(strcmp({variables.name},'state'))
            continue
        end

        saved = load(candidate,'-mat','state');

        if isfield(saved,'state') && valid_checkpoint(saved.state,m,q,seed)

            countRP = 0;

            if isfield(saved.state,'rpCompleted')
                countRP = saved.state.rpCompleted;
            end

            if saved.state.completed > bestCount ...
                    || (saved.state.completed == bestCount ...
                    && countRP > bestRP)

                best = saved.state;
                bestCount = best.completed;
                bestRP = countRP;

            end

        end

    catch problem

        warning('PS:SkippedOldCheckpoint', ...
            'Could not read old checkpoint %s: %s', ...
            candidate,problem.message);

    end

end

if ~isempty(best)

    state = best;

    fprintf('Recovered %d saved profiles for m=%d, q=%d.\n', ...
        bestCount,m,q);

    return

end

if ~isempty(snapshots) || isfile(file) || isfile([file '.previous'])

    error('PS:NoReadableCheckpoint', ...
        ['Existing checkpoints were found but none could be read and validated. ' ...
         'Original files have been kept. The simulator will not restart this cell at zero.']);

end

state = struct( ...
    'version',1, ...
    'm',m, ...
    'q',q, ...
    'seed',seed, ...
    'completed',0, ...
    'psValues',nan(reps,1), ...
    'legacyCount',0, ...
    'legacyFile','');

if isempty(legacyDirectory) || ~isfolder(legacyDirectory)
    return
end

files = dir(fullfile(legacyDirectory, ...
    sprintf('checkpoint_m%d_q%d_B*_seed%d.mat',m,q,seed)));

bestCount = 0;

for j = 1:numel(files)

    candidate = fullfile(files(j).folder,files(j).name);

    old = load(candidate,'m','q','seed','completed','psValues');

    if ~all(isfield(old,{'m','q','seed','completed','psValues'}))
        continue
    end

    if old.m ~= m || old.q ~= q || old.seed ~= seed
        continue
    end

    count = min(double(old.completed),reps);

    if ~isscalar(count) || count < 0 || count ~= floor(count) ...
            || count <= bestCount || numel(old.psValues) < count
        continue
    end

    values = double(old.psValues(1:count));

    if ~all(isfinite(values) & values >= 1-1e-8 & values <= m+1e-8)
        continue
    end

    bestCount = count;

    state.psValues(1:count) = values(:);
    state.completed = count;
    state.legacyCount = count;
    state.legacyFile = candidate;

end

end


function save_checkpoint(file,state)
% Write a new snapshot; do not replace, rename or delete old checkpoints.

[directory,sourceDirectory,stem] = checkpoint_directory(file);

assert(valid_checkpoint(state,state.m,state.q,state.seed), ...
    'Refusing to save an invalid checkpoint.');

state.checkpointSource = sourceDirectory;

[~,token] = fileparts(tempname(directory));

countRP = 0;
if isfield(state,'rpCompleted')
    countRP = state.rpCompleted;
end

snapshot = fullfile(directory, ...
    sprintf('%s_completed%09d_rp%09d_%s.mat', ...
    stem,state.completed,countRP,token));

assert(~isfile(snapshot), ...
    'Snapshot name collision; previous files are intact.');

checkpointComplete = true; %#ok<NASGU>

save(snapshot,'state','checkpointComplete','-v7');

% Partial writes are skipped on restart.
% The caller prints SAVED only after this function returns.

end


function ok = valid_checkpoint(state,m,q,seed)

required = {'version','m','q','seed','completed','psValues', ...
            'legacyCount','legacyFile'};

ok = isstruct(state) && isscalar(state) ...
    && all(isfield(state,required));

if ~ok
    return
end

ok = isequal(state.version,1) ...
    && isequal(state.m,m) ...
    && isequal(state.q,q) ...
    && isequal(state.seed,seed) ...
    && isnumeric(state.completed) ...
    && isscalar(state.completed) ...
    && isreal(state.completed) ...
    && isfinite(state.completed) ...
    && state.completed >= 0 ...
    && state.completed == floor(state.completed) ...
    && isnumeric(state.psValues) ...
    && isreal(state.psValues) ...
    && isvector(state.psValues) ...
    && state.completed <= numel(state.psValues) ...
    && isnumeric(state.legacyCount) ...
    && isscalar(state.legacyCount) ...
    && isreal(state.legacyCount) ...
    && isfinite(state.legacyCount) ...
    && state.legacyCount >= 0 ...
    && state.legacyCount == floor(state.legacyCount) ...
    && state.legacyCount <= state.completed;

if ~ok
    return
end

values = state.psValues(1:state.completed);

ok = all(isfinite(values(:)) ...
    & values(:) >= 1-1e-8 & values(:) <= m+1e-8);

if ~ok
    return
end

if any(isfield(state,{'rpCompleted','rpValues','rpSampler'}))

    ok = all(isfield(state,{'rpCompleted','rpValues','rpSampler'}));

    if ~ok
        return
    end

    ok = isequal(state.rpSampler,'iid_poisson_integer_ranks_v1') ...
        && isnumeric(state.rpCompleted) ...
        && isreal(state.rpCompleted) ...
        && isscalar(state.rpCompleted) ...
        && isfinite(state.rpCompleted) ...
        && state.rpCompleted >= 0 ...
        && state.rpCompleted == floor(state.rpCompleted) ...
        && isnumeric(state.rpValues) ...
        && isreal(state.rpValues) ...
        && isvector(state.rpValues) ...
        && state.rpCompleted <= numel(state.rpValues);

    if ~ok
        return
    end

    values = state.rpValues(1:state.rpCompleted);

    ok = all(isfinite(values(:)) ...
        & values(:) >= 1-1e-8 & values(:) <= m+1e-8);

end

end


function [directory,sourceDirectory,stem] = checkpoint_directory(file)

[sourceDirectory,stem] = fileparts(file);

[ok,attributes] = fileattrib(sourceDirectory);

assert(ok,'The results directory must exist before saving checkpoints.');

sourceDirectory = attributes.Name;

if ispc
    sourceDirectory = lower(sourceDirectory);
end

% Keep the same hashes as the earlier version to find saved PS results.
codes = double(unicode2native(sourceDirectory,'UTF-8'));

h1 = 0;
h2 = 0;

for j = 1:numel(codes)
    h1 = mod(h1*65599 + codes(j),4294967291);
    h2 = mod(h2*131 + codes(j),4294967279);
end

key = [dec2hex(h1,8) dec2hex(h2,8)];

checkpointRoot = getenv('LOCALAPPDATA');

if ~ispc || isempty(checkpointRoot)
    checkpointRoot = prefdir;
end

directory = fullfile(checkpointRoot,'PS_growth_checkpoints',key);

if ~isfolder(directory)
    [ok,message] = mkdir(directory);
    assert(ok,'Could not create local checkpoint directory: %s',message);
end

end


function value = rp_formula(m,q)
% Validation only. Does not supply the plotted RP observations.

if m == 1
    value = 1;
    return
end

if q == 1
    value = (m+1)/m*sum(1./(1:m))-1;
    return
end

k = (1:m)';

f = @(u) rp_integrand(u,q,k);

options = {'ArrayValued',true,'AbsTol',2e-10,'RelTol',2e-10};

value = integral(f,0,1,options{:}) ...
      + integral(f,1,Inf,options{:});

end


function value = rp_integrand(u,q,k)

p = gammainc(q*u,q,'upper');

if p >= 1
    value = 1;
elseif p <= 0
    value = 0;
else
    value = mean(-expm1(k.*log1p(-p)));
end

end


function fig = save_separate_figure(R,panel,mFixed,Ngrid,out,seed,reps)
% R columns:
% N, m, q, profiles, PS mean, PS SE, RP mean, RP SE, RP expectation.

R = sortrows(R,1);

N = R(:,1);
ps = R(:,5);
se = R(:,6);
rp = R(:,7);
rpSE = R(:,8);

blue = [0.12 0.36 0.59];
red = [0.72 0.24 0.18];
shade = [0.94 0.90 0.86];

if panel == 1

    name = 'fig1';
   

else

    name = 'fig2';
   

end

% The reference affects axis scaling only, not either plotted curve.
referenceTop = rp_formula(max(Ngrid),1);

yMax = max(2,ceil(2*(max( ...
    [referenceTop;rp+1.96*rpSE;ps+1.96*se])+0.3))/2);

fig = figure( ...
    'Color','w', ...
    'Visible','on', ...
    'Units','inches', ...
    'Position',[1 1 5.5 4.1], ...
    'Renderer','painters', ...
    'NumberTitle','off');

ax = axes('Parent',fig,'Position',[0.14 0.23 0.81 0.62]);

hold(ax,'on');

if numel(N) > 1
    patch(ax,[N;flipud(N)],[ps;flipud(rp)],shade, ...
        'EdgeColor','none','HandleVisibility','off');
end

hRP = errorbar(ax,N,rp,1.96*rpSE,'-o', ...
    'Color',red, ...
    'LineWidth',1.65, ...
    'MarkerFaceColor','w', ...
    'MarkerSize',5, ...
    'CapSize',4);

hPS = errorbar(ax,N,ps,1.96*se,'-s', ...
    'Color',blue, ...
    'LineWidth',3, ...
    'MarkerFaceColor','w', ...
    'MarkerSize',5, ...
    'CapSize',4);

tickIndices = unique(round( ...
    linspace(1,numel(Ngrid),min(4,numel(Ngrid)))));

ticks = Ngrid(tickIndices);

tickLabels = arrayfun(@(x)sprintf('%g',x),ticks, ...
    'UniformOutput',false);

set(ax, ...
    'XScale','log', ...
    'XLim',[min(Ngrid)/1.12 max(Ngrid)*1.12], ...
    'YLim',[0.8 yMax], ...
    'XTick',ticks, ...
    'XTickLabel',tickLabels, ...
    'FontName','Helvetica', ...
    'FontSize',18, ...
    'TickDir','out', ...
    'Box','off', ...
    'YGrid','on', ...
    'GridAlpha',0.10, ...
    'Layer','top');

xlabel(ax,'Agents');
ylabel(ax,'Average rank');

legend(ax,[hRP hPS], ...
    {'RP (simulation)','PS (simulation)'}, ...
    'Location','northwest','Box','off','FontSize',9);


drawnow;

prefix = fullfile(out,name);

set(fig, ...
    'PaperUnits','inches', ...
    'PaperSize',[5.5 4.1], ...
    'PaperPosition',[0 0 5.5 4.1]);

savefig(fig,[prefix '.fig']);
print(fig,[prefix '.pdf'],'-dpdf','-painters');
print(fig,[prefix '.png'],'-dpng','-r300');

fprintf('SAVED %s as PDF, PNG and FIG: %s\n',prefix);

end


function check_gap_sampler
% Exhaust every feasible minimum for all 1 <= a <= L <= 24.

lf = gammaln((0:24)' + 1);

for L = 1:24

    for a = 1:L

        d = (1:L-a+1)';

        survivalBefore = arrayfun( ...
            @(x)nchoosek(L-x+1,a)/nchoosek(L,a),d);

        survivalAfter = [survivalBefore(2:end);0];

        u = (survivalBefore+survivalAfter)/2;

        sampled = minimum_position( ...
            repmat(L,size(d)),a,u,lf);

        assert(isequal(sampled,d), ...
            'Rank-increment inverse sampling failed.');

        sampledRP = rp_integer_ranks( ...
            L,repmat(a,size(d)),u,lf);

        assert(isequal(sampledRP,d), ...
            'RP integer-rank inverse sampling failed.');

    end

end

end


function self_check

check_gap_sampler;

stream = RandStream('mrg32k3a','Seed',741);

% With two types, first choices specify the entire preference lists.
for q = 1:5

    N = 2*q;
    values = zeros(2^N,1);
    lf = gammaln((0:2)' + 1);

    for mask = 0:2^N-1

        first = 1+double(bitget(uint32(mask),1:N));

        values(mask+1) = ps_iid_rank(2,q,stream,lf,first);

    end

    target = 1+0.5*nchoosek(2*q,q)/4^q;

    assert(abs(mean(values)-target) < 1e-10, ...
        'Exhaustive two-type PS check failed.');

    assert(abs(rp_formula(2,q)-target) < 1e-8, ...
        'RP formula check failed.');

end

% Reusing a substream must reproduce a profile.
lf = gammaln((0:50)' + 1);
offset = substream_offset(50,2);

stream.Substream = offset+1;
first = ps_iid_rank(50,2,stream,lf);

stream.Substream = offset+2;
ps_iid_rank(50,2,stream,lf);

stream.Substream = offset+1;
repeated = ps_iid_rank(50,2,stream,lf);

assert(first == repeated, ...
    'Substream reproducibility failed.');

stream.Substream = 2^50+offset+1;
firstRP = rp_iid_rank(50,2,stream,lf);

stream.Substream = 2^50+offset+2;
rp_iid_rank(50,2,stream,lf);

stream.Substream = 2^50+offset+1;
repeatedRP = rp_iid_rank(50,2,stream,lf);

assert(firstRP == repeatedRP, ...
    'RP substream reproducibility failed.');

fprintf(['Passed both integer-rank samplers, exhaustive PS, ' ...
    'RP formula and reproducibility checks.\n']);

end


function stats = simulate_ps_eating_core(m, reps, seed, workers, outputDirectory)
% PS eating trace: same deferred-decision sampler used above.
%
% Uses the identical deferred-decision PS sampler from the growth code
% (the user-provided fast MATLAB code), modified to retain the eating trace.
% It never constructs an N-by-m preference matrix. The conditional rank
% increments are sampled from the minimum position of a uniform subset.
%
% Defaults: m = n = 2000, q = 1, reps = 2000, seed = 20260908,
%           workers = 8 (0 = serial), output in this file's directory.
%
% Usage:
%   stats = simulate_ps_eating_fast;
%   stats = simulate_ps_eating_fast(2000,2000,20260908,8);
%   stats = simulate_ps_eating_fast(2000,2000,20260908,0); % no toolbox
%
% OUTPUT:
%   ps_eating_proof_fast.pdf (vector), .png (300 dpi), .fig
%   ps_eating_proof_fast.csv (averaged time-series)
%   ps_eating_proof_fast_summary.csv (three stage contributions)
%
% No title, no in-plot annotations, no legend. The only threshold marks
% are the dotted vertical lines at average times 50% and 10% of goods remain.
%
% Checkpoints are saved separately after each batch, so an interrupted
% 2000-replication run can be restarted without losing completed work.
%
% For m=2000, two mechanisms are NOT being simulated: only PS, q=1.

if nargin < 1 || isempty(m), m = 2000; end
if nargin < 2 || isempty(reps), reps = 2000; end
if nargin < 3 || isempty(seed), seed = 20260908; end
if nargin < 4 || isempty(workers), workers = 8; end
if nargin < 5 || isempty(outputDirectory)
    outputDirectory = fileparts(mfilename('fullpath'));
end

validateattributes(m, {'numeric'}, {'scalar','integer','>=',2});
validateattributes(reps, {'numeric'}, {'scalar','integer','>=',2});
validateattributes(seed, {'numeric'}, {'scalar','integer','>=',0,'<=',2^32-1});
validateattributes(workers, {'numeric'}, {'scalar','integer','>=',0});
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

% Dense toward time 1: the last available goods disappear very quickly.
tGrid = unique([linspace(0,0.95,220), ...
                linspace(0.95,0.995,180), ...
                1-logspace(-6,-2,250), 1]);
nGrid = numel(tGrid);

% Keep the original simulator's random substream convention.
cellOffset = substream_offset(m,1);
assert(cellOffset + reps < 2^50, 'Substream range exhausted.');
logFactorial = gammaln((0:m)' + 1);

nWorkers = choose_local_workers(workers);
batchSize = max(40, 5*max(1,nWorkers));
nBatches = ceil(reps/batchSize);

survivalTotal = zeros(1,nGrid);
rankTotal = zeros(1,nGrid);
cutTimes = zeros(reps,2);           % crossing of 50% and 10% survival
stageContributions = zeros(reps,3); % >50%, 10-50%, <=10%
wholeRank = zeros(reps,1);

fprintf('Simulating PS: m=n=%d, q=1, %d iid profiles, %d workers.\n', ...
    m,reps,nWorkers);
for b = 1:nBatches
    from = (b-1)*batchSize + 1;
    to = min(reps,b*batchSize);
    ids = from:to;
    B = numel(ids);
    checkpoint = fullfile(outputDirectory, sprintf( ...
        'ps_trace_m%d_seed%d_rep%05d-%05d.mat',m,seed,from,to));

    if isfile(checkpoint)
        saved = load(checkpoint,'saved_m','saved_seed','saved_ids', ...
            'saved_tGrid','blockSurvival','blockRank', ...
            'blockCuts','blockStages','blockTotals');
        assert(isequal(saved.saved_m,m) && isequal(saved.saved_seed,seed) ...
            && isequal(saved.saved_ids,ids) ...
            && isequal(saved.saved_tGrid,tGrid), ...
            'Checkpoint parameters do not match this run: %s',checkpoint);
        blockSurvival = saved.blockSurvival;
        blockRank = saved.blockRank;
        blockCuts = saved.blockCuts;
        blockStages = saved.blockStages;
        blockTotals = saved.blockTotals;
        fprintf('Restored %d/%d: %d profiles.\n',b,nBatches,B);
    else
        blockSurvival = zeros(B,nGrid);
        blockRank = zeros(B,nGrid);
        blockCuts = zeros(B,2);
        blockStages = zeros(B,3);
        blockTotals = zeros(B,1);

        if nWorkers > 0
            parfor (j = 1:B, nWorkers)
                stream = RandStream('mrg32k3a','Seed',seed);
                stream.Substream = cellOffset + ids(j);
                [start,alive,duration,rankFlow] = ...
                    ps_iid_trace(m,stream,logFactorial);
                [ss,rr,cc,stage,total] = trace_on_grid( ...
                    start,alive,duration,rankFlow,m,tGrid);
                blockSurvival(j,:) = ss;
                blockRank(j,:) = rr;
                blockCuts(j,:) = cc;
                blockStages(j,:) = stage;
                blockTotals(j) = total;
            end
        else
            for j = 1:B
                stream = RandStream('mrg32k3a','Seed',seed);
                stream.Substream = cellOffset + ids(j);
                [start,alive,duration,rankFlow] = ...
                    ps_iid_trace(m,stream,logFactorial);
                [ss,rr,cc,stage,total] = trace_on_grid( ...
                    start,alive,duration,rankFlow,m,tGrid);
                blockSurvival(j,:) = ss;
                blockRank(j,:) = rr;
                blockCuts(j,:) = cc;
                blockStages(j,:) = stage;
                blockTotals(j) = total;
            end
        end

        % Atomic checkpoint write: old batches are never overwritten.
        saved_m = m; saved_seed = seed;
        saved_ids = ids; saved_tGrid = tGrid;
        tempCheckpoint = [tempname(outputDirectory) '.mat'];
        save(tempCheckpoint,'saved_m','saved_seed','saved_ids', ...
            'saved_tGrid','blockSurvival','blockRank', ...
            'blockCuts','blockStages','blockTotals','-v7');
        [ok,msg] = movefile(tempCheckpoint,checkpoint);
        assert(ok,'Cannot save checkpoint: %s',msg);
        fprintf('Saved %d/%d: %d profiles.\n',b,nBatches,B);
    end

    survivalTotal = survivalTotal + sum(blockSurvival,1);
    rankTotal = rankTotal + sum(blockRank,1);
    cutTimes(ids,:) = blockCuts;
    stageContributions(ids,:) = blockStages;
    wholeRank(ids) = blockTotals;
end

meanSurvival = survivalTotal/reps;
meanCumulativeRank = rankTotal/reps;
t50 = mean(cutTimes(:,1));
t10 = mean(cutTimes(:,2));
meanStage = mean(stageContributions,1);

% Exact conservation check: each replication's cumulative contribution
% equals its final average rank and the sum of its three stage contributions.
assert(max(abs(sum(stageContributions,2)-wholeRank)) < 1e-7, ...
    'Stage contributions do not sum to total average rank.');
assert(abs(meanCumulativeRank(end)-mean(wholeRank)) < 1e-7, ...
    'Cumulative curve does not end at mean average rank.');

% Match the typography, dimensions, and palette of the growth figures.
% The figure is intentionally untitled, with no in-plot annotations.
blue = [0.12 0.36 0.59];
red  = [0.72 0.24 0.18];

fig = figure('Color','w','Visible','on','Renderer','painters', ...
    'Units','inches','Position',[1 1 5.5 4.1], ...
    'NumberTitle','off');
ax = axes('Parent',fig,'Position',[0.19 0.23 0.63 0.62]);

yyaxis(ax,'left');
plot(ax,tGrid,meanSurvival,'LineWidth',3,'Color',blue);
ylim(ax,[0 1.02]);
ylabel(ax,'Share available');

yyaxis(ax,'right');
plot(ax,tGrid,meanCumulativeRank,'LineWidth',1.65,'Color',red);
ylim(ax,[0 max(meanCumulativeRank)*1.08]);
ylabel(ax,'Cumulative rank');

% Only two dotted threshold lines: 50% and 10% surviving types.
hold(ax,'on');
xline(ax,t50,':','Color',[0.35 0.35 0.35], ...
    'LineWidth',1.1,'HandleVisibility','off');
xline(ax,t10,':','Color',[0.35 0.35 0.35], ...
    'LineWidth',1.1,'HandleVisibility','off');
hold(ax,'off');

xlabel(ax,'Eating time');
xlim(ax,[0 1]);
set(ax,'FontName','Helvetica','FontSize',18, ...
    'TickDir','out','Box','off', ...
    'XGrid','off','YGrid','off','Layer','top');
ax.YAxis(1).Color = blue;
ax.YAxis(2).Color = red;

prefix = fullfile(outputDirectory,'ps_eating_proof_fast');
set(fig,'PaperUnits','inches', ...
    'PaperSize',[5.5 4.1], ...
    'PaperPosition',[0 0 5.5 4.1]);
drawnow;
savefig(fig,[prefix '.fig']);
print(fig,[prefix '.pdf'],'-dpdf','-painters');
print(fig,[prefix '.png'],'-dpng','-r300');

curves = table(tGrid(:),meanSurvival(:),meanCumulativeRank(:), ...
    'VariableNames',{'eating_time','share_of_goods_surviving', ...
                     'cumulative_average_rank'});
writetable(curves,fullfile(outputDirectory,'ps_eating_proof_fast.csv'));

stages = table({'over_50pct';'10_to_50pct';'at_most_10pct'}, ...
               meanStage(:), ...
               std(stageContributions,0,1)'/sqrt(reps), ...
    'VariableNames',{'stage','rank_contribution','monte_carlo_se'});
writetable(stages,fullfile(outputDirectory,'ps_eating_proof_fast_summary.csv'));

stats = struct('m',m,'q',1,'reps',reps,'t50',t50,'t10',t10, ...
    'meanAverageRank',mean(wholeRank),'meanStageContributions',meanStage, ...
    'tGrid',tGrid,'meanSurvival',meanSurvival, ...
    'meanCumulativeRank',meanCumulativeRank,'figure',fig);

fprintf('\nDone. Average rank = %.5f; stages = [%.5f %.5f %.5f].\n', ...
    stats.meanAverageRank,meanStage);
fprintf('50%% remaining at t = %.5f; 10%% remaining at t = %.5f.\n', ...
    t50,t10);
fprintf('Figure and CSV files saved to: %s\n',outputDirectory);
end

function [start,alive,duration,rankFlow] = ps_iid_trace(m,stream,lf)
% Direct adaptation of ps_iid_rank() from the growth simulator above.
% The only additional work is recording four scalars per exhaustion event.
q = 1;
N = m;
choice = randi(stream,m,N,1);
rank = ones(N,1);
counts = accumarray(choice,1,[m,1]);
remaining = q*ones(m,1);
available = true(m,1);
rankSum = N;
elapsed = 0;
tolerance = 1e-11;

start = zeros(m+1,1);
alive = zeros(m+1,1);
duration = zeros(m+1,1);
rankFlow = zeros(m+1,1);
events = 0;

while any(available)
    eating = find(counts>0);
    dt = min(remaining(eating)./counts(eating));
    assert(isfinite(dt) && dt>=0, 'Invalid PS event time.');

    events = events+1;
    start(events) = elapsed;
    alive(events) = nnz(available);
    duration(events) = dt;
    rankFlow(events) = rankSum/N;

    elapsed = elapsed+dt;
    remaining(eating) = remaining(eating)-dt*counts(eating);

    exhausted = available & remaining<=tolerance;
    assert(any(exhausted),'No good exhausted at a PS event.');
    remaining(exhausted) = 0;
    available(exhausted) = false;
    counts(exhausted) = 0;

    active = find(available);
    a = numel(active);
    if a == 0, break; end

    moving = find(exhausted(choice));
    L = m-rank(moving);
    assert(all(L>=a),'Inconsistent revealed preference prefix.');

    increment = minimum_position(L,a,rand(stream,numel(moving),1),lf);
    rank(moving) = rank(moving)+increment;
    rankSum = rankSum+sum(increment);
    choice(moving) = active(randi(stream,a,numel(moving),1));
    counts = counts+accumarray(choice(moving),1,[m,1]);
end

assert(abs(elapsed-1)<1e-7,'PS did not allocate all goods.');
start = start(1:events);
alive = alive(1:events);
duration = duration(1:events);
rankFlow = rankFlow(1:events);
end

function [surv,cumRank,cuts,stages,totalRank] = trace_on_grid(start,alive,duration,rankFlow,m,tGrid)
% The number of available goods is a step function; cumulative rank is
% exactly linear during each segment between exhaustion events.
contrib = duration .* rankFlow;
before = [0;cumsum(contrib(1:end-1))];

edges = [start; 1+eps(1)];
idx = discretize(tGrid(:),edges);
assert(all(isfinite(idx)),'Time grid does not match exhaustion events.');

surv = (alive(idx)/m).';
surv(end) = 0; % at t=1 all goods have been exhausted
elapsedWithinInterval = max(0,min(tGrid(:)-start(idx),duration(idx)));
cumRank = (before(idx)+rankFlow(idx).*elapsedWithinInterval).';
cumRank(end) = sum(contrib);

cut50 = find(alive/m <= .5,1,'first');
cut10 = find(alive/m <= .1,1,'first');
if isempty(cut50), t50 = 1; else, t50 = start(cut50); end
if isempty(cut10), t10 = 1; else, t10 = start(cut10); end
cuts = [t50 t10];

ratio = alive/m;
stages = [sum(contrib(ratio>.5)), ...
          sum(contrib(ratio>.1 & ratio<=.5)), ...
          sum(contrib(ratio<=.1))];
totalRank = sum(contrib);
end

function n = choose_local_workers(requested)
% Restrict to local process-based workers, as in the supplied fast code.
if requested == 0
    n = 0;
    return
end
hasToolbox = license('test','Distrib_Computing_Toolbox') ...
    && ~isempty(ver('parallel'));
if ~hasToolbox
    warning('Parallel toolbox unavailable; running serially.');
    n = 0;
    return
end
pool = gcp('nocreate');
if isempty(pool)
    cluster = parcluster('local');
    requested = min(requested,cluster.NumWorkers);
    pool = parpool(cluster,requested);
elseif isa(pool,'parallel.ThreadPool')
    error('Use a local process pool, or pass workers=0.');
end
if ~isa(pool.Cluster,'parallel.cluster.Local')
    error('Existing pool is non-local; pass workers=0.');
end
n = min(requested,pool.NumWorkers);
end
