#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "Usage: $0 S3_BUCKET <S3_PREFIX> <LAYER_NAME> <LAYER_ZIP_NAME>. Must provide at least an S3 bucket name."
    exit 1
fi

S3_BUCKET=$1
S3_PREFIX=${2:-lambda-layers}
LAYER_NAME=${3:-pytorch-v1-py36}
LAYER_ZIP_NAME=${4:-pytorch-1.0.1-lambda-layer.zip}
echo "Using S3 Bucket ${S3_BUCKET} and S3 Prefix ${S3_PREFIX} and Lambda Layer name ${LAYER_NAME}"

echo "Installing packages"
cd ..
sam build -u

echo "Bundling PyTorch packages into zip file"
mkdir -p .aws-sam/build/layers
cp -R .aws-sam/build/PyTorchFunction/* .aws-sam/build/layers/
cd .aws-sam/build/layers/ 
du -sch . 
find . -type d -name "tests" -exec rm -rf {} +
find . -type d -name "__pycache__" -exec rm -rf {} +
rm -rf ./{caffe2,wheel,pkg_resources,boto*,aws*,pip,pipenv,setuptools} 
rm ./torch/lib/libtorch.so 
rm -rf ./{*.egg-info,*.dist-info} 
find . -name \*.pyc -delete
rm {app.py,requirements.txt,__init__.py} 
du -sch . 
cd - 
# build the .requirements.zip file
cd .aws-sam/build/layers/
zip -9 -q -r ../../../layer/.requirements.zip . 
cd -

echo "Creating layer zipfile"
cd layer
zip -9 ${LAYER_ZIP_NAME} .requirements.zip -r python/

echo "Uploading zip to S3"
aws s3 cp ${LAYER_ZIP_NAME} s3://${S3_BUCKET}/${S3_PREFIX}/${LAYER_ZIP_NAME}

echo "Creating Lambda Layer"
aws lambda publish-layer-version \
    --layer-name ${LAYER_NAME} \
    --description "Lambda layer of PyTorch 1.0.1 zipped to be extracted with unzip_requirements file" \
    --content S3Bucket=${S3_BUCKET},S3Key=${S3_PREFIX}/${LAYER_ZIP_NAME} \
    --compatible-runtimes python3.6
    
echo "Delete the build directory"
rm -rf ../.aws-sam/build