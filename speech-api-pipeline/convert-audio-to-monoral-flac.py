# coding: utf-8
import boto3
import json
import os
import urllib
import re

from datetime import datetime, timezone, timedelta

REGION_NAME = 'ap-northeast-1'
PIPELINE_ID = os.environ['PIPELINE_ID']
PRESET_ID = os.environ['PRESET_ID']

s3 = boto3.resource('s3')
transcoder = boto3.client('elastictranscoder', REGION_NAME)


def is_object_audio_or_movie(content_type):
    print("uploaded object content-type: " + content_type)
    if 'audio' in content_type or 'video' in content_type or 'stream' in content_type:
        return True
    else:
        return False


def lambda_handler(event, context):
    try:
        print("Loading function")
        s3_bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
        object_key = urllib.parse.unquote_plus(event["Records"][0]["s3"]["object"]["key"], encoding="utf8")
        s3_object = s3.Object(s3_bucket_name, object_key)
        if not is_object_audio_or_movie(s3_object.content_type):
            return print("Uploaded file is not suitable for Amazon Elastic Transcoder.")

        print("bucket: " + s3_bucket_name)
        print("uploaded object key: " + object_key)

        # If there is the processed file with the same name, ets fails.
        # So I add time prefix to each file.
        jst = timezone(timedelta(hours=+9), 'JST')
        now = datetime.now(jst)
        flac_path = 'flac/{0:%Y%m%d%H%M}/'.format(now)
        object_name = re.sub(r".*/", "", object_key)

        job = transcoder.create_job(
            PipelineId=PIPELINE_ID,
            Inputs=[
                {
                    'Key': object_key,
                    'FrameRate': 'auto',
                    'Resolution': 'auto',
                    'AspectRatio': 'auto',
                    'Interlaced': 'auto',
                    'Container': 'auto',
                }
            ],
            Outputs=[
                {
                    'Key': flac_path + '{}.flac'.format(re.sub(r'\..*', '', object_name)),
                    'PresetId': PRESET_ID,
                }
            ]
        )
        print("Create a transcoder job. job_id: " + job['Job']['Id'])

    except Exception as e:
        print(e)
