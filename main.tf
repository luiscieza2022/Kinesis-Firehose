terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
provider "aws" { region = "us-east-2" }
resource "random_id" "suffix" { byte_length = 4 }
resource "aws_kinesis_stream" "source" {
  name = "grupo-kinesis-stream"
  shard_count = 1
  retention_period = 24
}
resource "aws_s3_bucket" "destination" {
  bucket = "kinesis-firehose-lab-${random_id.suffix.hex}"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.destination.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
resource "aws_iam_role" "firehose" {
  name = "grupo-firehose-delivery-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{Effect = "Allow", Principal = {Service = "firehose.amazonaws.com"}, Action = "sts:AssumeRole"}]
  })
}
resource "aws_iam_role_policy" "firehose" {
  name = "grupo-firehose-policy"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {Effect = "Allow", Action = ["kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:ListShards"], Resource = aws_kinesis_stream.source.arn},
      {Effect = "Allow", Action = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject"], Resource = [aws_s3_bucket.destination.arn, "${aws_s3_bucket.destination.arn}/*"]}
    ]
  })
}
resource "aws_kinesis_firehose_delivery_stream" "delivery" {
  name = "grupo-kinesis-firehose"
  destination = "extended_s3"
  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.source.arn
    role_arn = aws_iam_role.firehose.arn
  }
  extended_s3_configuration {
    role_arn = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.destination.arn
    prefix = "kinesis/"
    buffering_size = 1
    buffering_interval = 60
    compression_format = "GZIP"
  }
  depends_on = [aws_iam_role_policy.firehose, aws_s3_bucket_public_access_block.block]
}
output "bucket_name" { value = aws_s3_bucket.destination.bucket }
output "kinesis_name" { value = aws_kinesis_stream.source.name }
output "firehose_name" { value = aws_kinesis_firehose_delivery_stream.delivery.name }
