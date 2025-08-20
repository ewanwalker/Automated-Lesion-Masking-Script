idu=1000 # run id -u in terminal 
idg=1000 # run id -g in terminal 

cd ../derivatives/templates
	mrconvert \
		template-space_mask.mif \
		bet-avg.nii.gz
		
cd ../../meningioma_raw_data

# make a folder for the results of each pipeline run on T1-CE Scans

for i in  sub-*_T1.nii.gz #  loop through each image 
do
	cd ../derivatives/meningioma_patients # enter the structural derivatives folder
	mkdir  ${i:0:7} # create files for each of the T1 image derivatives
done

cd ../../meningioma_raw_data
echo "Starting Loop"
for i in  sub-*_T1.nii.gz # for testing purposes, the T1 images are in one directory
do
		identifier=${i:0:7} 
		brain=${identifier}_T1.nii.gz
		echo $brain
		# Checking if bias field correction has already been completed
		if [[ ! -e  ../derivatives/meningioma_patients/${identifier}/${identifier}_biascorr.nii.gz ]]
		then
			#Bias Field Correction
			N4BiasFieldCorrection \
						-i $brain \
						-o  ../derivatives/meningioma_patients/${identifier}/${identifier}_biascorr.nii.gz
			echo "Bias Field Corrected on Brain ID:"${identifier} 
		else
				echo "Already done bias field correction"
		fi
		cd ../derivatives/meningioma_patients/${identifier}
		# Checking if Resampling has already been completed
		if [[ ! -e  ${identifier}_iso.nii.gz ]]
		then
			#Resample 
			mrgrid \
						 ${identifier}_biascorr.nii.gz \
						regrid \
						-voxel 1.00 \
						 ${identifier}_iso.nii.gz
			echo "Resampled Brain ID:"${identifier} 
		else
				echo "Already Resampled"
		fi

		# Checking if Skull Strip has already been completed
		if [[ ! -e  ${identifier}_bet.nii.gz ]]
		then
			#Skull Strip 
			mri_synthstrip \
						-i  ${identifier}_iso.nii.gz \
						-o  ${identifier}_bet.nii.gz
			if [[ ! -e ${sub}_bet.nii.gz ]] 
					then
						echo "Using FSL instead"
						bet \
						${identifier}_iso.nii.gz \
						 ${identifier}_bet.nii.gz -B
					fi
			echo "Skull Stripped Brain ID:"${identifier} 
		else
				echo "Already Skull Stripped"
		fi

		# Checking if stripped template registration has already been completed
		if [[ ! -e ${identifier}_bet2std.nii.gz ]]
		then
			#registered to the stripped template image 
			flirt \
						-omat ${identifier}_bet2std.mat \
						-in ${identifier}_bet.nii.gz \
						-ref ../../../derivatives/templates/bet-avg.nii.gz \
						-out ${identifier}_bet2std.nii.gz
			echo "registered to the stripped template image, Brain ID:"${identifier}
		else
				echo "Already registered to the stripped template image "
		fi

		# Checking if masking has already been completed
		if [[ ! -e  ${identifier}_mask.nii.gz ]]
		then
			sudo docker run -it --rm -v $(pwd):/data --user ${idu}:${idg} neuronets/ams:latest-cpu  ${identifier}_iso.nii.gz ${identifier}_mask
			echo "Meningioma Masked, Brain ID:"${identifier} 
		else
				echo "Already masked meningioma"
		fi
		# check if the refinement is done `
		if [[ ! -e  ${identifier}_roi.nii.gz ]]
		then
			echo "clusterising"
			#clusterising map
			3dClusterize \
					-inset  ${identifier}_mask_orig.nii.gz \
					-ithr 0 \
					-idat 0 \
					-clust_nvox 1 \
					-NN 3 \
					-bisided 0 1 \
					-pref_map  ${identifier}_map.nii.gz
			echo "Meningioma Clusterised, Brain ID:"${identifier} 
			fslmaths \
					${identifier}_map.nii.gz \
					-uthr 1 \
					${identifier}_roi.nii.gz

			echo " leaving only the largest cluster, Brain ID:"${identifier} 
		else
				echo "Already refined mask"
		fi

		# Checking if registration to white space template has already been completed
		if [[ ! -e  ${identifier}_space-temp_roi.nii.gz ]]
		then
			flirt \
						-in  ${identifier}_roi.nii.gz \
						-ref ../../../derivatives/templates/bet-avg.nii.gz \
						-init  ${identifier}_bet2std.mat \
						-applyxfm \
						-out  ${identifier}_space-temp_roi.nii.gz
			echo "Registered to template space, Brain ID:"${identifier} 
		else
				echo "Already registered to template space"
		fi
		# the template-space lesion mask is converted into mif format, for use with tckgen
		mrconvert \
			${identifier}_space-temp_roi.nii.gz \
			${identifier}_space-temp_roi.mif
		# 100000 tracks are seeded from the template-space lesion, using default parameters
		tckgen \
			-angle 22.5 \
			-maxlen 250 \
			-minlen 10 \
			-power 1.0 \
			../../../derivatives/templates/wmfod-template.mif \
			-seed_image ${identifier}_space-temp_roi.mif \
			-mask ../../../derivatives/templates/template-space_mask.mif \
			-select 100000 \
			-cutoff 0.06 \
			${identifier}_tractogram.tck \
			-nthreads 12
		# the lesion tractograms are converted into fixel maps, which can be overlaid and compared
		tck2fixel \
			${identifier}_tractogram.tck \
			../../../derivatives/templates/fixel_mask \
			../../../derivatives/templates/tracks/lesion-tracks/ \
			${identifier}_lesion-track.mif
		# lesion-track fixel maps are binarised for spatial comparison
		mrthreshold \
			../../../derivatives/templates/tracks/lesion-tracks/${identifier}_lesion-track.mif \
			-abs 1 \
			../../../derivatives/templates/tracks/lesion-tracks/${identifier}_lesion-bin.mif
		
		cd ../../../meningioma_raw_data
done
