resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/26"
  tags = {
    Name = "vaultwarden-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = aws_vpc.vpc.cidr_block
  tags = {
    Name = "vaultwarden-subnet"
  }
}

resource "aws_default_route_table" "rtb" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  route {
    cidr_block = aws_vpc.vpc.cidr_block
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# TODO: Add EIP and attach to ENI
#resource "aws_eip" "eip" {
#  domain = "vpc"
#  network_interface =
#  associate_with_private_ip = ""
#}