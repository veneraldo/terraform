variable "ENV" {
    default = "development"
    type = string
    description = "Environment type e.g. production, staging, etc."
}

variable "VPC_NAME" {
    type = string
    default = "devops-vpc"
}

variable "VPC_CIDR_BLOCK" {
  type = string
  default = "172.20.0.0/16"
  description = "vpc cidr block"
}

variable "REGION" {
    type = string
    default = "ap-southeast-1"
    description = "AWS region to use"
}

variable "PUBLIC_SUBNET_CIDR_BLOCK" {
    type = list(any)
    default = [ "172.20.1.0/24", "172.20.2.0/24", "172.20.3.0/24"]
    description = "public subnet cidr list"
}

variable "PRIVATE_SUBNET_CIDR_BLOCK" {
    type = list(any)
    default = [ "172.20.51.0/24", "172.20.52.0/24", "172.20.53.0/24"]
    description = "private subnet cidr list"
}

//variable "rds_subnet1" {
  //default = "subnet-07714eb09171b1f7e"
//}
//variable "rds_subnet2" {
  //default = "subnet-0cca9fdeb1b95003c"
//}

variable "DB_INSTANCE" {
    type = string
    default = "db.t2.micro"
}
