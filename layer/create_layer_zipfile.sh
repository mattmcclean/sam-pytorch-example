#!/bin/bash

set -e

LAYER_ZIP_NAME=${1:-pytorch-1.0.1-lambda-layer.zip}

if [[ -f "${LAYER_ZIP_NAME}" ]]; then
    echo "Deleting zipfiles"
    rm *.zip
fi

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

echo "Delete the requirements zipfile & build directory"
rm .requirements.zip
rm -rf ../.aws-sam/build