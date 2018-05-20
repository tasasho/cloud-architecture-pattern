#!/usr/bin/env python
import boto3
import os
import re
import urllib

from google.cloud import storage

GCS_BUCKET_NAME = os.environ['GCS_BUCKET_NAME']
GCS_PREFIX = "flac/"
s3 = boto3.resource('s3')


def put_audio_file_to_gcs(GCS_BUCKET_NAME, local_path, GCS_PREFIX):
    gcs = storage.Client()
    gcs_bucket = gcs.get_bucket(GCS_BUCKET_NAME)
    object_key = GCS_PREFIX + re.sub(r'.*/', '', local_path)
    blob = gcs_bucket.blob(object_key)

    blob.upload_from_filename(local_path)
    print('File {} uploaded to {}.'.format(
        local_path,
        GCS_BUCKET_NAME + '/' + object_key)
    )


def lambda_handler(event, context):
    try:
        print("Loading function")
        s3_bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
        object_key = urllib.parse.unquote_plus(
            event["Records"][0]["s3"]["object"]["key"], 
            encoding="utf8"
        )

        print("bucket: " + s3_bucket_name)
        print("uploaded object key: " + object_key)

        object = s3.Object(s3_bucket_name, object_key)
        local_path = "/tmp/" + re.sub(r'.*/', '', object_key)
        object.download_file(local_path)
        put_audio_file_to_gcs(GCS_BUCKET_NAME, local_path, GCS_PREFIX)

    except Exception as e:
        print(e)

