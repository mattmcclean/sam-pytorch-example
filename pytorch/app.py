# this import statement is needed if you want to use the AWS Lambda Layer called "pytorch-v1-py36"
# it unzips all of the pytorch & dependency packages when the script is loaded to avoid the 250 MB unpacked limit in AWS Lambda
try:
    import unzip_requirements
except ImportError:
    pass

import os
import io
import json
import tarfile
import glob
import time
import logging

import boto3
import requests
import PIL

import torch
import torch.nn.functional as F
from torchvision import models, transforms

# load the S3 client when lambda execution context is created
s3 = boto3.client('s3')

# classes for the image classification
classes = []

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# get bucket name from ENV variable
MODEL_BUCKET=os.environ.get('MODEL_BUCKET')
logger.info(f'Model Bucket is {MODEL_BUCKET}')

# get bucket prefix from ENV variable
MODEL_KEY=os.environ.get('MODEL_KEY')
logger.info(f'Model Prefix is {MODEL_KEY}')

# processing pipeline to resize, normalize and create tensor object
preprocess = transforms.Compose([
    transforms.Resize(256),
    transforms.CenterCrop(224),
    transforms.ToTensor(),
    transforms.Normalize(
        mean=[0.485, 0.456, 0.406],
        std=[0.229, 0.224, 0.225]
    )
])

def load_model():
    """Loads the PyTorch model into memory from a file on S3.

    Returns
    ------
    Vision model: Module
        Returns the vision PyTorch model to use for inference.
    
    """      
    global classes
    logger.info('Loading model from S3')
    model_dir = '/tmp/model'
    local_model=f'{model_dir}/model.tar.gz'
    # download the model tar.gz file from S3 and extract
    logger.info(f'Downloading model from S3 to {local_model}')
    if not os.path.exists(model_dir):
        os.mkdir(model_dir)
    s3.download_file(
                    MODEL_BUCKET, MODEL_KEY, local_model)
    logger.info('Extracting model tarfile')
    tarfile.open(local_model).extractall(model_dir)
    os.remove(local_model)
    logger.info('Getting classes from file')
    # get the classes from saved 'classes.txt' file
    with open(f'{model_dir}/classes.txt', 'r') as f:
        classes = f.read().splitlines()
    logger.info(f'Classes are {classes}')    
    model_path = glob.glob(f'{model_dir}/*_jit.pth')[0]
    logger.info(f'Model path is {model_path}')
    model = torch.jit.load(model_path, map_location=torch.device('cpu'))
    return model.eval()

# load the model when lambda execution context is created
model = load_model()

def predict(input_object, model):
    """Predicts the class from an input image.

    Parameters
    ----------
    input_object: Tensor, required
        The tensor object containing the image pixels reshaped and normalized.

    Returns
    ------
    Response object: dict
        Returns the predicted class and confidence score.
    
    """        
    logger.info("Calling prediction on model")
    start_time = time.time()
    predict_values = model(input_object)
    logger.info("--- Inference time: %s seconds ---" % (time.time() - start_time))
    preds = F.softmax(predict_values, dim=1)
    conf_score, indx = torch.max(preds, dim=1)
    predict_class = classes[indx]
    logger.info(f'Predicted class is {predict_class}')
    logger.info(f'Softmax confidence score is {conf_score.item()}')
    response = {}
    response['class'] = str(predict_class)
    response['confidence'] = conf_score.item()
    return response
    
def input_fn(request_body):
    """Pre-processes the input data from JSON to PyTorch Tensor.

    Parameters
    ----------
    request_body: dict, required
        The request body submitted by the client. Expect an entry 'url' containing a URL of an image to classify.

    Returns
    ------
    PyTorch Tensor object: Tensor
    
    """    
    logger.info("Getting input URL to a image Tensor object")
    if isinstance(request_body, str):
        request_body = json.loads(request_body)
    img_request = requests.get(request_body['url'], stream=True)
    img = PIL.Image.open(io.BytesIO(img_request.content))
    img_tensor = preprocess(img)
    img_tensor = img_tensor.unsqueeze(0)
    return img_tensor
    
def lambda_handler(event, context):
    """Lambda handler function

    Parameters
    ----------
    event: dict, required
        API Gateway Lambda Proxy Input Format

        Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

    context: object, required
        Lambda Context runtime methods and attributes

        Context doc: https://docs.aws.amazon.com/lambda/latest/dg/python-context-object.html

    Returns
    ------
    API Gateway Lambda Proxy Output Format: dict

        Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
    """
    print("Starting event")
    logger.info(event)
    print("Getting input object")
    input_object = input_fn(event['body'])
    print("Calling prediction")
    response = predict(input_object, model)
    print("Returning response")
    return {
        "statusCode": 200,
        "body": json.dumps(response)
    }