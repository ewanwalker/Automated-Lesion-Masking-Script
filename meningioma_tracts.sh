cd ../meningioma_raw_data
echo "Starting Loop"
for i in  sub-*_T1.nii.gz 
do
		identifier=${i:0:7} 
		cd ../derivatives/meningioma_patients/${identifier}
		tckgen \
					-angle 22.5 \
					-maxlen 250 \
					-minlen 10 \
					-power 1.0 \
					../../../derivatives/templates/wmfod-template.mif \
					-seed_image ${identifier}_hand_delineated_mask.mif \
					-mask ../../../derivatives/templates/template-space_mask.mif \
					-select 100000 \
					-cutoff 0.06 \
					${identifier}_hand_delineated_tractogram.tck \
					-nthreads 12
				# the lesion tractograms are converted into fixel maps, which can be overlaid and compared
				tck2fixel \
					${identifier}_tractogram.tck \
					../../../derivatives/templates/fixel_mask \
					../../../derivatives/templates/tracks/lesion-tracks/ \
					${identifier}_hand_delineated_lesion-track.mif
				# lesion-track fixel maps are binarised for spatial comparison
				mrthreshold \
					../../../derivatives/templates/tracks/lesion-tracks/${identifier}_hand_delineated_lesion-track.mif \
					-abs 1 \
					../../../derivatives/templates/tracks/lesion-tracks/${identifier}_hand_delineated_lesion-bin.mif
				
			cd ../../../meningioma_raw_data
done
