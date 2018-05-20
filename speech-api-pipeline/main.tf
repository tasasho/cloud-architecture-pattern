provider "aws" {
  region = "ap-northeast-1"
}

provider "google" {
  region      = "asia-northeast1"
  alias       = "tokyo"
}

data "aws_caller_identity" "self" { }

data "aws_iam_policy_document" "policy_document_for_ets" {
  statement {
    actions = [
      "s3:Put*",
      "s3:ListBucket",
      "s3:*MultipartUpload*",
      "s3:Get*"
    ]

    effect    = "Allow"
    resources = ["arn:aws:s3:::*"]
  }

  statement {
    actions = [
      "sns:Publish"
    ]

    effect    = "Allow"
    resources = ["arn:aws:sns:ap-northeast-1:${data.aws_caller_identity.self.account_id}:*"]
  } 
}

data "aws_iam_policy_document" "policy_document_for_lambda01" {
  statement {
    actions = [
      "s3:Put*",
      "s3:ListBucket",
      "s3:*MultipartUpload*",
      "s3:Get*"
    ]

    effect    = "Allow"
    resources = ["arn:aws:s3:::*"]
  }

  statement {
    actions = [
      "sns:Publish"
    ]

    effect    = "Allow"
    resources = ["arn:aws:sns:ap-northeast-1:${data.aws_caller_identity.self.account_id}:*"]
  } 
}

data "aws_iam_policy_document" "ets_role_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["elastictranscoder.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda01_role_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda02_role_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Local Values for AWS Managed IAM Policies
locals {
  ets_submmit_jobs = "arn:aws:iam::aws:policy/AmazonElasticTranscoderJobsSubmitter"
  s3_read_only = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  cloudwatch_write_logs = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# etc
locals {
  usage_tag = "convert-pipeline-for-gcp-speech-api"
  project_folder = "${pathexpand("~/projects/terraform/speech-api-pipeline")}"
}

resource "aws_s3_bucket" "raw_audio_bucket" {
  bucket = "raw-audio-${data.aws_caller_identity.self.account_id}"
  acl    = "private"

  lifecycle_rule {
    id      = "lifecycle-raw-audio-${data.aws_caller_identity.self.account_id}"
    enabled = true

    expiration {
      days = 3
    }
  }

  tags {
    Name = "raw-audio-${data.aws_caller_identity.self.account_id}"
    Usage = "${local.usage_tag}"
  }
}

resource "aws_s3_bucket" "processed_audio_bucket" {
  bucket = "processed-audio-${data.aws_caller_identity.self.account_id}"
  acl    = "private"

  lifecycle_rule {
    id      = "lifecycle-processed-audio-${data.aws_caller_identity.self.account_id}"
    enabled = true

    expiration {
      days = 3
    }
  }

  tags {
    Name = "processed-audio-${data.aws_caller_identity.self.account_id}"
    Usage = "${local.usage_tag}"
  }
}

resource "aws_s3_bucket" "thumbnail_bucket" {
  bucket = "thumbnail-${data.aws_caller_identity.self.account_id}"
  acl    = "private"

  lifecycle_rule {
    id      = "lifecycle-thumbnail-${data.aws_caller_identity.self.account_id}"
    enabled = true

    expiration {
      days = 3
    }
  }

  tags {
    Name = "thumbnail-${data.aws_caller_identity.self.account_id}"
    Usage = "${local.usage_tag}"
  }
}

resource "aws_iam_policy" "ets-default-policy" {
  name   = "ets-default-policy"
  policy = "${data.aws_iam_policy_document.policy_document_for_ets.json}"
}

resource "aws_iam_role" "ets-default-role" {
  name               = "ets-default-role"
  assume_role_policy = "${data.aws_iam_policy_document.ets_role_assume_role_policy.json}"
}

resource "aws_iam_role_policy_attachment" "ets-role-attach" {
    role       = "${aws_iam_role.ets-default-role.name}"
    policy_arn = "${aws_iam_policy.ets-default-policy.arn}"
}

resource "aws_elastictranscoder_pipeline" "convert-to-flac-pipeline" {
  input_bucket = "${aws_s3_bucket.raw_audio_bucket.bucket}"
  name         = "convert-to-flac-pipeline"
  role         = "${aws_iam_role.ets-default-role.arn}"

  content_config = {
    bucket        = "${aws_s3_bucket.processed_audio_bucket.bucket}"
    storage_class = "Standard"
  }

  thumbnail_config = {
    bucket        = "${aws_s3_bucket.thumbnail_bucket.bucket}"
    storage_class = "Standard"
  }
}

resource "aws_elastictranscoder_preset" "monoral-flac-set" {
  container   = "flac"
  description = "Monoral Flac Preset for GCP Cloud Speech API"
  name        = "monoral-flac-set"

  audio = {
    channels           = 1
    codec              = "flac"
    sample_rate        = 44100
  }

  audio_codec_options = {
    bit_depth = 16
  }
}

# for IAM resources for lambda01
resource "aws_iam_role" "lambda01-role" {
  name               = "lambda-create-ets-job"
  assume_role_policy = "${data.aws_iam_policy_document.lambda01_role_assume_role_policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda01-role-attach01" {
    role       = "${aws_iam_role.lambda01-role.name}"
    policy_arn = "${local.s3_read_only}"
}

resource "aws_iam_role_policy_attachment" "lambda01-role-attach02" {
    role       = "${aws_iam_role.lambda01-role.name}"
    policy_arn = "${local.cloudwatch_write_logs}"
}

resource "aws_iam_role_policy_attachment" "lambda01-role-attach03" {
    role       = "${aws_iam_role.lambda01-role.name}"
    policy_arn = "${local.ets_submmit_jobs}"
}

resource "aws_lambda_function" "lambda01" {
  filename         = "${local.project_folder}/convert-audio-to-monoral-flac.zip"
  function_name    = "convert-audio-to-monoral-flac"
  role             = "${aws_iam_role.lambda01-role.arn}"
  handler          = "convert-audio-to-monoral-flac.lambda_handler"
  source_code_hash = "${base64sha256(file("${local.project_folder}/convert-audio-to-monoral-flac.zip"))}"
  runtime          = "python3.6"
  memory_size      = 128
  timeout          = 30
  description      = "Submmiting ets job to convert audio to monoral-flac"

  environment {
    variables = {
      PIPELINE_ID = "${aws_elastictranscoder_pipeline.convert-to-flac-pipeline.id}"
      PRESET_ID = "${aws_elastictranscoder_preset.monoral-flac-set.id}"
    }
  }

  tags {
    Name = "convert-audio-to-monoral-flac"
    Usage = "${local.usage_tag}"
  }
}

resource "aws_lambda_permission" "lambda01_permission" {
  statement_id  = "AllowExecutionFromRawAudioBucket"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda01.arn}"
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.raw_audio_bucket.arn}"
}

resource "aws_s3_bucket_notification" "lambda01_notification" {
  bucket = "${aws_s3_bucket.raw_audio_bucket.id}"

  lambda_function {
    lambda_function_arn = "${aws_lambda_function.lambda01.arn}"
    events              = ["s3:ObjectCreated:*"]
  }
}

# for IAM resources for lambda02
resource "aws_iam_role" "lambda02-role" {
  name               = "lambda-forward-s3audio-to-gcs"
  assume_role_policy = "${data.aws_iam_policy_document.lambda02_role_assume_role_policy.json}"
}

resource "aws_iam_role_policy_attachment" "lambda02-role-attach01" {
    role       = "${aws_iam_role.lambda02-role.name}"
    policy_arn = "${local.s3_read_only}"
}

resource "aws_iam_role_policy_attachment" "lambda02-role-attach02" {
    role       = "${aws_iam_role.lambda02-role.name}"
    policy_arn = "${local.cloudwatch_write_logs}"
}

# change memory_size and timeout as necessary.
resource "aws_lambda_function" "lambda02" {
  filename         = "${local.project_folder}/transfer-s3flac-to-gcs.zip"
  function_name    = "transfer-s3flac-to-gcs"
  role             = "${aws_iam_role.lambda02-role.arn}"
  handler          = "transfer-s3flac-to-gcs.lambda_handler"
  source_code_hash = "${base64sha256(file("${local.project_folder}/convert-audio-to-monoral-flac.zip"))}"
  runtime          = "python3.6"
  memory_size      = 384
  timeout          = 180
  description      = "Transfering processed flac file of s3 to gcs"

  environment {
    variables = {
      GOOGLE_APPLICATION_CREDENTIALS = "gcp-develop-key.json"
      GCS_BUCKET_NAME = "${google_storage_bucket.flac_bucket.name}"
    }
  }

  tags {
    Name = "transfer-s3flac-to-gcs"
    Usage = "${local.usage_tag}"
  }
}

resource "aws_lambda_permission" "lambda02_permission" {
  statement_id  = "AllowExecutionFromProcessedAudioBucket"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda02.arn}"
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.processed_audio_bucket.arn}"
}

resource "aws_s3_bucket_notification" "lambda02_notification" {
  bucket = "${aws_s3_bucket.processed_audio_bucket.id}"

  lambda_function {
    lambda_function_arn = "${aws_lambda_function.lambda02.arn}"
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".flac"
  }
}

resource "google_storage_bucket" "flac_bucket" {
  name          = "flac-files-${data.aws_caller_identity.self.account_id}"
  storage_class = "REGIONAL"
  location      = "asia-northeast1"

  labels {
    name = "flac-files-${data.aws_caller_identity.self.account_id}"
    usage = "${local.usage_tag}"
  }
}

resource "google_storage_bucket" "translated_text_bucket" {
  name          = "traslated-texts-${data.aws_caller_identity.self.account_id}"
  storage_class = "REGIONAL"
  location      = "asia-northeast1"

  labels {
    name = "traslated-texts-${data.aws_caller_identity.self.account_id}"
    usage = "${local.usage_tag}"
  }
}

resource "google_storage_bucket" "function_sources_bucket" {
  name          = "function-sources-${data.aws_caller_identity.self.account_id}"
  storage_class = "REGIONAL"
  location      = "us-central1"

  labels {
    name = "function-sources-${data.aws_caller_identity.self.account_id}"
    usage = "${local.usage_tag}"
  }
}

resource "google_storage_bucket_object" "function_source" {
  name   = "index.zip"
  bucket = "${google_storage_bucket.function_sources_bucket.name}"
  source = "${local.project_folder}/transcribe-flac-to-text.zip"
}

resource "google_cloudfunctions_function" "cloud_functions01" {
  name                  = "transcribe-flac-to-text"
  entry_point           = "processFile"
  description           = "Transfering flac file to speech api to transcribe, and saving text file based on the result."
  available_memory_mb   = 256
  source_archive_bucket = "${google_storage_bucket.function_sources_bucket.name}"
  source_archive_object = "${google_storage_bucket_object.function_source.name}"
  trigger_bucket        = "${google_storage_bucket.flac_bucket.name}"
  timeout               = 180
  region                = "us-central1"

  labels {
    name = "transcribe-flac-to-text"
    usage = "${local.usage_tag}"
  }
}


