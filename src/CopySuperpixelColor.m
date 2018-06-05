function lab_out = CopySuperpixelColors(samples, source, target)
%Perform superpixel matching followed by transfer (TBD)
% -Histogram based ?

%Superpixel matching
[bspfspt, dists] = knnsearch(samples.fv_sp', target.fv_sp');

lab_out = zeros([size(target.image) 3]);
lab_out(:,:,1) = target.luminance*100;

figure;
for i = 1:length(bspfspt)
%     figure(55);
    src_mask = (source.sp==bspfspt(i));
    tgt_mask = (target.sp==i);
    
%     subplot(1,2,1);
%     imshow(target.image.*~tgt_mask);
%     subplot(1,2,2);
%     imshow(source.luminance.*~src_mask);
    
    %Prototype color transfer
    for c = 2:3
        mask_c = source.lab(:,:,c).*src_mask;
        mu_sp = sum(sum(mask_c))/length(find(mask_c));
        lab_out(:,:,c) = lab_out(:,:,c) + mu_sp*tgt_mask;
    end
end


end
