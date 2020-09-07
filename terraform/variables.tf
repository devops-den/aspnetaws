variable "region" {
  default = "us-east-2"
}

variable "s3_bucket_region" {
  default = "us-east-2"
}

variable "s3_bucket_name" {
  default = "test-bucket"
}

variable "s3_artifact_name" {
  default = "s3testapp.zip"
}

variable "image_id" {
  default = "ami-0239d3998515e9ed1"
}
variable "lc_instance_type" {
  default = "t2.medium"
}
variable "aws_autoscaling_group_name" {
  default = "terraform-asg-test-app"
}