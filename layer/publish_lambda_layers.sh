#!/bin/bash

set -e

if [[ $# -eq 0 ]] ; then
    echo "Usage: $0 S3_BUCKET_PREFIX <S3_OBJECT_PREFIX> <LAYER_NAME> <LAYER_ZIP_NAME> <REGIONS>." 
    echo "Must provide at least an S3 bucket prefix."
    exit 1
fi

# process the input parameters
S3_BUCKET_PREFIX=$1
S3_OBJECT_PREFIX=${2:-lambda-layers}
LAYER_NAME=${3:-pytorchv1-p36}
LAYER_ZIP_NAME=${4:-pytorch-1.0.1-lambda-layer.zip}
REGIONS=${5:-$(aws configure get region)}
IFS=',' read -r -a regionarr <<< "$REGIONS"

echo "Using S3 Bucket prefix ${S3_BUCKET_PREFIX}"
echo "S3 Prefix ${S3_OBJECT_PREFIX}"
echo "Lambda Layer name is ${LAYER_NAME}"
echo "Layer Zip ${LAYER_ZIP_NAME}"
echo "Region list is ${REGIONS}"

if [[ ! -f "${LAYER_ZIP_NAME}" ]]; then
    echo "Create zipfile first by running  the script ./create_layer_zipfile.sh <LAYER_ZIP_NAME>"
    exit 1
fi

echo "Creating Lambda Layers"
for region in "${regionarr[@]}"
do
    echo "Uploading zip to S3 bucket \"${S3_BUCKET_PREFIX}-${region}\""
    aws s3 sync . s3://${S3_BUCKET_PREFIX}-${region}/${S3_OBJECT_PREFIX}/ --exclude "*" --include "${LAYER_ZIP_NAME}"

    echo "Creating Lambda layer in region: $region"
    aws lambda publish-layer-version \
        --layer-name "${LAYER_NAME}" \
        --description "Lambda layer of PyTorch 1.0.1 zipped to be extracted with unzip_requirements file" \
        --content "S3Bucket=${S3_BUCKET_PREFIX}-${region},S3Key=${S3_OBJECT_PREFIX}/${LAYER_ZIP_NAME}" \
        --compatible-runtimes "python3.6" \
        --license-info "MIT" \
        --region "${region}"

    echo "Creating lambda layer permissions"
    aws lambda add-layer-version-permission \
        --layer-name "${LAYER_NAME}" \
        --version-number 1 \
        --statement-id "public-access" \
        --action "lambda:GetLayerVersion" \
        --principal "*" \
        --region "${region}"
done
