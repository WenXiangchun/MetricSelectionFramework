function [reference_population, impaired_population, metric_scores, partialcorrs, factor_analysis] = metric_selection_framework(varargin)
%%% Exemplary code for
%
% "A data-driven framework for the
% selection and validation of digital health
% metrics:  use-case inneurological sensorimotor impairments"
%
% Christoph M. Kanzler*, Mike D. Rinderknecht, Anne Schwarz, Ilse Lamers,
% Cynthia Gagnon, Jeremia Held, Peter Feys,  Andreas R. Luft,
% Roger Gassert and Olivier Lambercy
%
%
% Rehabilitation Engineering Laboratory,
% Institute of Robotics and Intelligent Systems,
% Department of Health Sciences and Technology,
% ETH Zurich, Zurich, Switzerland
%
%
% Copyright (C) 2020, Christoph M. Kanzler, ETH Zurich
% Contact: christoph.kanzler@hest.ethz.ch
%
% Thanks to Pietro Oldrati for code cleanup.

% Syntax: function metric_selection_framework([Name, Value]) 
%      
%     Input (name-value pairs):
%          'Effects'        - effects for the confound compensation.
%          'ReferenceTable' - table holding features and effects of the
%                             healthy population. If 'ImpairedTable' is
%                             specified this parameter is required.
%          'ImpairedTable'  - table holding features and effects of the
%                             impaired population. If 'ReferenceTable' is
%                             specified this parameter is required.
%          'Metrics'        - list of metrics to evaluate. Required when
%                             using custom data (previous two parameters).
%          'NumFactors'     - number of factors for the factor analysis.
%                             Obtained with Scree plot (next parameter).
%          'ShowScreePlot'  - boolean flag to show scree plot for the 
%                             number of factors.
%          'NumSimSubj'     - number of subjects in the simulated data.
%          'NumSimMetrics'  - number of metrics in the simulated data.
%          'SavePlots'      - boolean flag to save the plot figures in the
%                             'output_plots' directory.
%     Outputs:
%          * reference_population and impaired_population - tables with 
%            the original andcompensated metrics
%          * metric_scores - results of the per-metric analysis.
%          * partialcorrs - partial correlations between metrics.
%          * factor_analysis - result of the factor analysis.
%
% Usage info : https://github.com/ChristophKanzler/MetricSelectionFramework

%% Parsing and getting parameters.
defaultEffects = {'age', 'gender', 'tested_hand', 'is_dominant_hand'};
defaultShowScreePlot = false;
defaultNumFactors = 2;
defaultNumSimSubj = 100;
defaultNumSimMetrics = 5;
defaultSavePlots = false;

p = inputParser;
addParameter(p, 'Effects', defaultEffects, @(x) assert(iscellstr(x) || isstring(x), ...
    'Effects should be specified as a cell array or string array of effect names.'));
addParameter(p, 'ReferenceTable', table());
addParameter(p, 'ImpairedTable', table());
addParameter(p, 'Metrics', {}, @(x) assert(iscellstr(x) || isstring(x), ...
    'Metrics should be specified as a cell array or string array of metric names.'));
addParameter(p, 'NumFactors', defaultNumFactors, @(x) assert(isinteger(x) && isscalar(x) && x > 0, ...
    'The number of effects should be a positive scalar integer.'));
addParameter(p, 'ShowScreePlot', defaultShowScreePlot, @isboolean);
addParameter(p, 'NumSimSubj', defaultNumSimSubj, @(x) assert(isinteger(x) && isscalar(x) && x > 0, ...
    'The number of simulated subjects should be a positive scalar integer.'));
addParameter(p, 'NumSimMetrics', defaultNumSimMetrics, @(x) assert(isinteger(x) && isscalar(x) && x > 0, ...
    'The number of simulated metrics should be a positive scalar integer.'));
addParameter(p, 'SavePlots', defaultSavePlots, @isboolean);
parse(p, varargin{:});

disp('-------------------------------------------------------------------------------------------------');
disp('Examplary code for the paper:')
disp('"A data-driven framework for the selection and validation of digital health metrics:');
disp('use-case in neurological sensorimotor impairments"');
disp('Christoph M. Kanzler, Mike D. Rinderknecht, Anne Schwarz, Ilse Lamers, Cynthia Gagnon, Jeremia Held, Peter Feys,  Andreas R. Luft, Roger Gassert, and Olivier Lambercy');
disp('https://www.biorxiv.org/content/10.1101/544601v2')
disp('-------------------------------------------------------------------------------------------------');

disp('');
disp('');
disp('This code starts with simulating a number of metrics and runs all steps of the proposed metric selection procedure!');
addpath(genpath(pwd));

% Seed for repeatability.
seed = 9000;                    
rng(seed);

if any(strcmp(p.UsingDefaults, 'ReferenceTable')) && ~any(contains(p.UsingDefaults, 'ImpairedTable'))
    error('If you specify ImpairedTable, then you should also specify ReferenceTable');
elseif any(strcmp(p.UsingDefaults, 'ImpairedTable')) && ~any(contains(p.UsingDefaults, 'ReferenceTable'))    
    error('If you specify ReferenceTable, then you should also specify ImpairedTable');
end
use_simulated_data = any(strcmp(p.UsingDefaults, 'ReferenceTable')) || ... 
    any(strcmp(p.UsingDefaults, 'ImpairedTable')); 

effects = p.Results.Effects;

n_simulated_subjects = p.Results.NumSimSubj;     
n_simulated_metrics = p.Results.NumSimMetrics;       

mean_age_ref = 50;
var_age_ref = 40;
mean_age_imp = 40;
var_age_imp = 50;

show_scree_plot = p.Results.ShowScreePlot;

k = p.Results.NumFactors;

%% Generate or load data. 
if (use_simulated_data)
    [reference_population, impaired_population] = simulate_data(seed, n_simulated_subjects, n_simulated_metrics, mean_age_ref, var_age_ref, mean_age_imp, var_age_imp);
    metrics = strcat("metric", string(1:n_simulated_metrics));
else
    reference_population = p.Results.ReferenceTable;
    impaired_population = p.Results.ImpairedTable;
    
    if any(strcmp(p.UsingDefaults, 'Metrics'))
        error('You input custom data, but did not specify the name of the metrics to validate. Please, provide the required parameter.');
    end
    metrics = p.Results.Metrics;
    
    % Checking that the provided tables contain all the required columns.
    ref_error = check_data_table_cols(reference_population, effects, metrics);
    
    if ~isempty(ref_error)
        error(strcat("The reference data table ", ref_error))
    end
    
    imp_error = check_data_table_cols(impaired_population, effects, metrics);
    
    if ~isempty(imp_error)
        error(strcat("The impaired data table ", ref_error))
    end
end
n_metrics = length(metrics);

%%  Postprocessing (modeling of confounds).
[reference_population, impaired_population, lme] = postprocess_metrics(metrics, effects, reference_population, impaired_population);

%% Metric selection & validation: steps 1 and 2.
metrics_mat = table();
metric_scores = table();
C1s = zeros(n_metrics, 1);
C2s = zeros(n_metrics, 1);
AUCs = zeros(n_metrics, 1);
SRDs = zeros(n_metrics, 1);
ICCs = zeros(n_metrics, 1);
slopes = zeros(n_metrics, 1);
for i = 1:n_metrics
    metric_name = metrics{i};
    metric_comp = [metric_name '_c'];
    metric_retest_comp = [metric_name '_retest_c'];
    
    fprintf('\n\n');
    disp(['<strong>Results for metric ' metric_name ':</strong>']);
    
    % Plot confound correction results.
    plot_confound_correction(reference_population, effects, metric_name)
    
    % Standardize metric w.r.t reference population.
    [reference_population, impaired_population] = standardize_reference(reference_population, impaired_population, metric_name);
    [reference_population, impaired_population] = standardize_reference(reference_population, impaired_population, metric_comp);
    [reference_population, impaired_population] = standardize_reference(reference_population, impaired_population, metric_retest_comp);
    
    [C1s(i), C2s(i), AUCs(i), SRDs(i), ICCs(i), slopes(i)] = analyze_metric(reference_population, impaired_population, lme, metric_name);
    disp('Press a button to continue...');
    waitforbuttonpress;

    metrics_mat.(metric_comp) = reference_population.(metric_comp);
end
metric_scores.metric = metrics';
metric_scores.C1 = C1s;
metric_scores.C2 = C2s;
metric_scores.AUC = AUCs;
metric_scores.SRD = SRDs;
metric_scores.ICC = ICCs;
metric_scores.slope = slopes;

close all;

%% Metric selection & validation: step 3.
metrics_mat = table2array(metrics_mat);
partialcorrs = partialcorr(metrics_mat);
hm_fig = figure('Position', [-1 -1 900 600]);
heatmap(partialcorrs, metrics, metrics, '%0.2f', 'Colormap', 'money', ...
    'FontSize', 9, 'Colorbar', {'SouthOutside'}, 'MinColorValue', -1, 'MaxColorValue', 1);
title('Inter-metric correlation')
movegui(hm_fig, 'center');
disp('Press a button to continue...');
waitforbuttonpress;
close all;

%% Further metric validation: step 1.
factor_analysis = analyze_factors(metrics, metrics_mat, k, show_scree_plot);

%% Further metric validation: step 2.
population = [reference_population; impaired_population];
population.id = (1:height(population))';
metrics_mat = table();
for i = 1:n_metrics
    metrics_mat.([metrics{i} '_c']) = population.([metrics{i} '_c']);
end
metrics_mat = table2array(metrics_mat);

disp('Press a button to continue...');
waitforbuttonpress;
close all;

% Calculating the cutoff for the metrics with the 95% percentile.
abnormal_behaviour_cut_offs = prctile(metrics_mat, 95, 1)';
visualize_impairment_profile_non_parametric_mad(population, metrics, abnormal_behaviour_cut_offs);
end
