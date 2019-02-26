#!/bin/bash

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
pwd
rm -rf .aws-sam/build/layers

echo "Creating layer zipfile"
cd layer
zip -9 pytorch-1.0.1-lambda-layer.zip .requirements.zip -r python/
