function remapped = luminance_remap(source, target)
    % assumes that the source is Lab with luminance channel (0-100)
    % assumes that target is a grayscale image (0-1)
    source_luminance = source(:,:,1)/100;
    
    mu_a = mean(source_luminance(:));
    mu_b = mean(target(:));
    sigma_a = std(source_luminance(:));
    sigma_b = std(target(:));
    
    remapped = sigma_b/sigma_a*(source_luminance - mu_a) + mu_b;
end