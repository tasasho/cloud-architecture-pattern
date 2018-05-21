#!/usr/bin/env python
import boto3
import logging
import os
import re
import time
# TODO: Implement log outputting
# import logging

from google.cloud import storage
# pydub requires installing ffmpeg. It is complicated for Raspberry Pi
from pydub import AudioSegment
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer


# Directory path which is monitored by watchdog
base_dir = '/home/pi/Desktop/audio_files'


def transfer_audio_to_cloud(event):
    if event.is_directory:
        return

    file_path = event.src_path
    file_name = re.sub(r'.*/', '', file_path)
    file_extension = lower_file_extension(file_path)
    
    if file_extension in ('.flac'):
        file_sound = AudioSegment.from_file(file_path, file_extension[1:])
        put_cloud_depending_on_channel_num(file_sound.channels, file_path)

    if file_extension in ('.mp3', '.wav'):
        # As Speech API doesn't correspond to mp3, we send it to AWS for converting.
        put_audio_file_to_s3(file_path)


def lower_file_extension(filename):
    return os.path.splitext(filename)[-1].lower()


def put_cloud_depending_on_channel_num(channel_num, file_path):
    # As Speech API doesn't correspond to stereo, we send it to AWS for converting.
    if channel_num == 2:
        put_audio_file_to_s3(file_path)

    if channel_num == 1:
        put_audio_file_to_gcs(file_path)


def put_audio_file_to_gcs(file_path):
    gcs_bucket = "{your bucket name}"
    gcs_prefix = "flac/"
    gcs = storage.Client()
    bucket = gcs.get_bucket(gcs_bucket)
    object_key = gcs_prefix + re.sub(r'.*/', '', file_path)
    blob = bucket.blob(object_key)

    blob.upload_from_filename(file_path)
    print('File {} uploaded to {}.'.format(
        file_path,
        gcs_bucket + '/' + object_key)
    )


def put_audio_file_to_s3(file_path):
    s3_bucket = "{your bucket name}"
    s3_prefix = "pre-conversion/"
    s3 = boto3.resource('s3')
    bucket = s3.Bucket(s3_bucket)
    object_key = s3_prefix + re.sub(r'.*/', '', file_path)

    bucket.upload_file(file_path, object_key)
    print('File {} uploaded to {}.'.format(
        file_path,
        s3_bucket + '/' + object_key)
    )


class ChangeHandler(FileSystemEventHandler):

    def on_created(self, event):
        transfer_audio_to_cloud(event)

    def on_moved(self, event):
        transfer_audio_to_cloud(event)


if __name__ in '__main__':
    event_handler = ChangeHandler()
    observer = Observer()
    observer.schedule(event_handler, base_dir, recursive=True)
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
