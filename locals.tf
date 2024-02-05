locals {
  spec              = yamldecode(file(var.spec_file))
  bench_id          = local.spec.id
  prefix            = local.bench_id
  route53_zone_name = replace("${local.prefix}.emqx.io", "/", "-")
  ssh_key_name      = local.prefix
  ssh_key_path      = pathexpand(format("~/.ssh/%s.pem", replace(local.ssh_key_name, "/", "-")))

  default_region             = try(local.spec.region, "eu-west-1")
  default_instance_type      = try(local.spec.instance_type, "t3.large")
  default_os_name            = try(local.spec.os_name, "ubuntu-jammy")
  default_os_version         = try(local.spec.os_version, "22.04")
  default_cpu_arch           = try(local.spec.cpu_arch, "amd64")
  default_use_spot_instances = try(local.spec.use_spot_instances, true)

  # collect all regions from spec
  regions = distinct(concat(
    [local.default_region],
    [for node in try(local.spec.emqx.nodes, []) : try(node.region, local.default_region)],
    [for node in try(local.spec.emqttb.nodes, []) : try(node.region, local.default_region)],
    [for node in try(local.spec.emqtt_bench.nodes, []) : try(node.region, local.default_region)],
    [for node in try(local.spec.locust.nodes, []) : try(node.region, local.default_region)],
    [for node in try(local.spec.http.nodes, []) : try(node.region, local.default_region)]
  ))

  regions_no_default            = tolist(setsubtract(local.regions, [local.default_region]))
  regions_no_default_no_region2 = tolist(setsubtract(local.regions_no_default, [local.region2]))
  region2                       = length(local.regions_no_default) > 0 ? local.regions_no_default[0] : "region2-stub"
  region3                       = length(local.regions_no_default_no_region2) > 0 ? local.regions_no_default_no_region2[0] : "region3-stub"

  region_aliases = {
    (local.default_region) = "default"
    (local.region2)        = "region2"
    (local.region3)        = "region3"
  }

  # emqx
  emqx_region                     = try(local.spec.emqx.region, local.default_region)
  emqx_os_name                    = try(local.spec.emqx.os_name, local.default_os_name)
  emqx_os_version                 = try(local.spec.emqx.os_version, local.default_os_version)
  emqx_cpu_arch                   = try(local.spec.emqx.cpu_arch, local.default_cpu_arch)
  emqx_ami_filter                 = try(local.spec.emqx.ami_filter, "*/${local.emqx_os_name}-${local.emqx_os_version}-${local.emqx_cpu_arch}-server-*")
  emqx_root_volume_size           = try(local.spec.emqx.root_volume_size, 20)
  emqx_version_family             = try(local.spec.emqx.version_family, 5) # 5 or 4
  emqx_http_api_port              = local.emqx_version_family == 4 ? 8081 : 18083
  emqx_api_version                = local.emqx_version_family == 4 ? "v4" : "v5"
  emqx_instance_type              = try(local.spec.emqx.instance_type, local.default_instance_type)
  emqx_use_spot_instances         = try(local.spec.emqx.use_spot_instances, local.default_use_spot_instances)
  emqx_dashboard_default_password = try(local.spec.emqx.dashboard_default_password, "public")
  emqx_extra_volumes              = try(local.spec.emqx.extra_volumes, [])
  emqx_instance_volumes           = try(local.spec.emqx.instance_volumes, [])
  cluster_dns_name                = "emqx-cluster.${local.route53_zone_name}"

  # group by region
  emqx_nodes_by_region = {
    for r in local.regions :
    r => flatten([
      for node in try(local.spec.emqx.nodes, []) : try(node.region, local.emqx_region) == r ?
      [for i in range(0, try(node.instance_count, 1)) : node]
      : []
    ])
  }
  # all nodes as flat list
  emqx_nodes_list = flatten([
    for r, nodes in local.emqx_nodes_by_region : [
      for i, n in nodes : {
        instance_type    = try(n.instance_type, local.emqx_instance_type)
        role             = try(n.role, "core")
        region           = r
        name             = "emqx-${lookup(var.regions_abbrev_map, r)}-${i + 1}",
        hostname         = "emqx-${lookup(var.regions_abbrev_map, r)}-${i + 1}.${local.route53_zone_name}",
        ami_filter       = try(n.ami_filter, local.emqx_ami_filter)
        extra_volumes    = try(n.extra_volumes, local.emqx_extra_volumes)
        instance_volumes = try(n.instance_volumes, local.emqx_instance_volumes)
      }
  ]])
  emqx_nodes        = { for node in local.emqx_nodes_list : node.hostname => node }
  emqx_static_seeds = [for node in local.emqx_nodes : "emqx@${node.hostname}" if node.role == "core"]

  # emqttb
  emqttb_region             = try(local.spec.emqttb.region, local.default_region)
  emqttb_os_name            = try(local.spec.emqttb.os_name, local.default_os_name)
  emqttb_os_version         = try(local.spec.emqttb.os_version, local.default_os_version)
  emqttb_cpu_arch           = try(local.spec.emqttb.cpu_arch, local.default_cpu_arch)
  emqttb_ami_filter         = try(local.spec.emqttb.ami_filter, "*/${local.emqttb_os_name}-${local.emqttb_os_version}-${local.emqttb_cpu_arch}-server-*")
  emqttb_instance_type      = try(local.spec.emqttb.instance_type, local.default_instance_type)
  emqttb_use_spot_instances = try(local.spec.emqttb.use_spot_instances, local.default_use_spot_instances)
  emqttb_scenario           = try(local.spec.emqttb.scenario, "@pub --topic t/%%n --conninterval 100ms --pubinterval 1s --num-clients 100 --size 1kb @sub --topic t/%%n --conninterval 100ms --num-clients 100")
  # group by region
  emqttb_nodes_by_region = {
    for r in local.regions :
    r => flatten([
      for node in try(local.spec.emqttb.nodes, []) : try(node.region, local.emqttb_region) == r ?
      [for i in range(0, try(node.instance_count, 1)) : node]
      : []
    ])
  }
  # all nodes as flat list
  emqttb_nodes_list = flatten([
    for r, nodes in local.emqttb_nodes_by_region : [
      for i, n in nodes : {
        instance_type  = try(n.instance_type, local.emqttb_instance_type)
        region         = r
        name           = "emqttb-${lookup(var.regions_abbrev_map, r)}-${i + 1}",
        hostname       = "emqttb-${lookup(var.regions_abbrev_map, r)}-${i + 1}.${local.route53_zone_name}",
        ami_filter     = try(n.ami_filter, local.emqttb_ami_filter)
        scenario       = try(n.scenario, local.emqttb_scenario)
        ip_alias_count = try(n.ip_alias_count, 0)
      }
  ]])
  emqttb_nodes = { for node in local.emqttb_nodes_list : node.hostname => node }

  # emqtt_bench
  emqtt_bench_region             = try(local.spec.emqtt_bench.region, local.default_region)
  emqtt_bench_os_name            = try(local.spec.emqtt_bench.os_name, local.default_os_name)
  emqtt_bench_os_version         = try(local.spec.emqtt_bench.os_version, local.default_os_version)
  emqtt_bench_cpu_arch           = try(local.spec.emqtt_bench.cpu_arch, local.default_cpu_arch)
  emqtt_bench_ami_filter         = try(local.spec.emqtt_bench.ami_filter, "*/${local.emqtt_bench_os_name}-${local.emqtt_bench_os_version}-${local.emqtt_bench_cpu_arch}-server-*")
  emqtt_bench_instance_type      = try(local.spec.emqtt_bench.instance_type, local.default_instance_type)
  emqtt_bench_use_spot_instances = try(local.spec.emqtt_bench.use_spot_instances, local.default_use_spot_instances)
  emqtt_bench_scenario           = try(local.spec.emqtt_bench.scenario, "pub -c 100 -I 10 -t bench/%%i -s 256")
  emqtt_bench_payload_template   = try(local.spec.emqtt_bench.emqtt_bench_payload_template, "")
  # group by region
  emqtt_bench_nodes_by_region = {
    for r in local.regions :
    r => flatten([
      for node in try(local.spec.emqtt_bench.nodes, []) : try(node.region, local.emqtt_bench_region) == r ?
      [for i in range(0, try(node.instance_count, 1)) : node]
      : []
    ])
  }
  # all nodes as flat list
  emqtt_bench_nodes_list = flatten([
    for r, nodes in local.emqtt_bench_nodes_by_region : [
      for i, n in nodes : {
        instance_type    = try(n.instance_type, local.emqtt_bench_instance_type)
        region           = r
        name             = "emqtt-bench-${lookup(var.regions_abbrev_map, r)}-${i + 1}",
        hostname         = "emqtt-bench-${lookup(var.regions_abbrev_map, r)}-${i + 1}.${local.route53_zone_name}",
        ami_filter       = try(n.ami_filter, local.emqtt_bench_ami_filter)
        scenario         = try(n.scenario, local.emqtt_bench_scenario)
        ip_alias_count   = try(n.ip_alias_count, 0)
        payload_template = try(n.payload_template, local.emqtt_bench_payload_template)
      }
  ]])
  emqtt_bench_nodes = { for node in local.emqtt_bench_nodes_list : node.hostname => node }

  # locust
  locust_region             = try(local.spec.locust.region, local.default_region)
  locust_os_name            = try(local.spec.locust.os_name, local.default_os_name)
  locust_os_version         = try(local.spec.locust.os_version, local.default_os_version)
  locust_cpu_arch           = try(local.spec.locust.cpu_arch, local.default_cpu_arch)
  locust_ami_filter         = try(local.spec.locust.ami_filter, "*/${local.locust_os_name}-${local.locust_os_version}-${local.locust_cpu_arch}-server-*")
  locust_instance_type      = try(local.spec.locust.instance_type, local.default_instance_type)
  locust_use_spot_instances = try(local.spec.locust.use_spot_instances, local.default_use_spot_instances)
  locust_plan_entrypoint    = try(local.spec.locust.plan_entrypoint, "locustfile.py")
  # group by region
  locust_nodes_by_region = {
    for r in local.regions :
    r => flatten([
      for node in try(local.spec.locust.nodes, []) : try(node.region, local.locust_region) == r ?
      [for i in range(0, try(node.instance_count, 1)) : node]
      : []
    ])
  }
  # all nodes as flat list
  locust_nodes_list = flatten([
    for r, nodes in local.locust_nodes_by_region : [
      for i, n in nodes : {
        instance_type   = try(n.instance_type, local.locust_instance_type)
        region          = r
        name            = "locust-${lookup(var.regions_abbrev_map, r)}-${i + 1}",
        hostname        = "locust-${lookup(var.regions_abbrev_map, r)}-${i + 1}.${local.route53_zone_name}",
        ami_filter      = try(n.ami_filter, local.locust_ami_filter)
        role            = try(n.role, "leader")
        plan_entrypoint = try(n.plan_entrypoint, local.locust_plan_entrypoint)
      }
  ]])
  locust_nodes = { for node in local.locust_nodes_list : node.hostname => node }

  # http server integration
  http_region             = try(local.spec.http.region, local.default_region)
  http_os_name            = try(local.spec.http.os_name, local.default_os_name)
  http_os_version         = try(local.spec.http.os_version, local.default_os_version)
  http_cpu_arch           = try(local.spec.http.cpu_arch, local.default_cpu_arch)
  http_ami_filter         = try(local.spec.http.ami_filter, "*/${local.http_os_name}-${local.http_os_version}-${local.http_cpu_arch}-server-*")
  http_instance_type      = try(local.spec.http.instance_type, local.default_instance_type)
  http_use_spot_instances = try(local.spec.http.use_spot_instances, local.default_use_spot_instances)
  # group by region
  http_nodes_by_region = {
    for r in local.regions :
    r => flatten([
      for node in try(local.spec.http.nodes, []) : try(node.region, local.http_region) == r ?
      [for i in range(0, try(node.instance_count, 1)) : node]
      : []
    ])
  }
  # all nodes as flat list
  http_nodes_list = flatten([
    for r, nodes in local.http_nodes_by_region : [
      for i, n in nodes : {
        instance_type = try(n.instance_type, local.http_instance_type)
        region        = r
        name          = "http-${lookup(var.regions_abbrev_map, r)}-${i + 1}",
        hostname      = "http-${lookup(var.regions_abbrev_map, r)}-${i + 1}.${local.route53_zone_name}",
        ami_filter    = try(n.ami_filter, local.http_ami_filter)
      }
  ]])
  http_nodes = { for node in local.http_nodes_list : node.hostname => node }

  # monitoring
  monitoring_os_name            = try(local.spec.monitoring.os_name, local.default_os_name)
  monitoring_os_version         = try(local.spec.monitoring.os_version, local.default_os_version)
  monitoring_cpu_arch           = try(local.spec.monitoring.cpu_arch, local.default_cpu_arch)
  monitoring_ami_filter         = try(local.spec.monitoring.ami_filter, "*/${local.monitoring_os_name}-${local.monitoring_os_version}-${local.monitoring_cpu_arch}-server-*")
  monitoring_instance_type      = try(local.spec.monitoring.instance_type, local.default_instance_type)
  monitoring_use_spot_instances = try(local.spec.monitoring.use_spot_instances, local.default_use_spot_instances)
  monitoring_root_volume_size   = try(local.spec.monitoring.root_volume_size, 20)
  monitoring_hostname           = "monitoring.${local.route53_zone_name}"
}

check "max_regions" {
  assert {
    condition     = length(local.regions) <= 3
    error_message = "Max number of different regions is 3. Found: ${length(local.regions)}"
  }
}
