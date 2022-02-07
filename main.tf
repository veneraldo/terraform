locals{
    sorted_az_list = sort(data.aws_availability_zones.available-zones.names)
}

data "aws_availability_zones" "available-zones" {
    state = "available"    
}

# provider configuration 
    provider "aws" { 
    region = var.REGION
}

# create vpc
resource "aws_vpc" "main" {
    cidr_block = var.VPC_CIDR_BLOCK
    enable_dns_hostnames = true
    enable_dns_support = true
    instance_tenancy = "default"
    tags = {
        Name = var.VPC_NAME
    }
}

# create internet gateway
resource "aws_internet_gateway" "internet-gateway" {
  vpc_id = aws_vpc.main.id
  tags = {
      Name = "internet-gateway"
  }
}

# create public subnets
resource "aws_subnet" "public-subnet" {
    vpc_id = aws_vpc.main.id
    count = length(var.PUBLIC_SUBNET_CIDR_BLOCK)
    cidr_block = var.PUBLIC_SUBNET_CIDR_BLOCK[count.index]
    availability_zone = local.sorted_az_list[count.index]
    map_public_ip_on_launch = true
    tags = {
        Name = "public-subnet-${element(local.sorted_az_list, count.index)}"
    }
}

# create private subnets
resource "aws_subnet" "private-subnet" {
    vpc_id = aws_vpc.main.id
    count = length(var.PRIVATE_SUBNET_CIDR_BLOCK)
    cidr_block = var.PRIVATE_SUBNET_CIDR_BLOCK[count.index]
    availability_zone = local.sorted_az_list[count.index]
    map_public_ip_on_launch = false
    tags = {
        Name = "private-subnet-${element(local.sorted_az_list, count.index)}"
    }
}

# create default route for public subnets
resource "aws_route_table" "public-route" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.internet-gateway.id
    }
}

# associate public subnets with the public default route
resource "aws_route_table_association" "public-subnets-assoc" {
    count = length(var.PUBLIC_SUBNET_CIDR_BLOCK)
    subnet_id = element(aws_subnet.public-subnet.*.id, count.index)
    route_table_id = aws_route_table.public-route.id
}

# create elastic IP for NAT gateway
resource "aws_eip" "nat-gw-eip" {
    vpc = true
    depends_on = [
      aws_internet_gateway.internet-gateway
    ]
  
}

# create NAT gateway
resource "aws_nat_gateway" "nat-gw" {
    allocation_id = aws_eip.nat-gw-eip.id
    subnet_id = element(aws_subnet.public-subnet.*.id, 0)
    depends_on = [
      aws_internet_gateway.internet-gateway
    ]    
}

# create private subnet route table
resource "aws_route_table" "private-route" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.nat-gw.id
    }    
}

# associate private subnets to private route table
resource "aws_route_table_association" "private-subnet-assoc" {
    count = length(var.PRIVATE_SUBNET_CIDR_BLOCK)
    subnet_id = element(aws_subnet.private-subnet.*.id, count.index)
    route_table_id = aws_route_table.private-route.id
  
}

# create rds subnet group
resource "aws_db_subnet_group" "rds-db-subnet-group" {
    name = "rds-db-subnet-group"
    subnet_ids = [element(aws_subnet.private-subnet.*.id, 0),element(aws_subnet.private-subnet.*.id,1)]
}

# create rds security group
resource "aws_security_group" "rds-mysql-sg" {
    name   = "rds-mysql-sg"
    vpc_id = aws_vpc.main.id
}

# create rds security group inbound rules
resource "aws_security_group_rule" "rds-mysql-sg-rule" {
    from_port  = 3306
    protocol   = "tcp"
    security_group_id = aws_security_group.rds-mysql-sg.id
    to_port  = 3306
    type  = "ingress"
    cidr_blocks = [var.VPC_CIDR_BLOCK]
}

# create rds security group outbound rules
resource "aws_security_group_rule" "rds-outbound-rule" {
    from_port = 0
    protocol  = "-1"
    security_group_id = aws_security_group.rds-mysql-sg.id
    to_port = 0
    type = "egress"
    cidr_blocks = ["0.0.0.0/0"]
}

# create rds-mysql database
resource "aws_db_instance" "rds-mysql" {
    instance_class = var.DB_INSTANCE
    engine = "mysql"
    engine_version = "8.0.17"
    multi_az = true
    storage_type  = "gp2"
    allocated_storage  = 8
    name = "rdsmysqlinstance"
    username = "admin"
    password = "admin123"
    apply_immediately = "true"
    db_subnet_group_name = "rds-db-subnet-group"
    vpc_security_group_ids  = ["${aws_security_group.rds-mysql-sg.id}"]
}

# create redis cluster
resource "aws_elasticache_cluster" "venerms-redis-cluster" {
    cluster_id  = "venerms-redis-cluster"
    engine  = "redis"
    node_type  = "cache.t3.micro"
    num_cache_nodes  = 1
    parameter_group_name = "default.redis5.0"
    engine_version  = "5.0.6"
    port = 6379
}


# create nginx proxy alb security group
resource "aws_security_group" "nginx-proxy-alb-sg" {
    name   = "nginx-proxy-alb-sg"
    vpc_id = aws_vpc.main.id
}

# create nginx proxy alb sg inbound rule for ssh
resource "aws_security_group_rule" "inbound-ssh" {
    from_port         = 22
    protocol          = "tcp"
    security_group_id = aws_security_group.nginx-proxy-alb-sg.id
    to_port           = 22
    type              = "ingress"
    cidr_blocks       = ["0.0.0.0/0"]
}

# create nginx proxy alb sg inbound rule for http
resource "aws_security_group_rule" "inbound-http" {
    from_port         = 80
    protocol          = "tcp"
    security_group_id = aws_security_group.nginx-proxy-alb-sg.id
    to_port           = 80
    type              = "ingress"
    cidr_blocks       = ["0.0.0.0/0"]
}

# create nginx proxy alb sg inbound rule for https
resource "aws_security_group_rule" "inbound-https" {
    from_port         = 443
    protocol          = "tcp"
    security_group_id = aws_security_group.nginx-proxy-alb-sg.id
    to_port           = 443
    type              = "ingress"
    cidr_blocks       = ["0.0.0.0/0"]
}

# create nginx proxy alb sg outbound rule for outbound
resource "aws_security_group_rule" "outbound-all" {
    from_port         = 0
    protocol          = "-1"
    security_group_id = aws_security_group.nginx-proxy-alb-sg.id
    to_port           = 0
    type              = "egress"
    cidr_blocks       = ["0.0.0.0/0"]
}

# create internet-facing nginx proxy alb
resource "aws_alb" "nginx-proxy-alb" {
    name = "nginx-proxy-alb"
    subnets = [
        element(aws_subnet.public-subnet.*.id, 0),
        element(aws_subnet.public-subnet.*.id, 1)
    ]
    security_groups = ["${aws_security_group.nginx-proxy-alb-sg.id}"]
    internal = "false"
    tags = {
        Name = "nginx-proxy-alb"
    }
}

# create target group for nginx server
resource "aws_alb_target_group" "nginx-server-alb-tg" {
    name     = "nginx-server-alb-tg"
    port     = "80"
    protocol = "HTTP"
    vpc_id   = aws_vpc.main.id
    tags = {
        name = "nginx-server-alb-tg"
    }
    health_check {
        healthy_threshold   = 3
        unhealthy_threshold = 10
        timeout             = 5
        interval            = 10
        path                = "/"
        port                = "80"
    }
}

# create target group for nodejs server
resource "aws_alb_target_group" "nodejs-server-alb-tg" {
    name     = "nodejs-server-alb-tg"
    port     = "80"
    protocol = "HTTP"
    vpc_id   = aws_vpc.main.id
    tags = {
        name = "nodejs-server-alb-tg"
    }
    health_check {
        healthy_threshold   = 3
        unhealthy_threshold = 10
        timeout             = 10
        interval            = 20
        path                = "/api" 
        port                = "80"
    }
}

# create nginx proxy alb listener
resource "aws_alb_listener" "nginx-proxy-alb-listener" {
    load_balancer_arn = aws_alb.nginx-proxy-alb.arn
    port              = "80"
    protocol          = "HTTP"

    default_action {
        target_group_arn = aws_alb_target_group.nginx-server-alb-tg.arn
        type  = "forward"
    }
}

/*
# create listener for https with certificate
resource "aws_alb_listener" "nginx-proxy-alb-listener-https" {
    load_balancer_arn = aws_alb.nginx-proxy-alb.arn
    port              = "443"
    protocol          = "HTTPS"
    certificate_arn   = "arn:aws:iam::123456789012:server-certificate/test_cert-123456789012"
    default_action {
        target_group_arn = aws_alb_target_group.nginx-server-alb-tg.arn
        type  = "forward"
    }
}
*/

# create nginx proxy listener rule
resource "aws_alb_listener_rule" "nginx-proxy-listener-rule" {
    depends_on   = [aws_alb_target_group.nodejs-server-alb-tg]
    listener_arn = aws_alb_listener.nginx-proxy-alb-listener.arn
    action {
        type   = "forward"
        target_group_arn = aws_alb_target_group.nodejs-server-alb-tg.id
    }
    condition {
        path_pattern {
        values = ["*api*"]
        }
    }
}


# create launch configuration for nginx web server
resource "aws_launch_configuration" "nginx-web-asg-launch-config" {
    image_id        = "ami-07f179dc333499419"
    instance_type   = "t3.micro"
    security_groups = ["${aws_security_group.nginx-proxy-alb-sg.id}"]
    user_data  = file("nginx-install.sh")
    lifecycle {
        create_before_destroy = true
    }
}

# create nginx server autoscaling group
resource "aws_autoscaling_group" "nginx-server-asg" {
    name                 = "nginx-server-asg"
    launch_configuration = aws_launch_configuration.nginx-web-asg-launch-config.name
    vpc_zone_identifier = [
        element(aws_subnet.private-subnet.*.id, 0),
        element(aws_subnet.private-subnet.*.id, 1)
    ]
    target_group_arns    = ["${aws_alb_target_group.nginx-server-alb-tg.arn}"]
    health_check_type    = "ELB"
    min_size         = 1
    max_size         = 3
    desired_capacity = 2

    tag {
        key                 = "Name"
        value               = "nginx-server-asg"
        propagate_at_launch = true
    }
}

# create launch configuration for nodejs web server
resource "aws_launch_configuration" "nodejs-web-asg-launch-config" {
    image_id        = "ami-055d15d9cfddf7bd3"
    instance_type   = "t3.micro"
    security_groups = ["${aws_security_group.nginx-proxy-alb-sg.id}"]
    user_data  = file("nodejs-install.sh")
    lifecycle {
        create_before_destroy = true
    }
}

# create nodejs server autoscaling group
resource "aws_autoscaling_group" "nodejs-server-asg" {
    name                 = "nodejs-server-asg"
    launch_configuration = aws_launch_configuration.nodejs-web-asg-launch-config.name
    vpc_zone_identifier = [
        element(aws_subnet.private-subnet.*.id, 0),
        element(aws_subnet.private-subnet.*.id, 1)
    ]
    target_group_arns    = ["${aws_alb_target_group.nodejs-server-alb-tg.arn}"]
    health_check_type    = "ELB"
    min_size         = 1
    max_size         = 3
    desired_capacity = 2
    tag {
        key                 = "Name"
        value               = "nodejs-server-asg"
        propagate_at_launch = true
    }
}

# create nginx server cpu scale up policy
resource "aws_autoscaling_policy" "nginx-server-cpu-scale-up-policy" {
    name                   = "nginx-server-cpu-scale-up-policy"
    autoscaling_group_name = "${aws_autoscaling_group.nginx-server-asg.name}"
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = "1"
    cooldown               = "300"
    policy_type            = "SimpleScaling"
}

# create nginx server cpu scale down policy
resource "aws_autoscaling_policy" "nginx-server-cpu-scale-down-policy" {
    name                   = "nginx-server-cpu-policy"
    autoscaling_group_name = "${aws_autoscaling_group.nginx-server-asg.name}"
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = "-1"
    cooldown               = "300"
    policy_type            = "SimpleScaling"
}

# create nginx server cloudwatch cpu scale-up alarm
resource "aws_cloudwatch_metric_alarm" "nginx-server-cpu-scale-up-alarm" {
    alarm_name          = "nginx-server-cpu-scale-up-alarm"
    alarm_description   = "nginx-server-cpu-scale-up-alarm"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = "2"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = "120"
    statistic           = "Average"
    threshold           = "30"
    dimensions = {
        "AutoScalingGroupName" = "${aws_autoscaling_group.nginx-server-asg.name}"
    }
    actions_enabled = true
    alarm_actions   = ["${aws_autoscaling_policy.nginx-server-cpu-scale-up-policy.arn}"]
}

# create nginx server cloudwatch cpu scale-down alarm
resource "aws_cloudwatch_metric_alarm" "nginx-server-cpu-scale-down-alarm" {
    alarm_name          = "nginx-server-cpu-scale-down-alarm"
    alarm_description   = "nginx-server-cpu-scale-down-alarm"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods  = "2"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = "120"
    statistic           = "Average"
    threshold           = "5"
    dimensions = {
        "AutoScalingGroupName" = "${aws_autoscaling_group.nginx-server-asg.name}"
    }
    actions_enabled = true
    alarm_actions   = ["${aws_autoscaling_policy.nginx-server-cpu-scale-down-policy.arn}"]
}

# create nodejs server cpu scale up policy
resource "aws_autoscaling_policy" "nodejs-server-cpu-scale-up-policy" {
    name                   = "nodejs-server-cpu-scale-up-policy"
    autoscaling_group_name = "${aws_autoscaling_group.nodejs-server-asg.name}"
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = "1"
    cooldown               = "300"
    policy_type            = "SimpleScaling"
}

# create nodejs cpu scale down policy
resource "aws_autoscaling_policy" "nodejs-server-cpu-scale-down-policy" {
    name                   = "nodejs-server-cpu-policy"
    autoscaling_group_name = "${aws_autoscaling_group.nodejs-server-asg.name}"
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = "-1"
    cooldown               = "300"
    policy_type            = "SimpleScaling"
}

# create nodejs cloudwatch cpu scale-up alarm
resource "aws_cloudwatch_metric_alarm" "nodejs-server-cpu-scale-up-alarm" {
    alarm_name          = "nodejs-server-cpu-scale-up-alarm"
    alarm_description   = "nodejs-server-cpu-scale-up-alarm"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = "2"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = "120"
    statistic           = "Average"
    threshold           = "30"
    dimensions = {
        "AutoScalingGroupName" = "${aws_autoscaling_group.nodejs-server-asg.name}"
    }
    actions_enabled = true
    alarm_actions   = ["${aws_autoscaling_policy.nodejs-server-cpu-scale-up-policy.arn}"]
}

# create nodejs server cloudwatch cpu scale-down alarm
resource "aws_cloudwatch_metric_alarm" "nodejs-server-cpu-scale-down-alarm" {
    alarm_name          = "nodejs-server-cpu-scale-down-alarm"
    alarm_description   = "nodejs-server-cpu-scale-down-alarm"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods  = "2"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = "120"
    statistic           = "Average"
    threshold           = "5"
    dimensions = {
        "AutoScalingGroupName" = "${aws_autoscaling_group.nodejs-server-asg.name}"
    }
    actions_enabled = true
    alarm_actions   = ["${aws_autoscaling_policy.nodejs-server-cpu-scale-down-policy.arn}"]
}

