
data "archive_file" "tools" {
  type        = "zip"
  source_dir  = "${path.module}/../../../tools/"
  output_path = "${path.module}/../../../build/terraform/tools.zip"
}

data "archive_file" "layer" {
  type        = "zip"
  source_dir  = "${path.module}/../../../build/terraform/tools-layer/"
  output_path = "${path.module}/../../../build/terraform/tools-layer.zip"
  depends_on  = [null_resource.pip_install]
}

resource "null_resource" "pip_install" {


  provisioner "local-exec" {
    command = "python -m pip install --platform manylinux2014_x86_64 --only-binary=:all: -r ${path.module}/../../../tools/requirements.txt -t ${path.module}/../../../build/terraform/tools-layer/python"
  }
}

resource "aws_iam_role_policy_attachment" "exporter_vpc_attachment" {
  role       = aws_iam_role.exporter_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_layer_version" "layer" {
  layer_name          = "vaultwarden-exporter-dependencies"
  filename            = data.archive_file.layer.output_path
  source_code_hash    = data.archive_file.layer.output_base64sha256
  compatible_runtimes = ["python3.10"]
}

resource "aws_s3_bucket" "exportbucket" {
  bucket_prefix = "vaultwarden-exporter"
}

resource "aws_s3_bucket_cors_configuration" "exportbucketconfig" {
  bucket = aws_s3_bucket.exportbucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["POST"]
    allowed_origins = ["https://${var.gateway_domain}"]
    max_age_seconds = 3600
  }
}

resource "aws_iam_role" "exporter_role" {
  name_prefix        = "vaultwarden-exporter-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_policy" "s3_policy" {
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        Action : [
          "s3:*",
        ],
        Effect : "Allow",
        Resource : [
          aws_s3_bucket.exportbucket.arn,
          "${aws_s3_bucket.exportbucket.arn}/*"
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_policy_attachment" {
  role       = aws_iam_role.exporter_role.id
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "function_logging_policy_attachment_2" {
  role       = aws_iam_role.exporter_role.id
  policy_arn = aws_iam_policy.function_logging_policy.arn
}

resource "aws_lambda_function" "exporter" {
  function_name    = "vaultwarden-serverless-tools"
  filename         = data.archive_file.tools.output_path
  source_code_hash = data.archive_file.tools.output_base64sha256
  role             = aws_iam_role.exporter_role.arn
  runtime          = "python3.10"
  handler          = "tools.handler"
  memory_size      = 256
  timeout          = 30
  layers           = [aws_lambda_layer_version.layer.arn]
  file_system_config {
    arn              = aws_efs_access_point.ap.arn
    local_mount_path = local.mount_dir
  }
  depends_on = [
    aws_cloudwatch_log_group.function_log_group,
  ]
  vpc_config {
    subnet_ids         = [aws_subnet.public.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  environment {
    variables = {
      ADMIN_TOKEN = var.vaultwarden_admin_hash
      BUCKET_NAME = aws_s3_bucket.exportbucket.id
    }
  }
}