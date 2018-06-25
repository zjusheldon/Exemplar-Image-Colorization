function [clRelabeled] = ClassScoreSpatialRelabeling(target, nClusters, Kis, neighbor_classes)
%Relabeling based on classification scores and spatial coherence. 
%TODO: Only works in mode 3 so far.

%% Feature space class scores:
clScoresF = zeros(target.nSuperpixels, nClusters);
for i = 1:size(clScoresF,1)
  clScoresF(i,:) = hist(neighbor_classes(i,:), 1:nClusters);
end
clScoresF = clScoresF ./ repmat(sum(clScoresF, 2), 1, nClusters);

[delta_idx, ~] = max(clScoresF,[],2);
clScoresF_delta = (clScoresF == repmat(delta_idx, 1, nClusters));

%% Image space coherence:
[neighbor_sps, ctrd_dists] = ...
  knnsearch(target.sp_centroids', target.sp_centroids', 'K', Kis+1);
neighbor_sps = neighbor_sps(:,2:end);
ctrd_dists = 1./ctrd_dists(:,2:end);
ctrd_dists = ctrd_dists ./ repmat(sum(ctrd_dists, 2), 1, Kis);

%% Combination
kLambda = 0.8;
kMaxIt = 3;

clScores = clScoresF;
for rel_it = 1:kMaxIt
  clScoresI = zeros(target.nSuperpixels, nClusters);
  for i = 1:size(clScoresI,1)
    neighbor_scores = clScoresF_delta(neighbor_sps(i,:)',:);
    w = ctrd_dists(i,:);
    w = ones(1, Kis)/Kis;

    clScoresI(i,:) = w*neighbor_scores;
  end
  clScoresI = clScoresI ./ repmat(sum(clScoresI, 2), 1, nClusters);

  clScores = clScores + kLambda*clScoresI;
  clScores = clScores ./ repmat(sum(clScores, 2), 1, nClusters);
  
  %Test
%   [~, clRelabeled{rel_it}] = max(clScores, [], 2);
end

[~, clRelabeled] = max(clScores, [], 2);

end

