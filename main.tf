variable "DEV_SCM_CONSTANT_ARN" {
  default = "arn:aws:secretsmanager:ap-southeast-1:087112488386:secret:dev-infrastructure-constant-91TPFe"
}

variable "PROD_SCM_CONSTANT_ARN" {
  default = "arn:aws:secretsmanager:ap-southeast-1:800823848420:secret:prod-infrastructure-constant-FEt8TM"
}


variable "ENV" {
  description = "Environment"
}
data "aws_secretsmanager_secret" "secrets" {
  arn = var.ENV == "dev" ? var.DEV_SCM_CONSTANT_ARN : var.PROD_SCM_CONSTANT_ARN
}

data "aws_secretsmanager_secret_version" "current" {
  secret_id = data.aws_secretsmanager_secret.secrets.id
}


variable "LAMBDA_LAYERS" {
  description = "List params of lambda layers"
}

variable "FEATURE_NAME" {
  description = "Feature name"
}
variable "TAGS" {
  description = "List tags"
}
locals {
  root_path = format("%s/../../..", path.root)
}

locals {
  constants = jsondecode(data.aws_secretsmanager_secret_version.current.secret_string)
  s3_bucket = local.constants["CODEPIPELINE_BUCKET"]
}
data "external" "layer_zip" {
  for_each = var.LAMBDA_LAYERS
  program = [
    "bash", "-c",
    format("%s/%s %s/%s %s/%s",
      local.root_path, "scripts/zip.sh",
      local.root_path, "deploy/${each.key}_layer.zip",
      local.root_path, each.value.path
    ),
  ]
}

## TODO: Temporary disable cause by codebuild upload error
resource "aws_s3_object" "layer_object" {
  for_each    = var.LAMBDA_LAYERS
  bucket      = local.s3_bucket
  key         = "execution/${var.ENV}-${var.FEATURE_NAME}-${each.key}-layer"
  source      = data.external.layer_zip[each.key].result.path
  source_hash = data.external.layer_zip[each.key].result.hash
}

resource "aws_lambda_layer_version" "layer" {
  for_each   = var.LAMBDA_LAYERS
  layer_name = "${var.ENV}-${var.FEATURE_NAME}-${each.key}-layer"
  # filename   = data.external.layer_zip[each.key].result.path

  ## TODO: Temporary disable cause by codebuild upload error
  s3_bucket        = local.s3_bucket
  s3_key           = aws_s3_object.layer_object[each.key].id
  source_code_hash = data.external.layer_zip[each.key].result.hash

  compatible_runtimes      = ["nodejs18.x"]
  compatible_architectures = ["arm64"]
}

output "lambda_layer_arns" {
  value = { for key, value in var.LAMBDA_LAYERS : key => aws_lambda_layer_version.layer[key].arn }
}
