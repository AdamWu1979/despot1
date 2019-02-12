% generates synthetic T1w image from a despot T1w map - flip-angle and TR are hardcoded, can modify to adjust contrast
function genDespotSynT1w ( in_t1_nii, out_t1w_nii)

    %in_t1_nii='_acq-DESPOT_T1map.nii.gz';
    %out_t1w_nii='T1w.nii.gz';

    TR_ms=8.3;
    flipangle_deg=18;
    flipangle=0.3142;

    in_nii=load_nifti(in_t1_nii);
% octave doesn't seem to have deg2rad in core libraries
 %   flipangle=deg2rad(flipangle_deg);  

    T1=in_nii.vol;
    E1=exp(-TR_ms./T1);
    SI=5000.*(1.0-E1).*sin(flipangle).*(1.0-E1.*cos(flipangle)).^(-1);

    %figure; imagesc(squeeze(SI(80,:,:)));colormap('gray');

    in_nii.vol=SI;

    save_nifti(in_nii,out_t1w_nii);

end
