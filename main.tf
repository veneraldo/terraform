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

//resource "aws_instance" "test-instance" { 
  //ami = "ami-055d15d9cfddf7bd3" 
 // instance_type = "t2.micro" 
  //tags = { 
    //Name = "test-instance"  
   // Owner = var.owner
 // } 
//}

