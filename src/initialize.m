%% -----------------------------------------------------------------
% Colorization by example.
% Modified by: Saulo Pereira
%
%TODO:
%-Estrutura de dados completa � cara para passar como argumento ?
%-CADA FEATURE DEVE TER UMA DIST�NCIA DIFERENTE ?
% -os valores de dist�ncias devem estar entre 0-1 
%-------------------------------------------------------------------

% clc
clear all; close all;

%% Setup
GRAPH =             true;
SAVE =              false;
SAMPLE_METHOD =     2;  %0 = brute-force, 1 = jittered-sampling, 2 = clustered-sampling
COL_METHOD =        1;  %0 = "regression", 1 = "classification"

%Parameters: 
nSamples =          2^10;
nClusters =         50;
features =          [true true true];
% featuresWeights = 

%% Input data (source and target images)
src_name = 'beach2.jpg';
tgt_name = 'beach1.jpg';

target = {};
source = {};

[source.image, target.image] = LoadImages(src_name, tgt_name, '../data/');

%% Color space conversion
source.lab = rgb2lab(source.image);

if (GRAPH)
%     figure(1); imshow([source.image source.lab]);
%     title('RGB x Lab');
    
    abs = reshape(source.lab(:,:,2:3), size(source.lab,1)*size(source.lab,2), 2);
    figure(2); scatter(abs(:,1), abs(:,2), '.'); hold on
    title('Source Lab chrominance distribution');
    
    drawnow;
end

%% Map source luminance to target luminance
target.luminance = target.image;
source.luminance = luminance_remap(source.lab, target.luminance, src_name == tgt_name);

%% Source sampling
disp('Source image sampling'); tic;

switch SAMPLE_METHOD
    case 0
    [samples.idxs, samples.ab] = FullSampling(source.lab);

    case 1
    %Jittered sampling:
    [samples.idxs, samples_ab] = JitterSampleIndexes(source.lab, nSamples);
    %TODO: inverter na propria funcao.
    samples.idxs = [samples.idxs(2,:); samples.idxs(1,:)];
    samples.ab = samples_ab(2:3,:);
    
    case 2
    samples = ClusteredSampling(source.lab, nClusters, nSamples);
    
    otherwise
    disp('Invalid SAMPLE_METHOD');
end
samples.sourceSize = size(source.luminance);

if (GRAPH)
    figure(3); imshow(source.image); hold on;
    %Invert coordinates because it is a plot over an image.
    scatter(samples.idxs(2,:), samples.idxs(1,:), '.r');
    title('Samples from source');
    
    figure(2);
    scatter(samples.ab(1,:), samples.ab(2,:), 6, 'r');
    title('Lab chrominance distribution (total x sampled)');
    drawnow;
end

toc;
%% Feature extraction:
disp('Feature extraction'); tic;

[target.fv, target.fv_w] = FeatureExtraction(target.luminance, features);
[samples.fv, samples.fv_w] = FeatureExtraction(source.luminance, features, samples.idxs);

toc;
%% Colorization:
disp('Color transfer'); tic

switch COL_METHOD
    case 0
    [tgt_lab, tiesIdx] = CopyClosestFeatureColor(samples, target);
    
    case 1
    clusters = ColorClustering(source.lab, nClusters, GRAPH); 
    [tgt_lab, tiesIdx] = CopyClosestFeatureColor(samples, target, clusters);
    
    otherwise
    disp('wtf');
end

toc;
%% Color space reconversion
tgt_rgb = lab2rgb(tgt_lab);

%% Show results
figure; imshow(tgt_rgb); hold on;
if(~isempty(tiesIdx))
    scatter(tiesIdx(2,:), tiesIdx(1,:), '.k');
end
title('Colorized result (ties marked)');

if (GRAPH)
    abs = reshape(tgt_lab(:,:,2:3), size(tgt_lab,1)*size(tgt_lab,2), 2);
    figure; scatter(abs(:,1), abs(:,2), '.'); hold on
    title('Target Lab chrominance distribution');
    
    drawnow;
end

%% save images
% success = save_image(tgt_color, new_name, SAVE);
