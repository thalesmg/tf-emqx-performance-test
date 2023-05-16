variable "namespace" {
  description = "namespace"
  type        = string
}

variable "ami_filter" {
  description = "AMI filter"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 Bucket"
  type        = string
}

variable "bench_id" {
  description = "Benchmark ID"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
  default     = "c5.large"
}

variable "instance_count" {
  description = "Instance count"
  type        = number
  default     = 1
}

variable "package_url" {
  description = "Package URL"
  type        = string
}

variable "sg_ids" {
  description = "Security Group IDs"
  type        = list(string)
}

variable "emqx_hosts" {
  description = "EMQX Hosts"
  type        = list(string)
}

variable "iam_profile" {
  description = "IAM Instance Profile"
  type        = string
}

variable "route53_zone_name" {
  description = "Route53 Zone Name"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 Zone ID"
  type        = string
}

variable "grafana_url" {
  description = "Grafana URL"
  type        = string
}

variable "grafana_api_key" {
  description = "Grafana API KEY"
  type        = string
  sensitive   = true
}

variable "test_duration" {
  description = "Performance test duration"
  type        = string
}

variable "scenario" {
  description = "emqttb scenario"
  type        = string
}

variable "key_name" {
  description = "SSH Key Name"
  type        = string
}

variable "prometheus_push_gw" {
  description = "Prometheus push gateway endpoint"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}
