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
    #count = length(var.PRIVATE_SUBNET_CIDR_BLOCK)
    #subnet_ids = ["${var.rds_subnet1}", "${var.rds_subnet2}"]
    #subnet_ids = [element(aws_subnet.private-subnet.*.id, count.index), ]
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
/*
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
        //backup_retention_period = 10
        //backup_window  = "09:46-10:16"
        //count = length(var.PRIVATE_SUBNET_CIDR_BLOCK)
        //db_subnet_group_name = aws_db_subnet_group.rds-db-subnet-group[count.index].name
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
*/

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
        timeout             = 5
        interval            = 10
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
# to do create listener for https with certificate


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

/*
# create listener rule
resource "aws_alb_listener_rule" "nginx-proxy-listener-rule1" {
    depends_on   = [aws_alb_target_group.nginx-proxy-alb-tg]
    listener_arn = aws_alb_listener.nginx-proxy-alb-listener.arn
    action {
        type  = "forward"
        target_group_arn = aws_alb_target_group.nginx-proxy-alb-tg.id
    }
    condition {
        path_pattern {
        values = ["*work*"]
        }
    }
}

resource "aws_instance" "nginx-reverse-proxy-instance" {
    ami                    = "ami-067f5c3d5a99edc80"
    instance_type          = "t2.micro"
    key_name               = "venerms-key"
    vpc_security_group_ids = ["sg-0dabbfc42efb67652"]
    subnet_id              = "subnet-0e87d62c04db49b80"
    user_data              = file("nginx-install.sh")
    tags = {
        Name = "nginx-reverse-proxy"
    }
}
*/

# create launch configuration for nginx web server
resource "aws_launch_configuration" "nginx-web-asg-launch-config" {
    image_id        = "ami-07f179dc333499419"
    instance_type   = "t3.micro"
    security_groups = ["${aws_security_group.nginx-proxy-alb-sg.id}"]
    user_data  = file("nginx-install.sh")
   /* user_data = <<-EOF
              #!/bin/bash
              yum -y install httpd
              echo "Hello, from auto-scaling group nginx server" > /var/www/html/index.html
              service httpd start
              chkconfig httpd on
              EOF
    */ 
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
    image_id        = "ami-07f179dc333499419"
    instance_type   = "t3.micro"
    security_groups = ["${aws_security_group.nginx-proxy-alb-sg.id}"]
    user_data = <<-EOF
              #!/bin/bash
              yum -y install httpd
              mkdir -p /var/www/html/api
              echo "Hello, from auto-scaling group nodejs server" > /var/www/html/api/index.html
              service httpd start
              chkconfig httpd on
              EOF

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
