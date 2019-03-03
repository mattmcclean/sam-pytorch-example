# PyTorch model deployment on AWS Lambda

## Table of Contents

   * [PyTorch model deployment on AWS Lambda](#pytorch-model-deployment-on-aws-lambda)
      * [Requirements](#requirements)
      * [Setup process](#setup-process)
      * [Lambda function request/response API](#lambda-function-requestresponse-api)
      * [Local development](#local-development)
      * [Packaging and deployment](#packaging-and-deployment)
      * [Fetch, tail, and filter Lambda function logs](#fetch-tail-and-filter-lambda-function-logs)
      * [Testing](#testing)
      * [Cleanup](#cleanup)
      * [Advanced concepts](#advanced-concepts)
      * [SAM and AWS CLI commands](#sam-and-aws-cli-commands)

This is a sample [SAM](https://docs.aws.amazon.com/lambda/latest/dg/deploying-lambda-apps.html) application to deploy a PyTorch model on AWS Lambda.

It deploys a computer vision classifier by receving a URL of an image and returns the predicted class with a confidence value.

The file structure of this application is the following:

```bash
.
├── README.md                       <-- This instructions file
├── event.json                      <-- API Gateway Proxy Integration event payload
├── layer                           <-- Scripts for setting up the Lambda Layer for PyTorch
│   ├── create_code_buckets.sh
│   ├── create_layer_zipfile.sh
│   ├── publish_lambda_layers.sh  
│   └──python                      
│       └──  unzip_requirements.py     
├── pytorch                         <-- Source code for a lambda function
│   ├── __init__.py
│   ├── app.py                      <-- Lambda function code
│   ├── requirements.txt            <-- Python requirements describing package dependencies to be included in Lambda layer
├── template.yaml                   <-- SAM Template
└── tests                           <-- Unit tests
    └── unit
        ├── __init__.py
        └── test_handler.py
```

## Requirements

* [AWS CLI](https://aws.amazon.com/cli/) already configured with Administrator permission
* [Python 3 installed](https://www.python.org/downloads/)
* [Docker installed](https://www.docker.com/community-edition)

## Setup process

**Create S3 Bucket**

First, we need a `S3 bucket` where we can upload our Lambda functions and layers packaged as ZIP files before we deploy anything - If you don't have a S3 bucket to store code artifacts then this is a good time to create one:

```bash
aws s3 mb s3://BUCKET_NAME
```

**Upload your PyTorch model to S3**

The SAM application expects a PyTorch model in [TorchScript](https://pytorch.org/docs/stable/jit.html?highlight=jit#module-torch.jit) format to be saved to S3 along with a classes text file with the output class names.

An example of packaging and uploading a trained resnet PyTorch model to S3 is shown below:

```python
# save the PyTorch model in TorchScript format
import torch
trace_input = torch.ones(1,3,299,299).cuda()
jit_model = torch.jit.trace(model.float(), trace_input)
torch.jit.save(jit_model, 'resnet50_jit.pth')

# bundle the model with the classes text file in a tar.gz file
import tarfile
with tarfile.open('model.tar.gz', 'w:gz') as f:
    f.add('resnet50_jit.pth')
    f.add('classes.txt')

# upload tarfile to S3
import boto3
s3 = boto3.resource('s3')
# replace 'mybucket' with the name of your S3 bucket
s3.meta.client.upload_file('model.tar.gz', 
    'REPLACE_THIS_WITH_YOUR_MODEL_S3_BUCKET_NAME', 
    'REPLACE_THIS_WITH_YOUR_MODEL_S3_OBJECT_KEY')
```

## Lambda function request/response API

**Lambda Request Body format**

The Lambda function expects a JSON body request object containing the URL of an image to classify.

Example:
```json
{
    "url": "REPLACE_THIS_WITH_AN_IMAGE_URL"
}
```
**Lambda Response format**

The Lambda function will return a JSON object containing the predicted class and confidence score.

Example:
```json
{
    "statusCode": 200,
    "body": {
        "class": "english_cocker_spaniel",
        "confidence": 0.99
    }
}
```

## Local development

**Creating test Lambda Environment Variables**

First create a file called `env.json` with the payload similar to the following substituting the values for the S3 Bucket and Key where your PyTorch model has been saved on S3.

```json
{
    "PyTorchFunction": {
      "MODEL_BUCKET": "REPLACE_THIS_WITH_YOUR_MODEL_S3_BUCKET_NAME",  
      "MODEL_KEY": "REPLACE_THIS_WITH_YOUR_MODEL_S3_OBJECT_KEY"      
    }
}
```

**Invoking function locally using a local sample payload**

Edit the file named `event.json` and enter a value for the JSON value `url` to the image you want to classify.

Call the following sam command to test the function locally.

```bash
sam local invoke PyTorchFunction -n env.json -e event.json
```

**Invoking function locally through local API Gateway**

```bash
sam local start-api -n env.json
```

If the previous command ran successfully you should now be able to send a post request to the local endpoint.

An example is the following:

```bash
curl -d "{\"url\":\"REPLACE_THIS_WITH_AN_IMAGE_URL\"}" \
    -H "Content-Type: application/json" \
    -X POST http://localhost:3000/invocations
```


**SAM CLI** is used to emulate both Lambda and API Gateway locally and uses our `template.yaml` to understand how to bootstrap this environment (runtime, where the source code is, etc.) - The following excerpt is what the CLI will read in order to initialize an API and its routes:

```yaml
...
Events:
    PyTorch:
        Type: Api # More info about API Event Source: https://github.com/awslabs/serverless-application-model/blob/master/versions/2016-10-31.md#api
        Properties:
            Path: /invocations
            Method: post
```

## Packaging and deployment

AWS Lambda Python runtime requires a flat folder with all dependencies including the application. SAM will use `CodeUri` property to know where to look up for both application and dependencies:

```yaml
...
    PyTorchFunction:
        Type: AWS::Serverless::Function
        Properties:
            CodeUri: pytorch/
            ...
```

Next, run the following command to package our Lambda function to S3:

```bash
sam package \
    --output-template-file packaged.yaml \
    --s3-bucket REPLACE_THIS_WITH_YOUR_S3_BUCKET_NAME
```

Next, the following command will create a Cloudformation Stack and deploy your SAM resources.

```bash
sam deploy \
    --template-file packaged.yaml \
    --stack-name pytorch-sam-app \
    --capabilities CAPABILITY_IAM
```

> **See [Serverless Application Model (SAM) HOWTO Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-quick-start.html) for more details in how to get started.**

After deployment is complete you can run the following command to retrieve the API Gateway Endpoint URL:

```bash
aws cloudformation describe-stacks \
    --stack-name pytorch-sam-app \
    --query 'Stacks[].Outputs[?OutputKey==`PyTorchApi`]' \
    --output table
``` 

## Fetch, tail, and filter Lambda function logs

To simplify troubleshooting, SAM CLI has a command called sam logs. sam logs lets you fetch logs generated by your Lambda function from the command line. In addition to printing the logs on the terminal, this command has several nifty features to help you quickly find the bug.

`NOTE`: This command works for all AWS Lambda functions; not just the ones you deploy using SAM.

```bash
sam logs -n PyTorchFunction --stack-name pytorch-sam-app --tail
```

You can find more information and examples about filtering Lambda function logs in the [SAM CLI Documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-logging.html).

## Testing

Next, we install test dependencies and we run `pytest` against our `tests` folder to run our initial unit tests:

```bash
pip install pytest pytest-mock --user
python -m pytest tests/ -v
```

## Cleanup

In order to delete our Serverless Application recently deployed you can use the following AWS CLI Command:

```bash
aws cloudformation delete-stack --stack-name pytorch-sam-app
```

## Advanced concepts

Have shown how to create a SAM application to do PyTorch model inference. Now you will learn how to create your own Lambda Layer to package the PyTorch dependencies.

**Create Lambda Layer for PyTorch packages**

The project uses [Lambda layers](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html) for deploying the PyTorch libraries. **Lambda Layers** allow you to bundle dependencies without needing to include them in your application bundle.

The project defaults to using a public Lambda Layer ARN `arn:aws:lambda:eu-west-1:934676248949:layer:pytorchv1-py36:1` containing the PyTorch packages. It is publically accessible. To build and publish your own PyTorch layer follow the instuctions below.

AWS Lambda has a limit of 250 MB for the deployment package size including lamba layers. PyTorch plus its dependencies is more than this so we need to implement a trick to get around this limit. We will create a zipfile called `.requirements.zip` with all the PyTorch and associated packages. We will then add this zipfile to the Lambda Layer zipfile along with a python script called `unzip_requirements.py`. The python script will extract the zipfile `.requirements.zip` to the `/tmp` when the Lambda execution context is created. 

1. Goto the directory named `layer` and run the script named `create_layer_zipfile.sh`. This will launch the command `sam build --use-container` to download the packages defined in the `requirements.txt` file. The script will remove unncessary files and directories and then create the zipfile `.requirements.zip` then bundle this zipfile with the python script `unzip_requirements.py` to the zipfile `pytorch-1.0.1-lambda-layer.zip`.

```bash
cd layer
./create_layer_zipfile.sh
```

1. Upload the Lambda Layer zipfile to one of your S3 buckets. Take note of the S3 URL as it will be used when creating the Lambda Layer.

```bash
aws s3 cp pytorch-1.0.1-lambda-layer.zip s3://REPLACE_THIS_WITH_YOUR_S3_BUCKET_NAME/lambda-layers/pytorch-1.0.1-lambda-layer.zip
```

1. Now we can create the Lambda Layer version. Execute the following AWS CLI command:

```bash
aws lambda publish-layer-version \
    --layer-name "pytorchv1-p36" \
    --description "Lambda layer of PyTorch 1.0.1 zipped to be extracted with unzip_requirements file" \
    --content "S3Bucket=REPLACE_THIS_WITH_YOUR_S3_BUCKET_NAME,S3Key=lambda-layers/lambda-layers/pytorch-1.0.1-lambda-layer.zip" \
    --compatible-runtimes "python3.6" 
```

1. Take note of the value of the response parameter `LayerVersionArn`. 

The following examples show how you can use your own Lambda Layer in both local testing and then deploying to AWS. They will overide the default Lambda Layer in the file `template.yaml`.

**Invoking function locally overriding Lambda Layer default**

```bash
sam local invoke PyTorchFunction -n env.json -e event.json --parameter-overrides LambdaLayerArn=REPLACE_WITH_YOUR_LAMBDA_LAYER_ARN
```

**Invoking function through local API Gateway overriding Lambda Layer default**

```bash
sam local start-api -n env.json --parameter-overrides LambdaLayerArn=REPLACE_WITH_YOUR_LAMBDA_LAYER_ARN
```

**Deploying the Lambda function overriding Lambda Layer default**

```bash
sam deploy \
    --template-file packaged.yaml \
    --stack-name pytorch-sam-app \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides LambdaLayerArn=REPLACE_WITH_YOUR_LAMBDA_LAYER_ARN

```

**Lambda code format**

At the beginning of the file `pytorch/app.py` you need to include the following code that will unzip the package file containing the python libs. It will extract the package zip file named `.requirements.zip` to the `/tmp` to get around the unzipped Lambda deployment package limit of 250 MB.

```python
try:
    import unzip_requirements
except ImportError:
    pass
```

After these lines you can import all the python libraries you need to.

## SAM and AWS CLI commands

All commands used throughout this document

```bash
# Generate event.json via generate-event command
sam local generate-event apigateway aws-proxy > event.json

# Invoke function locally with event.json as an input
sam local invoke PyTorchFunction --event event.json

# Run API Gateway locally
sam local start-api

# Create S3 bucket
aws s3 mb s3://BUCKET_NAME

# Package Lambda function defined locally and upload to S3 as an artifact
sam package \
    --output-template-file packaged.yaml \
    --s3-bucket REPLACE_THIS_WITH_YOUR_S3_BUCKET_NAME

# Deploy SAM template as a CloudFormation stack
sam deploy \
    --template-file packaged.yaml \
    --stack-name pytorch-sam-app \
    --capabilities CAPABILITY_IAM

# Describe Output section of CloudFormation stack previously created
aws cloudformation describe-stacks \
    --stack-name pytorch-sam-app \
    --query 'Stacks[].Outputs[?OutputKey==`PyTorchApi`]' \
    --output table

# Tail Lambda function Logs using Logical name defined in SAM Template
sam logs -n PyTorchFunction --stack-name pytorch-sam-app --tail
```

