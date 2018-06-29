%% -----------------------------------------------------------------
% Exemplar-based colorization algorithm
% Author: Saulo Pereira
%
%TODO: 
%-default input file with input list;
%-add to path
%
%-------------------------------------------------------------------

function initialize()
%   dir_el = dir('./../input');
%   
%   list = [];
%   for i = :
%     list = [list dir_el(i).name];
%   end
% 
%   batch_input = strsplit(list, '.in');
  
  batch_input = {'default'};

%TODO: remove function and use run.
  
  for i = 1:length(batch_input)
    close all;
    ColorizationPipeline(batch_input{i});
  end
end

function ColorizationPipeline(input_file)

  %% Input parameters
  [IP, FP, OO] = InputAlgorithmParameters(input_file);
  figs = GenerateFiguresList;

  %% Input data (source and target images)
  [source.image, target.image] = LoadImages(IP.sourceFile, IP.targetFile, IP.dataFolder);

  %% Color space conversion
  source.lab = rgb2lab(source.image);

  if (OO.PLOT)
    abs = reshape(source.lab(:,:,2:3), size(source.lab,1)*size(source.lab,2), 2);
    figure(figs.ColorDist); scatter(abs(:,1), abs(:,2), '.'); hold on
    title('Source Lab chrominance distribution');

    drawnow;
  end

  %% Luminance Remapping (source to target)
  tgt_lab = rgb2lab(cat(3, target.image, target.image, target.image));
  target.luminance = tgt_lab(:,:,1)/100;

  source.luminance = luminance_remap(source.lab, target.luminance, IP.sourceFile == IP.targetFile);

  %% Superpixel extraction
  if (IP.SUPERPIXEL)
    disp('Superpixel extraction'); tic;

    %TODO: superpixels should be a struct inside both source and target.
    [source.sp, source.lin_sp, source.sp_centroids, source.nSuperpixels] = ...
      SuperpixelExtraction(source.luminance, IP.nSuperpixels);
    [target.sp, target.lin_sp, target.sp_centroids, target.nSuperpixels] = ...
      SuperpixelExtraction(target.image, IP.nSuperpixels);

    toc;

    if (OO.PLOT)
      figure(figs.TargetSP); imshow(imoverlay(target.image, boundarymask(target.sp, 4), 'w')); 
      title('Target superpixels');
      figure(figs.SourceSP); imshow(imoverlay(source.image, boundarymask(source.sp, 4), 'w')); 
      title('Source superpixels');
    end
  end

  %% Color Clustering (Automatic Labeling)
  % Performs the clustering for sampling and/or classification.

  if (IP.COLOR_CLUSTERING)
    disp('Source color clustering'); tic;
    clusters = ColorClustering(source.lab, IP.nClusters, OO.PLOT);

    toc;
    if (IP.SUPERPIXEL)
      disp('Superpixel labeling'); tic;
      source.sp_clusters = zeros(1, max(source.lin_sp));

      for i = 1:length(source.sp_clusters)
        %TODO: CORRIGIR MODE
        [source.sp_clusters(i), ~, ties] = mode(clusters.idxs(source.lin_sp == i));
%         if (length(ties{1}) > 1)
%           source.sp_clusters(i) = 0;
%         end
      end
      toc;
      
      % TEST -------------------------------------------------------------
      %Plot das classes
      im_labels = zeros(size(source.luminance));
      for i = 1:source.nSuperpixels
        mask = (source.sp == i);
        im_labels = im_labels + source.sp_clusters(i)*mask;
      end
      figure; imshow(im_labels, []); title('Automatic Labeling of Superpixels');
      colormap jet;
      %-------------------------------------------------------------------
    end
    
  end

  %% Source sampling
  disp('Source image sampling'); tic;

  switch IP.SAMPLE_METHOD
    case 0
    %No sampling:
    [samples.idxs, samples.ab] = FullSampling(source.lab);

    case 1
    %Jittered sampling:
    [samples.idxs, samples_ab] = JitterSampleIndexes(source.lab, IP.nSamples);
    samples.idxs = [samples.idxs(2,:); samples.idxs(1,:)];
    samples.lin_idxs = sub2ind(size(source.luminance), samples.idxs(1,:), samples.idxs(2,:))';
    samples.ab = samples_ab(2:3,:);

    case 2
    %Clustered sampling:
    samples = ClusteredSampling(source.lab, clusters, IP.nClusters, IP.nSamples);

    otherwise
    disp('Invalid SAMPLE_METHOD');
  end
  samples.sourceSize = size(source.luminance);

  toc;

  if (OO.PLOT)
    figure; imshow(source.image); title('Samples from source'); hold on;
    %Invert coordinates because it is a plot over an image.
    scatter(samples.idxs(2,:), samples.idxs(1,:), '.r'); hold off;

    figure(figs.ColorDist); title('Lab chrominance distribution (total x sampled)');
    scatter(samples.ab(1,:), samples.ab(2,:), 6, 'r');

    drawnow;
  end

  %% Feature extraction
  try
    load(['./../temp/' input_file(5:end)]);
    
    %Sampling
    idxs = sub2ind(size(source.luminance), samples.idxs(1,:), samples.idxs(2,:));
    samples.fv = samples_fv(:,idxs);
    target.fv = target_fv;
    samples.fvl = samples_fvl;
    target.fvl = target_fvl;
  catch
    disp('Feature extraction'); tic;

    [target_fv, target_fvl] = FeatureExtraction(target.luminance, FP);
%     samples_fv = FeatureExtraction(source.luminance, FP, samples.idxs);
    % Compute features for the whole image
    [samples_fv, samples_fvl] = FeatureExtraction(source.luminance, FP);
    toc;
    
    save(['./../temp/' input_file(5:end)], 'target_fv', 'samples_fv', 'target_fvl', 'samples_fvl');
    
    %Sampling
    idxs = sub2ind(size(source.luminance), samples.idxs(1,:), samples.idxs(2,:));
    samples_fv = samples_fv(:,idxs);
        
    target.fv = target_fv;
    samples.fv = samples_fv;
    target.fvl = target_fvl;
    samples.fvl = samples_fvl;
  end
    
  if (IP.SUPERPIXEL)
      disp('Superpixel feature averaging'); tic;
      [target.fv_sp, source.fv_sp] = SuperpixelFeatures(source, samples, target);

      target = rmfield(target, 'fv');
      samples = rmfield(samples, 'fv');

      toc;
  end

  % Principal components:
  if (IP.DIM_RED)
    disp('Dimensionality Reduction on Feature Space'); tic;

    if (~IP.SUPERPIXEL)
      [samples.fv, target.fv] = DimensionalityReduction(samples.fv, target.fv, IP.DIM_RED);
    else
      [source.fv_sp, target.fv_sp] = ...
        DimensionalityReduction(source.fv_sp, target.fv_sp, IP.DIM_RED);
    end
    toc;
  end

  %% Feature space analysis

  if(OO.ANALYSIS && IP.COLOR_CLUSTERING)
    figure(figs.LabelsFS); title('Source: Labeled samples in feature space'); hold on; 
    figure(figs.LabelsImage); imshow(source.luminance); 
    title('Source: Labeled samples over image'); hold on;

    if (~IP.SUPERPIXEL)
      for i = 1:IP.nClusters
          instances = find(samples.clusters == i);
          figure(figs.LabelsFS); scatter(samples.fv(1,instances), samples.fv(2,instances),'.');
          figure(figs.LabelsImage); scatter(samples.idxs(2,instances), samples.idxs(1,instances),'.');
      end
    else
      for i = 1:IP.nClusters
        sp_instances = find(source.sp_clusters == i);
        figure(figs.LabelsFS); scatter(source.fv_sp(1,sp_instances), source.fv_sp(2,sp_instances), '.');
      end
    end
    figure(figs.LabelsFS); hold off;
    figure(figs.LabelsImage); hold off; 

    drawnow;
  end

  if (OO.ANALYSIS)
    figure; title('Target: Feature space distribution'); hold on;
    if (~IP.SUPERPIXEL) 
        scatter(target.fv(1,:), target.fv(2,:), '.k'); hold off;
    else
        scatter(target.fv_sp(1,:), target.fv_sp(2,:), '.k'); hold off;
    end
  end

  %% Matching / Classification
  disp('Feature matching / Classification in Feature Space'); tic;

  if (~IP.SUPERPIXEL && ~IP.CLASSIFICATION)
    [neighbor_idxs, neighbor_dists] = knnsearch(samples.fv', target.fv'); 
  elseif (~IP.SUPERPIXEL && IP.CLASSIFICATION)
        %K adjustment:----------------------------------------------
    mc_cost = squareform(pdist(clusters.centroids(:,1:2)));
    mc_cost = mc_cost*((IP.nClusters - 1)/norm(mc_cost));
    
    K = round(logspace(0,log10(length(samples.lin_idxs)),10)); % number of neighbors 
    K = [1 2 3 4 5 6 7 8 9 10 11 K(4:end)];
    cvloss = zeros(numel(K),1);
    cvloss_w = zeros(numel(K),1);
    for k=1:numel(K)
      knn = fitcknn(samples.fv',samples.clusters',...
          'NumNeighbors',K(k),'CrossVal','On');
      knn_w = fitcknn(samples.fv',samples.clusters',...
          'NumNeighbors',K(k),'CrossVal','On', 'Cost', mc_cost);
      cvloss(k) = kfoldLoss(knn);
      cvloss_w(k) = kfoldLoss(knn_w);

%       labels = predict(knn, source.fv_sp');
%       labels_w = predict(knn_w, source.fv_sp');
% 
%       figure; imshow(lab2rgb(CopyClosestSuperpixelFromClassAvgColor(source, target, neighbor_idxs, ...
%       neighbor_classes, labels)));
%       figure; imshow(lab2rgb(CopyClosestSuperpixelFromClassAvgColor(source, target, neighbor_idxs, ...
%       neighbor_classes, labels_w)));
    end
    
    [neighbor_idxs, neighbor_dists] = knnsearch(samples.fv', target.fv', 'K', IP.Kfs);
    neighbor_classes = samples.lin_idxs(neighbor_idxs,:);
    neighbor_classes = clusters.idxs(neighbor_classes);
    neighbor_classes = reshape(neighbor_classes, size(neighbor_idxs,1), size(neighbor_idxs,2));
    labels = mode(neighbor_classes,2);
  elseif (IP.SUPERPIXEL && ~IP.CLASSIFICATION)
    [neighbor_idxs, neighbor_dists] = knnsearch(source.fv_sp', target.fv_sp');
  elseif (IP.SUPERPIXEL && IP.CLASSIFICATION)
    
    %K adjustment:----------------------------------------------
    mc_cost = squareform(pdist(clusters.centroids(:,1:2)));
    mc_cost = mc_cost*((IP.nClusters - 1)/norm(mc_cost));
    
    K = round(logspace(0,log10(source.nSuperpixels),10)); % number of neighbors 
    K = [1 2 3 4 5 6 7 8 9 10 11 K(4:end)];
    cvloss = zeros(numel(K),1);
    cvloss_w = zeros(numel(K),1);
    for k=1:numel(K)
      knn = fitcknn(source.fv_sp',source.sp_clusters',...
          'NumNeighbors',K(k),'CrossVal','On');
      knn_w = fitcknn(source.fv_sp',source.sp_clusters',...
          'NumNeighbors',K(k),'CrossVal','On', 'Cost', mc_cost);
      cvloss(k) = kfoldLoss(knn);
      cvloss_w(k) = kfoldLoss(knn_w);

%       labels = predict(knn, source.fv_sp');
%       labels_w = predict(knn_w, source.fv_sp');
% 
%       figure; imshow(lab2rgb(CopyClosestSuperpixelFromClassAvgColor(source, target, neighbor_idxs, ...
%       neighbor_classes, labels)));
%       figure; imshow(lab2rgb(CopyClosestSuperpixelFromClassAvgColor(source, target, neighbor_idxs, ...
%       neighbor_classes, labels_w)));
    end
    figure; % Plot the accuracy versus k
    semilogx(K,cvloss);hold on;
    semilogx(K,cvloss_w); hold off;
    xlabel('Number of nearest neighbors');
    ylabel('10 fold classification error');
    title('k-NN classification');
    
    [~,minK_idx] = min(cvloss);
    [~, minKw_idx] = min(cvloss_w);
    %End K adjustment:------------------------------------------
    %Ensemble:--------------------------------------------------
    NPredToSample = round(linspace(1,size(source.fv_sp,1),20)); % linear spacing of dimensions
    cvloss = zeros(numel(NPredToSample),1);
    learner = templateKNN('NumNeighbors',K(minKw_idx));
    for npred=1:numel(NPredToSample)
       subspace = fitcensemble(source.fv_sp',source.sp_clusters',...
         'Method','Subspace','Learners',learner, ...
         'NPredToSample',NPredToSample(npred),'CrossVal','On', 'Cost', mc_cost);
       cvloss(npred) = kfoldLoss(subspace);
       fprintf('Random Subspace %i done.\n',npred);
    end
    figure; % plot the accuracy versus dimension
    plot(NPredToSample,cvloss);
    xlabel('Number of predictors selected at random');
    ylabel('10 fold classification error');
    title('k-NN classification with Random Subspace');
    %End Ensemble:----------------------------------------------
    %TEST:------------------------------------------------------
    
%     l = 1;
%     labels_m = [];
%     labels_t = [];
%     for i = 1:length(target.fvl)
%       [nn_idx, nn_dist] = knnsearch(source.fv_sp(l:l+(target.fvl(i)-1),:)', ...
%                                     target.fv_sp(l:l+(target.fvl(i)-1),:)', ...
%                                     'K', IP.Kfs);
%       classes = source.sp_clusters(nn_idx);
% 
%       labels_m_aux = modeTies(classes);
%       labels_m = [labels_m labels_m_aux];
%       labels_t = [labels_t classes];
% 
%       l = l + target.fvl(i);
%     end
%     %Mode of mode
%     labels_mm = modeTies(labels_m);
%     labels_mt = modeTies(labels_t);
    %---------------------------------------------------

    [neighbor_idxs, neighbor_dists] = knnsearch(source.fv_sp', target.fv_sp', ...
      'K', source.nSuperpixels); % Return all distances for further reference.
    neighbor_classes = source.sp_clusters(neighbor_idxs);
    labels = modeTies(neighbor_classes(:,1:IP.Kfs));

    %COLORIZE TEST:-----------------------------------------------------------------
    [neighbor_idxs, neighbor_dists] = knnsearch(source.fv_sp', target.fv_sp', ...
      'K', source.nSuperpixels); % Return all distances for further reference.
    neighbor_classes = source.sp_clusters(neighbor_idxs);
    labels = modeTies(neighbor_classes(:,1:minKw_idx));
    
    tgt_rgb = lab2rgb(CopyClosestSuperpixelFromClassAvgColor(source, target, neighbor_idxs, ...
        neighbor_classes, labels));
    figure;imshow(tgt_rgb);
    figure;imshow(imoverlay(tgt_rgb, boundarymask(target.sp, 4), 'w'));
  end

  toc;

  %% Relabeling
  if (IP.SUPERPIXEL && IP.CLASSIFICATION)
    disp('Superpixel relabeling'); tic;
    relabels = ClassScoreSpatialRelabeling(target, IP.nClusters, IP.Kis, ...
      neighbor_classes(:, 1:IP.Kfs));

    test = find(labels ~= relabels);
    toc;
  end

  %% Color transfer:
  disp('Color transfer'); tic

  switch IP.COL_METHOD
    case 0
      tgt_lab = CopyClosestFeatureColor(samples.ab, target, neighbor_idxs);
    case 1
      tgt_lab = CopyClosestFeatureInClassColor(samples.ab, target, neighbor_idxs, neighbor_classes, ...
        labels);
    case 2
      tgt_lab = CopyClosestSuperpixelAvgColor(source, target, neighbor_idxs);
    case 3
      tgt_lab = CopyClosestSuperpixelFromClassAvgColor(source, target, neighbor_idxs, ...
        neighbor_classes, labels);
      
      tgt_lab_r = CopyClosestSuperpixelFromClassAvgColor(source, target, neighbor_idxs, ...
        neighbor_classes, relabels);
    case 4
      [tgt_scribbled, scribbles_mask] = CopyClosestSuperpixelAvgScribble(source, target, neighbor_idxs);
      tgt_scribbled = lab2rgb(tgt_scribbled);
      target.rgb = ColorPropagationLevin(tgt_scribbled, target.luminance, scribbles_mask);  
    case 5
      [tgt_scribbled, scribbles_mask] = CopyClosestSuperpixelFromClassScribble(source, target, ...
        neighbor_idxs, neighbor_classes, labels);
      tgt_scribbled = lab2rgb(tgt_scribbled);
      target.rgb = ColorPropagationLevin(tgt_scribbled, target.luminance, scribbles_mask);
      
      %Relabeled
      [tgt_scribbled, scribbles_mask] = CopyClosestSuperpixelFromClassScribble(source, target, ...
        neighbor_idxs, neighbor_classes, relabels);
      tgt_scribbled = lab2rgb(tgt_scribbled);
      target.rgb_r = ColorPropagationLevin(tgt_scribbled, target.luminance, scribbles_mask);
    otherwise
      disp('Invalid COL_METHOD');
  end

  toc;

  % Color space reconversion
  if (~isfield(target, 'rgb'))
    target.rgb = lab2rgb(tgt_lab);
  end
  if (~isfield(target, 'rgb_r') && exist('tgt_lab_r'))
    target.rgb_r = lab2rgb(tgt_lab_r);
  end
  
  %% Show results
  if (OO.PLOT)
    figure; imshow(target.rgb);
    if(isfield(target, 'rgb_r'))
      figure; imshow(target.rgb_r); title('Relabeled');
    end
  end
  
  %% Save Output images
  if (OO.SAVE)
    disp('Saving output image');
    imwrite(target.rgb, ['./../results/' input_file '.png'], 'png');
    if(isfield(target, 'rgb_r'))
      imwrite(target.rgb_r, ['./../results/' input_file '_r.png'], 'png');
    end
  end

  %% Result Analysis
  
  if (OO.ANALYSIS)
    MatchingAnalysis(IP.COL_METHOD, figs, source, target, neighbor_idxs);
  end
  
end
