cd ../Derivatives 
mkdir  Group  # create group folder 
cd ../Raw_Data 
for i in  sub-* #  loop through each file 
do
	cd ../Derivatives # enter the diffusion derivatives folder
	mkdir  ${i:0:7} # create files for each of the T1 image derivatives
	cd  ${i:0:7} # create files for each of the T1 image derivatives
	mkdir  anat 
	mkdir  dwi
	cd ../
done

cd ../Raw_Data
echo "Starting Pipeline"
for i in  sub-*
	do
		sub=${i:0:7} 
		DWI_Derivative_Path=../Derivatives/${sub}/dwi/
		DWI_Raw_Path=${sub}/dwi/
		mrconvert \
			-fslgrad \
				${DWI_Raw_Path}${sub}_dir-AP_dwi.bvec \
				${DWI_Raw_Path}${sub}_dir-AP_dwi.bval \
			${DWI_Raw_Path}${sub}_dir-AP_dwi.nii.gz \
			${DWI_Derivative_Path}${sub}_dwi.mif
		# extract b0 from dki series to make up PA part of phase pair
		mrconvert \
			${DWI_Derivative_Path}${sub}_dwi.mif \
			-coord \
			3 \
			0 \
			-axes 0,1,2 \
			${DWI_Derivative_Path}${sub}_dir-AP_dwi.mif
		# convert reverse phase encoded image
		mrconvert \
			${DWI_Raw_Path}${sub}_dir-PA_dwi.nii.gz \
			${DWI_Derivative_Path}${sub}_dir-PA_dwi.mif	
		# concatenate the phase encoding images to create the phase pair
		mrcat \
			${DWI_Derivative_Path}${sub}_dir-AP_dwi.mif \
			${DWI_Derivative_Path}${sub}_dir-PA_dwi.mif \
			${DWI_Derivative_Path}${sub}_acq-pair_dwi.mif \
			-axis 3
		# denoise
		dwidenoise \
			${DWI_Derivative_Path}${sub}_dwi.mif \
			${DWI_Derivative_Path}${sub}_dwi_denoised.mif
		# gibbs unringing
		mrdegibbs \
			${DWI_Derivative_Path}${sub}_dwi_denoised.mif \
			${DWI_Derivative_Path}${sub}_dwi_unringed.mif \
			-axes 0,1
		# eddy and topup
		dwifslpreproc \
			${DWI_Derivative_Path}${sub}_dwi_unringed.mif \
			${DWI_Derivative_Path}${sub}_dwi_preproc.mif \
			-rpe_pair \
			-se_epi ${DWI_Derivative_Path}${sub}_acq-pair_dwi.mif \
			-readout_time 0.029 \
			-pe_dir AP \
			-align_seepi \
			-eddy_options " --slm=linear --nthr=8"
		# bias correction
		dwibiascorrect \
			ants \
				${DWI_Derivative_Path}${sub}_dwi_preproc.mif \
				${DWI_Derivative_Path}${sub}_dwi_unbiased.mif
		# upsample to 1.25mm
		mrgrid \
			${DWI_Derivative_Path}${sub}_dwi_unbiased.mif \
			regrid \
			-vox 1.25 \
			${DWI_Derivative_Path}${sub}_dwi_upsampled.mif
		# mri_synthstrip to brain extract
		mrconvert \
			${DWI_Derivative_Path}${sub}_dwi_upsampled.mif \
			${DWI_Derivative_Path}${sub}_dwi_upsampled.nii.gz
		fslmaths \
			${DWI_Derivative_Path}${sub}_dwi_upsampled.nii.gz \
		-Tmean \
			${DWI_Derivative_Path}${sub}_dwi-mean_upsampled.nii.gz
		mri_synthstrip \
			-i ${DWI_Derivative_Path}${sub}_dwi-mean_upsampled.nii.gz \
			-m ${DWI_Derivative_Path}${sub}_dwi-mask_upsampled.nii.gz
		mrconvert \
			${DWI_Derivative_Path}${sub}_dwi-mask_upsampled.nii.gz \
			${DWI_Derivative_Path}${sub}_dwi-mask_upsampled.mif
		dwi2response \
			dhollander \
				${DWI_Derivative_Path}${sub}_dwi_upsampled.mif \
				${DWI_Derivative_Path}${sub}_dwi_response-wm.txt \
				${DWI_Derivative_Path}${sub}_dwi_response-gm.txt \
				${DWI_Derivative_Path}${sub}_dwi_response-csf.txt \
				-mask ${DWI_Derivative_Path}${sub}_dwi-mask_upsampled.mif
	done

cd ../Derivatives
echo "Starting group averaging"
for i in  sub-*
	do
		sub=${i:0:7} 
		cp ${sub}/dwi/${sub}_dwi_response-*.txt Group
	done
 
responsemean \
	Group/*_dwi_response-wm.txt \
	Group/group_average_response-wm.txt
responsemean \
	Group/*_dwi_response-gm.txt \
	Group/group_average_response-gm.txt
responsemean \
	Group/*_dwi_response-csf.txt \
	Group/group_average_response-csf.txt
rm Group/*_dwi_response-*.txt

for i in  sub-*
	do
		sub=${i:0:7} 
		dwi2fod \
			msmt_csd \
				${sub}/dwi/${sub}_dwi_upsampled.mif \
				Group/group_average_response-wm.txt \
				${sub}/dwi/${sub}_wmfod.mif \
				Group/group_average_response-gm.txt \
				${sub}/dwi/${sub}_gmfod.mif \
				Group/group_average_response-csf.txt  \
				${sub}/dwi/${sub}_csf.mif \
				-mask ${sub}/dwi/${sub}_dwi-mask_upsampled.mif \
				-nthreads 10
			mtnormalise \
				${sub}/dwi/${sub}_wmfod.mif \
				${sub}/dwi/${sub}_wmfod-norm.mif \
				${sub}/dwi/${sub}_gmfod.mif \
				${sub}/dwi/${sub}_gmfod-norm.mif \
				${sub}/dwi/${sub}_csf.mif \
				${sub}/dwi/${sub}_csf-norm.mif \
				-mask ${sub}/dwi/${sub}_dwi-mask_upsampled.mif \
				-nthreads 10
	done

for i in  sub-*
	do
		sub=${i:0:7} 
		cp \
			${sub}/dwi/${sub}_wmfod-norm.mif \
			Templates/FOD_Input/${sub}_fd.mif
		cp \
			${sub}/dwi/${sub}_dwi-mask_upsampled.mif \
			Templates/Mask_Input/${sub}_pre-mask.mif
	done
# create a white matter fiber orientation template 
population_template \
		Templates/FOD_Input/ \
		-mask Templates/Mask_Input/ \
		Templates/wmfod-template.mif \
		-voxel_size 1.25 \
		-nthreads 4

for i in  sub-*
	do
		sub=${i:0:7} 
	# register all of the individual wmfod images to the population template, using their masks
	mrregister \
		${sub}/dwi/${sub}_wmfod.mif \
		-mask1 ${sub}/dwi/${sub}_dwi-mask_upsampled.mif \
		Templates/wmfod-template.mif \
		-nl_warp \
			${sub}/dwi/${sub}_sub2template-warp.mif \
			${sub}/dwi/${sub}_template2sub-warp.mif \
			-nthreads 4
	# take the warps generated from aligning the DWI image, and apply it to the mask
	mrtransform \
		${sub}/dwi/${sub}_dwi-mask_upsampled.mif \
		-warp ${sub}/dwi/${sub}_sub2template-warp.mif \
		-interp nearest \
		-datatype bit \
		${sub}/dwi/${sub}_dwi-mask_template-space.mif \
		-nthreads 4
done
 
# compute the minimum overlap of all of the masks
mrmath \
	sub-*/dwi/*dwi-mask_template-space.mif \
	min \
	Templates/template-space_mask.mif \
	-datatype bit \
	-nthreads 4
	

templatedir=../Derivatives/Templates/
# the template mask and the population template are used to estimate template fixels
fod2fixel \
	-mask ${templatedir}template-space_mask.mif \
	-fmls_peak_value 0.06 \
	${templatedir}wmfod-template.mif \
	${templatedir}fixel_mask \
	-nthreads 4
# 40mil tracks are seeded across the whole brain, using default parameters
tckgen \
	-angle 22.5 \
	-maxlen 250 \
	-minlen 10 \
	-power 1.0 \
	${templatedir}wmfod-template.mif \
	-seed_dynamic ${templatedir}wmfod-template.mif \
	-mask ${templatedir}template-space_mask.mif \
	-select 40000000 \
	-cutoff 0.06 \
	${templatedir}tracks/tracks_040-mill_wholebrain.tck \
	-nthreads 4
	
#trim the tractogram down to a more manageable size, whilst increasing the anatomical validity of the remaining tracks
tcksift \
	${templatedir}tracks/tracks_040-mill_wholebrain.tck \
	${templatedir}wmfod-template.mif \
	${templatedir}tracks/tracks_001-mill_wholebrain_sift.tck \
	-term_number 1000000 \
	-nthreads 12
# creates a fixel-fixel  connectivity matrix 
fixelconnectivity \
	${templatedir}fixel_mask/ \
	${templatedir}tracks/tracks_001-mill_wholebrain_sift.tck \
	${templatedir}matrix/ \
	-nthreads 12
