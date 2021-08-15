variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "region" {}
variable "vpc_a_cidr_block" {}
variable "vpc_b_cidr_block" {}
variable "ubuntu_account_number" {}
variable "private_key_path" {}
variable "key_name" {}


provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

## VPC creation ##
### VPC A configurations ###
resource "aws_vpc" "vpc_a" {
  cidr_block           = var.vpc_a_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
}

/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig_a" {
  vpc_id = aws_vpc.vpc_a.id
}

/* Elastic IP for NAT */
resource "aws_eip" "nat_eip_a" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig_a]
}

/* NAT */
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_eip_a.id
  subnet_id     = element(aws_subnet.public_subnet_a.*.id, 0)
  depends_on    = [aws_internet_gateway.ig_a]
}


/* Routing table for public subnet */
resource "aws_route_table" "public_a" {
  vpc_id = aws_vpc.vpc_a.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.vpc_a_cidr_block)
  subnet_id      = element(aws_subnet.public_subnet_a.*.id, count.index)
  route_table_id = aws_route_table.public_a.id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_a.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig_a.id
}

/* Public subnet */
resource "aws_subnet" "public_subnet_a" {
  vpc_id     = aws_vpc.vpc_a.id
  cidr_block = var.vpc_a_cidr_block
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
}

### VPC B configurations ###############
resource "aws_vpc" "vpc_b" {
  cidr_block           = var.vpc_b_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
}

/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig_b" {
  vpc_id = aws_vpc.vpc_b.id
}

/* Elastic IP for NAT */
resource "aws_eip" "nat_eip_b" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig_b]
}

/* NAT */
resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_eip_b.id
  subnet_id     = element(aws_subnet.public_subnet_b.*.id, 0)
  depends_on    = [aws_internet_gateway.ig_b]
}


/* Routing table for public subnet */
resource "aws_route_table" "public_b" {
  vpc_id = aws_vpc.vpc_b.id
}

resource "aws_route_table_association" "public_b" {
  count          = length(var.vpc_a_cidr_block)
  subnet_id      = element(aws_subnet.public_subnet_b.*.id, count.index)
  route_table_id = aws_route_table.public_b.id
}

resource "aws_route" "public_internet_gateway_b" {
  route_table_id         = aws_route_table.public_b.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig_b.id
}

/* Public subnet */
resource "aws_subnet" "public_subnet_b" {
  vpc_id     = aws_vpc.vpc_b.id
  cidr_block = var.vpc_b_cidr_block
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
}




/**** VPC peering **************
********************************/

resource "aws_vpc_peering_connection" "owner" {
  vpc_id = aws_vpc.vpc_a.id
  peer_vpc_id   = aws_vpc.vpc_b.id

  tags = {
    Name = "peer_to_vpc_b"
  }
}

resource "aws_vpc_peering_connection_accepter" "accepter" {
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
  auto_accept               = true

  tags = {
    Name = "peer_to_vpc_a"
  }
}

resource "aws_route" "owner" {

  route_table_id            = aws_route_table.public_a.id
  destination_cidr_block    = var.vpc_b_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}

resource "aws_route" "accepter" {
  route_table_id            = aws_route_table.public_b.id
  destination_cidr_block    = var.vpc_a_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}
/***************************
*******VPC peering - end***/

## instance configuration ###
data "aws_ami" "ubuntu-18_04" {
  most_recent = true
  owners      = [var.ubuntu_account_number]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
}

resource "aws_security_group" "sg_nginx" {
  name        = "sg_base_yoink"
  description = "allow http ports"
  vpc_id      = aws_vpc.vpc_a.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "nginx_yoink" {
  ami                    = data.aws_ami.ubuntu-18_04.id
  tags = {
    Name = "bypass server"
  }
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.sg_nginx.id]
  subnet_id              = aws_subnet.public_subnet_a.id
}


resource "aws_security_group" "sg_nginx_vpc_b" {
  name        = "nginx_yoink"
  description = "allow http ports"
  vpc_id      = aws_vpc.vpc_b.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "nginx_b_vpc" {
  ami                    = data.aws_ami.ubuntu-18_04.id
  tags = {
    Name = "nginx_yoink_vpc_b"
  }
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.sg_nginx_vpc_b.id]
  subnet_id              = aws_subnet.public_subnet_b.id
  depends_on = [aws_security_group.sg_nginx_vpc_b]
  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)

  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install nginx -y",
      "echo \"nginx installed\""
    ]
  }
}