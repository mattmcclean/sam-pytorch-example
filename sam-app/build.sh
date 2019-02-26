#!/bin/bash

BUCKET="mmcclean-lambda-code"

ZIP_FILE=".requirements.zip"

sam build -u

aws s3 ls s3://${BUCKET}/pytorch-lambda/${ZIP_FILE}
if [[ $? -ne 0 ]]; then
  echo "PyTorch Zip file does not exist in S3"

  echo "Bundling PyTorch layer files"
  mkdir -p .aws-sam/build/layers/python
  cp -R .aws-sam/build/PyTorchFunction/* .aws-sam/build/layers/python/
  cd .aws-sam/build/layers/python/ && \
  du -sch . && \
  find . -type d -name "tests" -exec rm -rf {} + && \
  find . -type d -name "__pycache__" -exec rm -rf {} + && \
  rm -rf ./{caffe2,wheel,pkg_resources,boto*,aws*,pip,pipenv,setuptools} && \
  rm ./torch/lib/libtorch.so && \
  rm -rf ./{*.egg-info,*.dist-info} && \
  find . -name \*.pyc -delete && \
  rm -rf ./numpy* && \
  rm {app.py,requirements.txt,__init__.py} && \
  du -sch . && cd - && \
  cd .aws-sam/build/layers/ && zip -9 -q -r ../${ZIP_FILE} . && rm -rf .aws-sam/build/layers && cd -

  echo "Copying PyTorch Zip file to S3"
  aws s3 cp .aws-sam/build/${ZIP_FILE} s3://${BUCKET}/pytorch-lambda/${ZIP_FILE}
  
  #echo "Publish Lambda layer"
  aws lambda publish-layer-version --layer-name "pytorch-v1-py36-sans-numpy" \
        --description "Lambda layer of PyTorch 1.0.1 without Numpy for Python 3.6" \
        --content S3Bucket=${BUCKET},S3Key=pytorch-lambda/${ZIP_FILE} \
        --compatible-runtimes python3.6
fi


