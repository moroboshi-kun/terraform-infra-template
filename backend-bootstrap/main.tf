# ============================================================================
# backend-bootstrap/main.tf
# ============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  bucket_name      = "${var.project}-${var.env}-tfstate"
  logs_bucket_name = "${var.project}-${var.env}-tfstate-logs"
  table_name       = "${var.project}-${var.env}-tf-locks"
}

# ---------------------------------------------------------------------------
# KMS keys
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_default" {
  #checkov:skip=CKV_AWS_109:KMS key policy intentionally grants root full key management
  #checkov:skip=CKV_AWS_111:KMS key policy intentionally allows broad write for root
  #checkov:skip=CKV_AWS_356:KMS key policy uses * resource as per AWS default key policy
  statement {
    sid    = "EnableAccountRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }
}
resource "aws_kms_key" "s3_state" {
  description         = "KMS CMK for Terraform state bucket"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_default.json
}

resource "aws_kms_key" "dynamodb_locks" {
  description         = "KMS CMK for Terraform state lock table"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_default.json
}

# ---------------------------------------------------------------------------
# S3 bucket for Terraform state
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  # checkov:skip=CKV2_AWS_62:State bucket does not require S3 event notifications
  # checkov:skip=CKV_AWS_144:Cross-region replication is not required for state bucket
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    # Enforces bucket owner ownership and effectively disables ACLs
    object_ownership = "BucketOwnerEnforced"
  }
}

# Lifecycle for old versions / multipart uploads
resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Log bucket for access logging
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state_logs" {
  # checkov:skip=CKV2_AWS_62:Log bucket does not require S3 event notifications
  # checkov:skip=CKV_AWS_144:Cross-region replication not required for log bucket
  bucket = local.logs_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state_logs" {
  bucket = aws_s3_bucket.tf_state_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_logs" {
  bucket = aws_s3_bucket.tf_state_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state_logs" {
  bucket = aws_s3_bucket.tf_state_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tf_state_logs" {
  bucket = aws_s3_bucket.tf_state_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tf_state_logs" {
  bucket = aws_s3_bucket.tf_state_logs.id

  rule {
    id     = "cleanup-old-logs"
    status = "Enabled"

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Enable access logging on the state bucket
resource "aws_s3_bucket_logging" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  target_bucket = aws_s3_bucket.tf_state_logs.id
  target_prefix = "access-logs/"
}

# ---------------------------------------------------------------------------
# DynamoDB table for state locking
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "tf_lock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # KMS CMK encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_locks.arn
  }

  # Point-in-time recovery (PITR)
  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

